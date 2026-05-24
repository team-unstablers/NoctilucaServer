//
//  FSAccessConsentBroker.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 5/4/26.
//

import Foundation

import SiriusKitClient

/// 클라이언트 사용자에게 mount 요청 동의를 받기 위한 추상화.
///
/// 구현체는 (보통) `RemoteSession` 이며, 실제로는 SwiftUI 시트를 띄워 사용자 결정을 기다린다.
/// 채널 측은 해당 결정이 어떤 UI 로 표시되는지 알 필요가 없도록 protocol 로 분리했다.
protocol FSAccessConsentBroker: AnyObject, Sendable {
    @MainActor
    func requestConsent(_ request: FSAccessConsentRequest) async -> FSAccessConsentDecision
}

/// Consent 다이얼로그에 전달되는 모델.
struct FSAccessConsentRequest: Identifiable, Sendable {
    let id: UUID
    let entryName: String
    let entryPath: String
    let requestedAccess: AccessMode
    let reason: String?

    init(
        id: UUID = UUID(),
        entryName: String,
        entryPath: String,
        requestedAccess: AccessMode,
        reason: String?
    ) {
        self.id = id
        self.entryName = entryName
        self.entryPath = entryPath
        self.requestedAccess = requestedAccess
        self.reason = reason
    }
}

/// Consent 결과.
enum FSAccessConsentDecision: Sendable {
    case allow(grantedAccess: AccessMode)
    case deny
}
