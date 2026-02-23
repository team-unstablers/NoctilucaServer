//
//  ProjectionSessionSubscription.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/9/26.
//

import AVFoundation

/// 프로젝션 세션에 대한 구독 객체.
///
/// 각 구독자는 자신만의 `AVSampleBufferDisplayLayer`를 소유하며,
/// `ProjectionSession`은 디코딩된 프레임을 등록된 모든 레이어에 브로드캐스트한다.
class ProjectionSessionSubscription {
    let displayLayer = AVSampleBufferDisplayLayer()
    let session: ProjectionSession
    private let ticket: RemoteSession.SessionReferenceTicket

    var sourceDescriptor: ProjectionSourceDescriptor { session.sourceDescriptor }

    init(session: ProjectionSession, ticket: RemoteSession.SessionReferenceTicket) {
        self.session = session
        self.ticket = ticket
        session.registerDisplayLayer(displayLayer)
    }

    deinit {
        session.unregisterDisplayLayer(displayLayer)
    }
}
