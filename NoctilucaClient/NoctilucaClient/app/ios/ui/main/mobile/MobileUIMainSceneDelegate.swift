//
//  MobileUISceneDelegate.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/19/25.
//

#if canImport(UIKit)
import Foundation
import UIKit
import Combine

import SwiftUI

class MobileUIMainSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    var rootViewController: RootViewController? {
        return window?.rootViewController as? RootViewController
    }

    /// mainWindowViewModel.remoteSession 을 observeChanges 로 추적하여 attach 시점에
    /// `onDetachDisplay` 를 주입하고 detach 시점에 SubDisplayCoordinator 를 통해
    /// 연관된 모든 sub-display scene 을 정리한다.
    /// (macOS `AppKitMainWindowController.swift:67-84` 의 iOS 대응 구현.)
    private var lastAttachedSessionID: UUID?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let windowScene = scene as? UIWindowScene {
            let window = UIWindow(windowScene: windowScene)

            let controller = RootViewController()
            window.rootViewController = controller

            self.window = window
            window.makeKeyAndVisible()

            bindRemoteSessionObservation()
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        guard let hidioSession = rootViewController?.mainWindowViewModel?.remoteSession?.hidio?.session else {
            return
        }
        hidioSession.activateSession()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        guard let hidioSession = rootViewController?.mainWindowViewModel?.remoteSession?.hidio?.session else {
            return
        }
        hidioSession.deactivateSession()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // 이 메인 scene 에 귀속된 sub-display scene 들을 정리.
        if let sessionID = lastAttachedSessionID {
            SubDisplayCoordinator.shared.destroyAll(for: sessionID)
            lastAttachedSessionID = nil
        }

        guard let rootViewController = rootViewController else {
            return
        }

        Task { @MainActor in
            await rootViewController.mainWindowViewModel?.stopSession()
        }
    }

    // MARK: - Private

    private func bindRemoteSessionObservation() {
        guard let viewModel = rootViewController?.mainWindowViewModel else { return }

        // viewModel이 @Observable로 전환되어 $remoteSession publisher가 없어졌으므로
        // observeChanges 헬퍼로 프로퍼티 변경을 추적한다.
        observeChanges { [weak self, weak viewModel] in
            guard let self, let viewModel else { return }
            let session = viewModel.remoteSession
            if let session {
                self.lastAttachedSessionID = session.id
                viewModel.onDetachDisplay = { [weak session] displayID in
                    guard let session else { return }
                    try await SubDisplayCoordinator.shared.spawn(sessionID: session.id, displayID: displayID)
                }
            } else {
                // 이전 세션의 sub-display scene 들을 일괄 파기.
                if let previousSessionID = self.lastAttachedSessionID {
                    SubDisplayCoordinator.shared.destroyAll(for: previousSessionID)
                    self.lastAttachedSessionID = nil
                }
                viewModel.onDetachDisplay = nil
            }
        }
    }
}

#endif
