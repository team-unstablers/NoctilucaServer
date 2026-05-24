//
//  SubDisplayWindow.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/9/26.
//

#if os(macOS)

import Foundation
import AppKit
import SwiftUI
import Combine

import SiriusKitClient

@MainActor
class ObservableWindowInfo: ObservableObject {
    @Published var windowInfo: WindowInfo

    init(_ windowInfo: WindowInfo) {
        self.windowInfo = windowInfo
    }
}

@MainActor
class AppStreamWindow: NSWindow {
    let windowID: Int
    let mouse: HIDIOAppKitPointer
    let windowInfoStore: ObservableWindowInfo

    weak var hidioController: HIDIOController?

    /// 현재 표시 중인 컨텍스트 메뉴와 그 menuId. ContextMenu 종료(.nodeRemoved) 알림 수신 시 매칭에 사용.
    fileprivate(set) var activeContextMenu: NSMenu?
    fileprivate(set) var activeContextMenuID: UUID?

    init(windowID: Int, remoteSession: RemoteSession, subscription: ProjectionSessionSubscription, windowInfoStore: ObservableWindowInfo) {
        self.windowID = windowID
        self.windowInfoStore = windowInfoStore
        self.mouse = HIDIOAppKitPointer()
        self.mouse.localIdentifier = "window-\(windowID)"
        self.mouse.scope = .windowId(Int64(windowID))

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: Self.styleMask(for: windowInfoStore.windowInfo.flags),
            backing: .buffered,
            defer: false
        )

        self.title = Self.displayTitle(for: windowID, remoteSession: remoteSession)

        // borderless 윈도우엔 fullSizeContentView 가 의미가 없고, titlebar 관련 옵션은
        // .titled 이 아닐 때 무시되거나 경고가 발생할 수 있으므로 가드.
        if self.styleMask.contains(.titled) {
            self.styleMask.insert(.fullSizeContentView)
            self.titlebarAppearsTransparent = true
            self.titleVisibility = .hidden
        }
        
        // self.minSize = NSSize(width: 640, height: 480)
        self.isReleasedWhenClosed = false
        self.center()

        guard let projection = remoteSession.projection,
              let hidio = remoteSession.hidio else { return }
        
        self.hidioController = hidio.controller
        hidio.controller.connect(mouse)

        let rootView = ZStack(alignment: .topTrailing) {
            RemoteSessionProjectionView(
                remoteSession: remoteSession,
                projection: projection,
                hidio: hidio,
                sourceDescriptor: .constant(.windowID(windowID)),
                subscription: subscription,
                mouse: mouse
            )

            AppStreamWindowInfoOverlayContainer(store: windowInfoStore)
        }
        .ignoresSafeArea(.all)
        .environmentObject(SettingsStore.shared)

        self.contentView = NSHostingView(rootView: rootView)
    }
    
    @MainActor
    deinit {
        hidioController?.disconnect(mouse.identifierString)
    }

    /// 사용자가 마우스 좌버튼을 *놓은* 시점을 detect 해 pending 한 windowDidMove
    /// debounce 를 즉시 flush 한다 — 짧고 빠른 드래그에서 setGeometry 가 늦게
    /// 송신되어 stale update event 에 의해 NSWindow 가 원위치로 워프하는 문제를
    /// 방지한다.
    override func sendEvent(_ event: NSEvent) {
        super.sendEvent(event)
        if event.type == .leftMouseUp {
            (delegate as? AppStreamWindowManager)?.flushPendingMove(windowID: UInt64(windowID))
        }
    }

    private static func displayTitle(for windowID: Int, remoteSession: RemoteSession) -> String {
        return "AppStream Window (streaming #\(windowID))"
    }

    // MARK: - Context Menu (popup) 표시

    /// 호스트의 popup 메뉴를 클라 native NSMenu 로 표시한다.
    /// `screenPoint` 는 클라 NSScreen 좌표계의 popup 좌상단(Cocoa 기준; `translateServerFrameToClientOrigin` 결과).
    ///
    /// `NSMenu.popUp(positioning:at:in:)` 은 메뉴 트래킹 동안 main run loop 를 modal 로 block 하므로,
    /// 호출이 return 한 시점이 곧 메뉴 close 시점이다.
    func showContextMenu(_ menu: NSMenu, atScreenPoint screenPoint: NSPoint, menuId: UUID) {
        guard let anchor = self.contentView else { return }

        // 동시에 여러 popup 은 1차 범위 외. 기존 메뉴가 떠 있으면 먼저 닫는다.
        if let existing = self.activeContextMenu {
            existing.cancelTracking()
        }

        // screen → window → contentView 좌표
        let windowPoint = self.convertPoint(fromScreen: screenPoint)
        let viewPoint = anchor.convert(windowPoint, from: nil)

        self.activeContextMenu = menu
        self.activeContextMenuID = menuId

        menu.popUp(positioning: nil, at: viewPoint, in: anchor)

        // popUp 이 return 했다는 것은 menu tracking 이 끝났다는 의미. 호출자가 후속 동기화
        // (cancel action 송신 여부 등) 를 결정한다.
        self.activeContextMenu = nil
        self.activeContextMenuID = nil
    }

    /// 호스트로부터 popup close 알림(AccessibilityTreeUpdateEvent .nodeRemoved)이 도착했을 때 호출.
    /// `menuId` 가 매칭되면 표시 중인 NSMenu 의 트래킹을 종료한다.
    func cancelContextMenu(matching menuId: UUID) {
        guard self.activeContextMenuID == menuId else { return }
        self.activeContextMenu?.cancelTracking()
    }

    /// 서버가 보고한 `WindowInfoFlags` 를 NSWindow.StyleMask 로 변환한다.
    /// `noWindowDecoration` 이 set 이면 신호등이 없는 borderless 윈도우로 만든다.
    private static func styleMask(for flags: WindowInfoFlags) -> NSWindow.StyleMask {
        if flags.contains(.noWindowDecoration) {
            return [.borderless, .resizable]
        }

        var mask: NSWindow.StyleMask = [.titled, .closable, .resizable]
        if !flags.contains(.cannotMinimize) {
            mask.insert(.miniaturizable)
        }
        return mask
    }
}

#endif
