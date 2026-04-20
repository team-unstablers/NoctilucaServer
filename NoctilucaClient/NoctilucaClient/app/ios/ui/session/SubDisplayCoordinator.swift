//
//  SubDisplayCoordinator.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 4/20/26.
//

#if os(iOS)

import Foundation
import UIKit

import SiriusKitClient

/// iPadOS 환경에서 원격 디스플레이를 별도 `UIWindowScene` 으로 띄우기 위한 중앙 조정자.
///
/// 메인 씬에서 `spawn(sessionID:displayID:)` 을 호출하면, `ProjectionSessionSubscription` 을
/// 미리 생성해 `pending` 에 보관한 뒤 시스템에 새 scene 활성화를 요청한다.
/// 새 scene 의 `UISceneDelegate` 가 `consume(...)` 을 호출하면 해당 subscription 의 소유권을
/// scene delegate 측으로 이관한다.
@MainActor
final class SubDisplayCoordinator {
    static let shared = SubDisplayCoordinator()

    private let logger = NoctilucaLogger(category: "SubDisplayCoordinator")

    static let activityType = "app.noctiluca.client.sub-display"

    enum UserInfoKey {
        static let sessionID = "sessionID"
        static let displayID = "displayID"
    }

    struct Key: Hashable {
        let sessionID: UUID
        let displayID: Int
    }

    /// spawn → sceneDidConnect 사이의 subscription 홀딩소.
    /// scene delegate 가 consume 하면 제거.
    private var pending: [Key: ProjectionSessionSubscription] = [:]

    /// 현재 활성화된 sub-display scene 의 key → UISceneSession 매핑.
    /// 재활성화(foreground), 세션 종료 시 일괄 destroy 등에 사용.
    private var connected: [Key: UISceneSession] = [:]

    private init() {}

    /// DisplaySwitcherSheet 의 `onDetach` 에서 호출.
    /// - 이미 해당 (sessionID, displayID) 에 대한 scene 이 존재하면 activation 요청만 보냄.
    /// - 아니면 subscription 을 새로 생성해 pending 에 저장하고 scene 생성 요청.
    func spawn(sessionID: UUID, displayID: Int) async throws {
        let key = Key(sessionID: sessionID, displayID: displayID)

        if let existing = connected[key] {
            logger.info("Reactivating existing sub-display scene for \(sessionID).\(displayID)")
            UIApplication.shared.requestSceneSessionActivation(existing, userActivity: nil, options: nil, errorHandler: { [weak self] error in
                self?.logger.error("Failed to reactivate sub-display scene: \(error.localizedDescription)")
            })
            return
        }

        guard let session = RemoteSessionManager.shared.sessions[sessionID] else {
            throw SubDisplayCoordinatorError.unknownSession(sessionID)
        }
        guard let projection = session.projection else {
            throw SubDisplayCoordinatorError.projectionNotAvailable
        }

        let subscription = try await projection.subscribeProjectionSession(for: displayID)
        pending[key] = subscription

        let activity = NSUserActivity(activityType: Self.activityType)
        activity.userInfo = [
            UserInfoKey.sessionID: sessionID.uuidString,
            UserInfoKey.displayID: displayID
        ]

        UIApplication.shared.requestSceneSessionActivation(
            nil,
            userActivity: activity,
            options: nil,
            errorHandler: { [weak self] error in
                guard let self else { return }
                self.logger.error("Failed to activate sub-display scene: \(error.localizedDescription)")
                // 시스템이 scene 을 생성하지 못했으므로 pending 의 subscription 을 즉시 정리한다.
                Task { @MainActor in
                    if let stale = self.pending.removeValue(forKey: key) {
                        stale.invalidate()
                    }
                }
            }
        )
    }

    /// `SubDisplayUISceneDelegate.scene(_:willConnectTo:options:)` 에서 호출.
    /// - 성공 시 `(RemoteSession, ProjectionSessionSubscription)` 반환 및 connected 테이블 업데이트.
    /// - 실패 시 (pending 없음 / 세션 유실 등) nil 반환. 호출자는 scene 파기 요청.
    func consume(sessionID: UUID, displayID: Int, scene: UISceneSession) -> (RemoteSession, ProjectionSessionSubscription)? {
        let key = Key(sessionID: sessionID, displayID: displayID)

        guard let subscription = pending.removeValue(forKey: key) else {
            logger.warning("consume: no pending subscription for \(sessionID).\(displayID)")
            return nil
        }
        guard let session = RemoteSessionManager.shared.sessions[sessionID] else {
            logger.warning("consume: session \(sessionID) no longer registered, invalidating subscription")
            subscription.invalidate()
            return nil
        }

        connected[key] = scene
        return (session, subscription)
    }

    /// `SubDisplayUISceneDelegate.sceneDidDisconnect` 에서 호출.
    /// 실제 subscription invalidate 는 scene delegate 가 수행하고, 여기서는 매핑 테이블 정리만.
    func release(scene: UISceneSession) {
        guard let entry = connected.first(where: { $0.value === scene }) else { return }
        connected.removeValue(forKey: entry.key)
    }

    /// RemoteSession 종료 시 해당 세션에 속한 모든 sub-display scene 을 파기한다.
    /// (B안: 메인 연결이 끊기면 sub-display 도 같이 정리)
    func destroyAll(for sessionID: UUID) {
        // pending 정리
        let pendingVictims = pending.filter { $0.key.sessionID == sessionID }
        for (key, subscription) in pendingVictims {
            subscription.invalidate()
            pending.removeValue(forKey: key)
        }

        // connected scene 파기 요청
        let connectedVictims = connected.filter { $0.key.sessionID == sessionID }
        for (_, sceneSession) in connectedVictims {
            UIApplication.shared.requestSceneSessionDestruction(sceneSession, options: nil, errorHandler: { [weak self] error in
                self?.logger.error("Failed to destroy sub-display scene: \(error.localizedDescription)")
            })
        }
    }

    /// 특정 sub-display 를 명시적으로 파기한다 (향후 UI 에서 개별 close 지원 시 사용).
    func destroy(sessionID: UUID, displayID: Int) {
        let key = Key(sessionID: sessionID, displayID: displayID)
        if let subscription = pending.removeValue(forKey: key) {
            subscription.invalidate()
        }
        if let sceneSession = connected.removeValue(forKey: key) {
            UIApplication.shared.requestSceneSessionDestruction(sceneSession, options: nil, errorHandler: { [weak self] error in
                self?.logger.error("Failed to destroy sub-display scene: \(error.localizedDescription)")
            })
        }
    }
}

enum SubDisplayCoordinatorError: LocalizedError {
    case unknownSession(UUID)
    case projectionNotAvailable

    var errorDescription: String? {
        switch self {
        case .unknownSession(let id):
            return "No RemoteSession registered for id \(id)"
        case .projectionNotAvailable:
            return "RemoteSession.projection is not available yet"
        }
    }
}

#endif
