//
//  AppStreamWindowManager.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/9/26.
//

#if os(macOS)
import Foundation
import AppKit
import Combine

import SiriusKitClient

@MainActor
class AppStreamWindowManager: NSObject, NSWindowDelegate {
    let logger = NoctilucaLogger(category: "AppStreamWindowManager")
    let remoteSession: RemoteSession

    struct WindowState {
        let window: AppStreamWindow
        let subscription: ProjectionSessionSubscription
        let windowInfoStore: ObservableWindowInfo
        var windowInfo: WindowInfo
    }

    private(set) var windows: [UInt64: WindowState] = [:]
    private var closedWindowIDs: Set<UInt64> = []
    private var streamId: UUID?
    private var eventSubscription: AnyCancellable?
    private var resizeDebounceTask: [UInt64: Task<Void, Never>] = [:]
    private var isHandlingRemoteFocusChange = false

    /// 클라 NSScreen ↔ 호스트 가상 디스플레이 매핑. AppStream 활성 동안만 유효.
    var hostVDMappings: [CGDirectDisplayID: HostVDMapping] = [:]
    /// 우리가 호스트에 만든 VD 의 wire identifier 목록 (stop 시 destroy 용).
    var createdVDIdentifiers: [UUID] = []
    /// LocalDisplayLayoutManager 변경 구독 (Phase 4 실시간 동기화).
    var localDisplayChangeCancellable: AnyCancellable?
    /// 직전 동기화 시점의 NSScreen 스냅샷 (diff 계산용).
    var lastSyncedLocalScreens: [CGDirectDisplayID: LocalScreenInfo] = [:]

    /// 양방향 위치 동기화의 echo 방지: 우리가 setFrameOrigin 으로 적용한 NSWindow Cocoa
    /// origin 을 windowID 별로 기록해 두고, 이어지는 windowDidMove 가 같은 origin 이면
    /// 호스트로 setGeometry 를 다시 보내지 않는다. (서버측 AppStreamWindowAnchor 의 mirror)
    var expectedWindowOrigins: [UInt64: CGPoint] = [:]
    /// windowDidMove debounce — 드래그 도중 setGeometry 폭주 방지.
    var moveDebounceTask: [UInt64: Task<Void, Never>] = [:]

    /// 사용자가 *지금* 마우스 좌버튼을 누르고 있는지 (= 드래그/리사이즈 중일 가능성).
    /// 이 동안 호스트로부터 들어오는 update event 의 위치 매핑은 skip 해, 사용자가
    /// 컨트롤하고 있는 NSWindow 위치를 stale 한 좌표로 덮어쓰지 않게 한다.
    var isUserHoldingMouse: Bool {
        return (NSEvent.pressedMouseButtons & 0x1) != 0
    }

    // 원격 메뉴 스왑 관련 상태
    private var menuBuilder: AppStreamMenuBuilder?
    private var remoteMenu: NSMenu?
    private var remoteMenuRootNodeId: UUID?
    private var accessibilitySubscriptionId: UUID?

    init(remoteSession: RemoteSession) {
        self.remoteSession = remoteSession
        super.init()
    }

    // MARK: - Lifecycle

    func start(bundleId: String) async throws {
        guard let projectionChannel = remoteSession.projection?.channel else {
            return
        }

        // AppStream 시작 *전* 에 클라 NSScreen 레이아웃을 호스트 VD 로 복제한다.
        // 실패해도 throw 하지 않으며, 이 경우 서버는 fallback path 로 단일 VD 자동 생성.
        await provisionHostVirtualDisplays(projectionChannel: projectionChannel)

        let response = try await projectionChannel.startAppStream(
            bundleId: bundleId,
            flags: [.ignoreInvisibleWindows]
        )

        guard response.isSuccess else {
            logger.error("StartAppStream failed: code=\(response.code), message=\(response.message ?? "nil")")
            throw AppStreamError.startFailed(code: response.code, message: response.message)
        }

        self.streamId = response.streamId

        // Z-order: focused 윈도우를 마지막에 생성하여 맨 앞에 오도록 정렬
        let sortedWindows = response.initialWindows.sorted { lhs, rhs in
            let lhsFocused = lhs.flags.contains(.isFocused)
            let rhsFocused = rhs.flags.contains(.isFocused)
            if lhsFocused != rhsFocused { return !lhsFocused }
            return lhs.windowID < rhs.windowID
        }

        for windowInfo in sortedWindows {
            await spawnWindow(windowInfo)
        }

        // 원격 앱 메뉴바 구독 및 로컬 NSMenu 트리 빌드
        await setupRemoteMenu(projectionChannel: projectionChannel)
    }

    /// 원격 메뉴 초기 fetch + Subscribe push 구독.
    /// 실패해도 AppStream 자체는 계속 동작하도록 throw하지 않는다.
    private func setupRemoteMenu(projectionChannel: ProjectionChannel) async {
        do {
            let response = try await projectionChannel.getAccessibilityTree(nodeId: nil)
            guard response.success, let root = response.rootNode else {
                logger.warning("GetAccessibilityTree failed: \(response.errorMessage ?? "nil")")
                return
            }

            let builder = AppStreamMenuBuilder(projectionChannel: projectionChannel)
            self.menuBuilder = builder
            self.remoteMenuRootNodeId = root.id
            self.remoteMenu = builder.buildMenu(from: root)

            let subResponse = try await projectionChannel.subscribeAccessibilityTreeUpdates(
                nodeId: root.id,
                eventMask: [],
                maxDepth: 0
            )
            if subResponse.success {
                self.accessibilitySubscriptionId = subResponse.subscriptionId
            } else {
                logger.warning("SubscribeAccessibilityTreeUpdates failed: \(subResponse.errorMessage ?? "nil")")
            }
        } catch {
            logger.warning("Failed to setup remote menu: \(error)")
        }
    }

    func stop() async {
        // 모든 윈도우 닫기 (스트림 자체를 종료하므로 서버에 close를 보내지 않음)
        let windowIDs = Array(windows.keys)
        for windowID in windowIDs {
            destroyWindow(windowID: windowID, sendCloseToServer: false)
        }

        await teardownRemoteMenu()

        if let projectionChannel = remoteSession.projection?.channel {
            if let streamId = self.streamId {
                _ = try? await projectionChannel.stopAppStream(streamId: streamId)
            }
            // 우리가 만든 가상 디스플레이를 명시적으로 회수.
            // 실패해도 서버 측 cleanupAppStreamSession 안전망이 처리한다.
            await unprovisionHostVirtualDisplays(projectionChannel: projectionChannel)
        }

        self.streamId = nil
        self.closedWindowIDs.removeAll()
    }

    func destroyAll() {
        let windowIDs = Array(windows.keys)
        for windowID in windowIDs {
            destroyWindow(windowID: windowID, sendCloseToServer: false)
        }

        Task { [weak self] in
            await self?.teardownRemoteMenu()
        }

        self.streamId = nil
        self.closedWindowIDs.removeAll()
    }

    /// 원격 메뉴 구독 해제 + 로컬 메뉴 복구.
    private func teardownRemoteMenu() async {
        if let subId = accessibilitySubscriptionId,
           let projectionChannel = remoteSession.projection?.channel {
            _ = try? await projectionChannel.unsubscribeAccessibilityTreeUpdates(subscriptionId: subId)
        }

        (NSApp.delegate as? AppDelegate)?.restoreOriginalMainMenu()

        self.menuBuilder?.reset()
        self.menuBuilder = nil
        self.remoteMenu = nil
        self.remoteMenuRootNodeId = nil
        self.accessibilitySubscriptionId = nil
    }

    // MARK: - Window Management

    private func spawnWindow(_ windowInfo: WindowInfo) async {
        let windowID = windowInfo.windowID

        if closedWindowIDs.contains(windowID) {
            closedWindowIDs.remove(windowID)
        }

        guard windows[windowID] == nil else {
            windows[windowID]?.window.makeKeyAndOrderFront(nil)
            return
        }

        guard let projection = remoteSession.projection else { return }

        do {
            let subscription = try await projection.subscribeProjectionSession(
                for: .windowID(Int(windowID))
            )

            let windowInfoStore = ObservableWindowInfo(windowInfo)

            let window = AppStreamWindow(
                windowID: Int(windowID),
                remoteSession: remoteSession,
                subscription: subscription,
                windowInfoStore: windowInfoStore
            )

            // 서버 bounds 의 크기 반영 + 위치는 호스트 VD ↔ 클라 NSScreen 매핑이
            // 있으면 1:1 변환, 없으면 NSWindow 의 기본 .center() 위치 유지.
            let serverBounds = windowInfo.bounds.cgRect
            if serverBounds.size.width > 0 && serverBounds.size.height > 0 {
                window.setContentSize(serverBounds.size)
            }

            if let cocoaOrigin = translateServerFrameToClientOrigin(serverBounds: serverBounds) {
                expectedWindowOrigins[windowID] = cocoaOrigin
                window.setFrameOrigin(cocoaOrigin)
            }

            window.delegate = self
            window.title = windowInfo.windowTitle

            windows[windowID] = WindowState(
                window: window,
                subscription: subscription,
                windowInfoStore: windowInfoStore,
                windowInfo: windowInfo
            )
            window.makeKeyAndOrderFront(nil)
        } catch {
            logger.warning("Failed to spawn AppStream window \(windowID): \(error)")
        }
    }

    private func destroyWindow(windowID: UInt64, sendCloseToServer: Bool) {
        resizeDebounceTask[windowID]?.cancel()
        resizeDebounceTask.removeValue(forKey: windowID)
        moveDebounceTask[windowID]?.cancel()
        moveDebounceTask.removeValue(forKey: windowID)
        expectedWindowOrigins.removeValue(forKey: windowID)

        if sendCloseToServer {
            closedWindowIDs.insert(windowID)
        }

        // 딕셔너리에서 먼저 제거하여 windowWillClose → destroyWindow 재귀 호출 방지
        guard let state = windows.removeValue(forKey: windowID) else { return }
        state.subscription.invalidate()
        state.window.close()

        if sendCloseToServer {
            Task { [weak self] in
                guard let projectionChannel = self?.remoteSession.projection?.channel else { return }
                try? await projectionChannel.sendWindowManipulation(
                    windowID: windowID,
                    operation: .stateCommand(.close)
                )
            }
        }
    }

    private func updateWindow(windowID: UInt64, info: WindowInfo) {
        guard windows[windowID] != nil else { return }

        windows[windowID]?.windowInfo = info
        windows[windowID]?.windowInfoStore.windowInfo = info
        windows[windowID]?.window.title = info.windowTitle

        // 서버에서 크기가 변경되었으면 클라이언트 윈도우 크기도 반영
        let serverBounds = info.bounds.cgRect
        let serverSize = serverBounds.size
        if serverSize.width > 0 && serverSize.height > 0 {
            let currentSize = windows[windowID]?.window.contentView?.frame.size ?? .zero
            // 리사이즈 무한 루프 방지: 1pt 이하 차이는 무시
            if abs(currentSize.width - serverSize.width) > 1 ||
               abs(currentSize.height - serverSize.height) > 1 {
                windows[windowID]?.window.setContentSize(serverSize)
            }
        }

        // 서버에서 위치가 변경되었으면 매핑된 클라 NSScreen 안에서 1:1 추적.
        // 단, 사용자가 마우스를 누르고 드래그 중일 가능성이 있으면 (= mouse down 상태)
        // backlog 된 stale update event 가 사용자의 현재 위치를 덮어쓰지 못하도록 skip.
        // 매핑이 없거나 어느 VD 와도 교차하지 않으면 위치는 그대로 둔다.
        if !isUserHoldingMouse,
           let cocoaOrigin = translateServerFrameToClientOrigin(serverBounds: serverBounds),
           let window = windows[windowID]?.window {
            let currentOrigin = window.frame.origin
            if abs(currentOrigin.x - cocoaOrigin.x) > 1 ||
               abs(currentOrigin.y - cocoaOrigin.y) > 1 {
                // setFrameOrigin 이 windowDidMove 를 트리거하므로 echo 방지를 위해 마커 등록.
                expectedWindowOrigins[windowID] = cocoaOrigin
                window.setFrameOrigin(cocoaOrigin)
            }
        }

        // 포커스 처리: isFocused이면 key window로 전환
        if info.flags.contains(.isFocused), !(windows[windowID]?.window.isKeyWindow ?? false) {
            isHandlingRemoteFocusChange = true
            windows[windowID]?.window.makeKeyAndOrderFront(nil)
            isHandlingRemoteFocusChange = false
        }
    }

    // MARK: - Event Subscription

    func handleAppStreamWindowEvent(_ event: AppStreamWindowEvent) {
        guard event.streamId == self.streamId else { return }

        switch event.eventType {
        case .appeared:
            guard let info = event.info else { return }
            Task { [weak self] in
                await self?.spawnWindow(info)
            }

        case .disappeared:
            destroyWindow(windowID: event.windowId, sendCloseToServer: false)

        case .updated:
            guard let info = event.info else { return }
            updateWindow(windowID: event.windowId, info: info)

        default:
            break
        }
    }

    /// Accessibility tree update 이벤트 처리. 현재 구현은 루트 메뉴바 전체 재구성에 한정한다.
    func handleAccessibilityTreeUpdateEvent(_ event: AccessibilityTreeUpdateEvent) {
        guard let builder = menuBuilder else { return }
        guard let currentRootId = remoteMenuRootNodeId else { return }

        // 서버는 현재 childrenChanged(루트) 단일 이벤트로 메뉴 재스냅샷을 송신한다.
        // nodeId가 루트와 일치하고 updatedNode가 있으면 전체 메뉴를 교체한다.
        guard event.nodeId == currentRootId,
              let updatedNode = event.updatedNode else {
            // 일부 서브트리 업데이트는 캐시 무효화만 수행해 다음 open 시 재fetch되도록 한다.
            builder.invalidate(nodeId: event.nodeId)
            return
        }

        // 새 빌더로 교체 — 기존 NSMenu 인스턴스 객체는 버리고 새로 빌드 (가장 단순하고 안전)
        builder.reset()
        self.remoteMenuRootNodeId = updatedNode.id

        let newBuilder = AppStreamMenuBuilder(
            projectionChannel: (remoteSession.projection?.channel)!
        )
        self.menuBuilder = newBuilder
        let newMenu = newBuilder.buildMenu(from: updatedNode)
        self.remoteMenu = newMenu

        // 현재 AppStreamWindow가 key이면 즉시 적용
        if NSApp.keyWindow is AppStreamWindow {
            (NSApp.delegate as? AppDelegate)?.installRemoteMainMenu(newMenu)
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? AppStreamWindow else { return }

        remoteSession.hidio?.session.activateSession()

        // 원격 메뉴 스왑
        if let remoteMenu {
            (NSApp.delegate as? AppDelegate)?.installRemoteMainMenu(remoteMenu)
        }

        // 서버에서 온 포커스 변경이면 서버로 재전송하지 않음 (무한 루프 방지)
        guard !isHandlingRemoteFocusChange else { return }

        guard let projectionChannel = remoteSession.projection?.channel else { return }
        Task {
            try? await projectionChannel.sendWindowManipulation(
                windowID: UInt64(window.windowID),
                operation: .focus(true)
            )
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard notification.object is AppStreamWindow else { return }
        remoteSession.hidio?.session.deactivateSession()

        // 포커스가 다른 AppStreamWindow로 이동했는지 확인. 아니면 원본 메뉴로 복구.
        // NSApp.keyWindow는 이 시점에는 아직 nil/이전 window일 수 있으므로 한 틱 뒤에 확인.
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            let newKey = NSApp.keyWindow
            if !(newKey is AppStreamWindow) {
                (NSApp.delegate as? AppDelegate)?.restoreOriginalMainMenu()
            }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let window = sender as? AppStreamWindow else { return true }

        // 실제로 닫지 않고 서버에 close 요청만 전송
        // 서버 앱이 실제로 닫히면 disappeared 이벤트로 로컬 윈도우 정리
        let windowID = UInt64(window.windowID)
        closedWindowIDs.insert(windowID)
        Task { [weak self] in
            guard let projectionChannel = self?.remoteSession.projection?.channel else { return }
            try? await projectionChannel.sendWindowManipulation(
                windowID: windowID,
                operation: .stateCommand(.close)
            )
        }

        return false
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? AppStreamWindow else { return }
        destroyWindow(windowID: UInt64(window.windowID), sendCloseToServer: false)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? AppStreamWindow else { return }
        let windowID = UInt64(window.windowID)
        let contentSize = window.contentView?.frame.size ?? window.frame.size

        resizeDebounceTask[windowID]?.cancel()
        resizeDebounceTask[windowID] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            guard let projectionChannel = self.remoteSession.projection?.channel else { return }

            let hostRect = self.translateClientFrameToServerRect(
                window: window,
                contentSize: contentSize
            ) ?? SRRect(
                x: 0, y: 0,
                width: Double(contentSize.width),
                height: Double(contentSize.height)
            )
            try? await projectionChannel.sendWindowManipulation(
                windowID: windowID,
                operation: .setGeometry(hostRect)
            )
        }
    }

    /// 사용자가 NSWindow 를 드래그할 때 호출. drag 중 매 프레임 호출되므로 debounce 한다.
    /// echo 방지: 직전에 우리가 setFrameOrigin 으로 적용한 origin 과 일치하면 송신하지 않는다.
    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? AppStreamWindow else { return }
        let windowID = UInt64(window.windowID)

        // setFrameOrigin 으로 인한 self-triggered move 인지 확인.
        if let expected = expectedWindowOrigins[windowID] {
            let current = window.frame.origin
            if abs(current.x - expected.x) < 0.5 && abs(current.y - expected.y) < 0.5 {
                expectedWindowOrigins.removeValue(forKey: windowID)
                return
            }
        }

        // 사용자 드래그 — debounce 후 호스트로 좌표 송신.
        moveDebounceTask[windowID]?.cancel()
        moveDebounceTask[windowID] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            guard let projectionChannel = self.remoteSession.projection?.channel else { return }
            guard let hostRect = self.translateClientFrameToServerRect(
                window: window,
                contentSize: window.contentView?.frame.size ?? window.frame.size
            ) else {
                // 매핑이 없으면 호스트 측 위치는 손대지 않는다.
                return
            }
            try? await projectionChannel.sendWindowManipulation(
                windowID: windowID,
                operation: .setGeometry(hostRect)
            )
        }
    }

    /// NSWindow 의 *현재* 위치/크기를 호스트 글로벌 좌표 (top-left) `SRRect` 로 변환.
    /// 매핑된 NSScreen 이 없거나 window 가 어느 NSScreen 과도 교차하지 않으면 nil 반환.
    private func translateClientFrameToServerRect(
        window: NSWindow,
        contentSize: CGSize
    ) -> SRRect? {
        // NSWindow 가 속한 NSScreen 찾기 (가장 많이 겹치는 화면).
        guard let nsScreen = window.screen ?? NSScreen.main else { return nil }
        guard let screenDisplayID = nsScreen.compatibleDisplayID else { return nil }
        guard let mapping = hostVDMappings[screenDisplayID] else { return nil }

        // NSWindow.frame 은 frame (title bar 포함) 의 bottom-left.
        // contentView 좌상단 (Cocoa) = window.frame.origin.x, window.frame.maxY - titleBarHeight
        // 그러나 호스트 측 setWindowFrame 은 *frame 전체* (title 포함) 의 top-left 기준이라
        // window.frame 그대로 변환해도 무방. AX kAXPositionAttribute 도 frame top-left.
        let frame = window.frame

        // Cocoa bottom-left → NSScreen 내부 top-left.
        // intra.x = frame.origin.x - nsScreen.frame.origin.x
        // intra.y = nsScreen.frame.maxY - frame.maxY
        let intraX = frame.origin.x - nsScreen.frame.origin.x
        let intraY = nsScreen.frame.maxY - frame.maxY

        // 호스트 VD origin + intra → 호스트 글로벌 top-left.
        let hostX = mapping.hostFrame.origin.x + intraX
        let hostY = mapping.hostFrame.origin.y + intraY

        return SRRect(
            x: Double(hostX),
            y: Double(hostY),
            width: Double(contentSize.width),
            height: Double(contentSize.height)
        )
    }
}

// MARK: - Error

enum AppStreamError: Error {
    case startFailed(code: UInt32, message: String?)
}

#endif
