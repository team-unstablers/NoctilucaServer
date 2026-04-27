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

import SiriusKitClient

@MainActor
class SubDisplayWindow: NSWindow {
    let targetDisplayID: Int
    let mouse: HIDIOAppKitPointer

    weak var hidioController: HIDIOController?

    init(
        displayID: Int,
        remoteSession: RemoteSession,
        subscription: ProjectionSessionSubscription,
        onLost: @escaping () -> Void
    ) {
        self.targetDisplayID = displayID
        self.mouse = HIDIOAppKitPointer()
        self.mouse.localIdentifier = "display-\(displayID)"
        self.mouse.scope = .displayId(Int32(targetDisplayID))

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        self.title = Self.displayTitle(for: displayID, remoteSession: remoteSession)
        self.minSize = NSSize(width: 640, height: 480)
        self.isReleasedWhenClosed = false
        self.center()

        guard let projection = remoteSession.projection,
              let hidio = remoteSession.hidio else { return }

        self.hidioController = hidio.controller
        hidio.controller.connect(mouse)

        let rootView = SubDisplayWindowProjectionRoot(
            remoteSession: remoteSession,
            projection: projection,
            hidio: hidio,
            displayID: displayID,
            mouse: mouse,
            initialSubscription: subscription,
            onLost: onLost
        )
            .environmentObject(SettingsStore.shared)

        self.contentView = NSHostingView(rootView: rootView)
    }

    @MainActor
    deinit {
        hidioController?.disconnect(mouse.identifierString)
    }

    private static func displayTitle(for displayID: Int, remoteSession: RemoteSession) -> String {
        if let projection = remoteSession.projection,
           let displayInfo = projection.channel.displayLayoutManager.displayLayouts[displayID] {
            let name = displayInfo.displayName
            if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return name
            }
        }
        return "Display #\(displayID)"
    }
}

/// SubDisplayWindow 의 contentView 로 사용되는 SwiftUI 루트.
///
/// `subscription` 을 `@State` 로 보유함으로써, backoff 재시도가 성공했을 때 새 subscription
/// 으로 교체하여 NSHostingView 를 다시 그리게 한다. NSWindow 자체는 init 시 contentView 를
/// 한 번만 설정하므로, 동적 subscription 교체는 이 wrapper 가 담당해야 한다.
@MainActor
private struct SubDisplayWindowProjectionRoot: View {
    static let logger = NoctilucaLogger(category: "SubDisplayWindowProjectionRoot")

    let remoteSession: RemoteSession
    let projection: RemoteSession.Projection
    let hidio: RemoteSession.HIDIO
    let displayID: Int
    let mouse: HIDIOAppKitPointer
    let onLost: () -> Void

    @State private var subscription: ProjectionSessionSubscription
    @State private var retryTask: Task<Void, Never>?

    init(
        remoteSession: RemoteSession,
        projection: RemoteSession.Projection,
        hidio: RemoteSession.HIDIO,
        displayID: Int,
        mouse: HIDIOAppKitPointer,
        initialSubscription: ProjectionSessionSubscription,
        onLost: @escaping () -> Void
    ) {
        self.remoteSession = remoteSession
        self.projection = projection
        self.hidio = hidio
        self.displayID = displayID
        self.mouse = mouse
        self.onLost = onLost
        _subscription = State(initialValue: initialSubscription)
    }

    var body: some View {
        RemoteSessionProjectionView(
            remoteSession: remoteSession,
            projection: projection,
            hidio: hidio,
            sourceDescriptor: .constant(.displayID(displayID)),
            subscription: subscription,
            mouse: mouse
        )
        .onChange(of: projection.sessionErrors[displayID]) { _, error in
            guard let error else { return }
            handleError(error)
        }
        .onDisappear {
            retryTask?.cancel()
            retryTask = nil
            subscription.invalidate()
        }
    }

    /// `sessionErrors[displayID]` 가 채워졌을 때의 정책 분기.
    ///
    /// - 디스플레이 자체가 사라짐 → 윈도우 close (`onLost` 콜백)
    /// - 비재시도 reason → 윈도우 close (`onLost`)
    /// - 재시도 가능 → 1s/2s/4s × 3회 backoff retry. 실패 시 윈도우 close.
    private func handleError(_ error: RemoteSession.ProjectionSessionFailureInfo) {
        Self.logger.warning("SubDisplay projection error: displayID=\(displayID), reason=\(error.reason.rawValue), message=\(error.message ?? "(nil)")")

        let layoutManager = projection.channel.displayLayoutManager

        if layoutManager.displayLayouts[displayID] == nil {
            // 디스플레이 자체 분리 → 윈도우 닫기
            onLost()
            return
        }

        guard error.reason.isRetryable else {
            // 비재시도 reason (clientRequested 등) → 윈도우 닫기
            onLost()
            return
        }

        retryTask?.cancel()
        retryTask = Task { @MainActor in
            do {
                let newSubscription = try await projection.subscribeWithBackoff(for: displayID)
                let previous = subscription
                subscription = newSubscription
                previous.invalidate()
            } catch is CancellationError {
                // 사용자 close 등으로 정상 cancel — onLost 는 외부 트리거가 처리
            } catch {
                Self.logger.error("SubDisplay retry failed permanently for display \(displayID): \(error.localizedDescription)")
                onLost()
            }
        }
    }
}

#endif
