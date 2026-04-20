//
//  SubDisplayUISceneDelegate.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 4/20/26.
//

#if os(iOS)

import Foundation
import UIKit
import SwiftUI

import SiriusKitClient

/// iPadOS 에서 원격 디스플레이를 별도 scene 으로 렌더링하는 UISceneDelegate.
///
/// 생명주기:
/// - `willConnectTo`: userActivity 에서 (sessionID, displayID) 파싱 → `SubDisplayCoordinator.consume` 으로
///   subscription/remoteSession 획득 → per-scene `HIDIOUIKitMouse` 생성 후 controller 에 connect →
///   `RemoteSessionProjectionView` 를 `UIHostingController` 로 래핑.
/// - `sceneDidBecomeActive` / `sceneWillResignActive`: HIDIO session 활성/비활성 토글.
/// - `sceneDidDisconnect`: subscription invalidate, mouse disconnect, coordinator release.
@MainActor
final class SubDisplayUISceneDelegate: UIResponder, UIWindowSceneDelegate {
    private let logger = NoctilucaLogger(category: "SubDisplayUISceneDelegate")

    var window: UIWindow?

    private var remoteSession: RemoteSession?
    private var subscription: ProjectionSessionSubscription?
    private var mouse: HIDIOUIKitMouse?
    private weak var hidioController: HIDIOController?

    /// `RemoteSessionProjectionView` 의 `@EnvironmentObject`(SessionWindowViewModel) 요구사항을
    /// 충족하기 위해 메인 씬의 뷰모델을 그대로 공유한다. (UX 상 sub-display 에서는 fullscreen 등 상태가
    /// 별도 의미를 가지지 않지만, 뷰 계층 차원의 요구사항만 만족시키면 충분함.)
    private var mainWindowViewModel: SessionWindowViewModel?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else {
            logger.error("scene is not UIWindowScene")
            return
        }

        // 1. userActivity 에서 sessionID / displayID 추출
        let activity = connectionOptions.userActivities.first(where: { $0.activityType == SubDisplayCoordinator.activityType })
            ?? session.stateRestorationActivity

        guard let activity,
              let sessionIDString = activity.userInfo?[SubDisplayCoordinator.UserInfoKey.sessionID] as? String,
              let sessionID = UUID(uuidString: sessionIDString),
              let displayID = activity.userInfo?[SubDisplayCoordinator.UserInfoKey.displayID] as? Int else {
            logger.warning("Missing or invalid sub-display userActivity, destroying scene")
            UIApplication.shared.requestSceneSessionDestruction(session, options: nil, errorHandler: nil)
            return
        }

        // 2. coordinator 에서 subscription / remoteSession 소유권 획득
        guard let (remoteSession, subscription) = SubDisplayCoordinator.shared.consume(sessionID: sessionID, displayID: displayID, scene: session) else {
            logger.warning("consume failed for \(sessionID).\(displayID), destroying scene")
            UIApplication.shared.requestSceneSessionDestruction(session, options: nil, errorHandler: nil)
            return
        }

        guard let projection = remoteSession.projection,
              let hidio = remoteSession.hidio else {
            logger.warning("projection or hidio missing on remoteSession, destroying scene")
            subscription.invalidate()
            UIApplication.shared.requestSceneSessionDestruction(session, options: nil, errorHandler: nil)
            return
        }

        // 3. per-scene mouse 생성 및 controller 에 연결
        let mouse = HIDIOUIKitMouse()
        mouse.localIdentifier = "display-\(displayID)"
        mouse.scope = .displayId(Int32(displayID))
        hidio.controller.connect(mouse)

        self.remoteSession = remoteSession
        self.subscription = subscription
        self.mouse = mouse
        self.hidioController = hidio.controller
        self.mainWindowViewModel = remoteSession.parent

        // 4. 타이틀
        windowScene.title = Self.titleFor(displayID: displayID, remoteSession: remoteSession)

        // 5. SwiftUI 뷰 구성
        let viewModel = self.mainWindowViewModel ?? SessionWindowViewModel()
        let rootView = RemoteSessionProjectionView(
            remoteSession: remoteSession,
            projection: projection,
            hidio: hidio,
            sourceDescriptor: .constant(.displayID(displayID)),
            subscription: subscription,
            mouse: mouse
        )
        .environmentObject(SettingsStore.shared)
        .environment(viewModel)

        let hostingController = UIHostingController(rootView: AnyView(rootView))

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = hostingController
        self.window = window
        window.makeKeyAndVisible()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        remoteSession?.hidio?.session.activateSession()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        remoteSession?.hidio?.session.deactivateSession()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // B안: subscription 즉시 invalidate 하여 서버측 스트림 정리
        subscription?.invalidate()
        subscription = nil

        if let mouse, let controller = hidioController {
            controller.disconnect(mouse.identifierString)
        }
        mouse = nil
        hidioController = nil

        SubDisplayCoordinator.shared.release(scene: scene.session)
        remoteSession = nil
        mainWindowViewModel = nil
    }

    private static func titleFor(displayID: Int, remoteSession: RemoteSession) -> String {
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

#endif
