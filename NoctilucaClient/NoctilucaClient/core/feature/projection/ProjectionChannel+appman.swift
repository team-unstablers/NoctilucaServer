//
//  ProjectionChannel+appman.swift
//  NoctilucaClient
//

import Foundation
import Combine
import SiriusKitClient

// MARK: - AppStream Request/Response

extension ProjectionChannel {

    // MARK: Application List

    /// 서버의 AppStream 허용 앱 목록을 조회한다. 서버는 단일 응답(`isLastPage = true`)으로
    /// 모든 항목을 반환한다.
    func getApplicationList(
        flags: ApplicationListRequestFlags = [.includeIcons]
    ) async throws -> ApplicationListResponse {
        let requestID = nextRequestID()

        return try await self.sendRequest(
            requestID: requestID,
            opcode: .applicationListRequest,
            message: ApplicationListRequest(
                requestId: requestID,
                flags: flags
            )
        )
    }

    // MARK: AppStream Lifecycle

    func startAppStream(
        bundleId: String,
        flags: AppStreamFlags = [.ignoreInvisibleWindows]
    ) async throws -> StartAppStreamResponse {
        let requestID = nextRequestID()

        return try await self.sendRequest(
            requestID: requestID,
            opcode: .startAppStreamRequest,
            message: StartAppStreamRequest(
                requestId: requestID,
                bundleId: bundleId,
                flags: flags
            )
        )
    }

    func stopAppStream(streamId: UUID) async throws -> StopAppStreamResponse {
        let requestID = nextRequestID()

        return try await self.sendRequest(
            requestID: requestID,
            opcode: .stopAppStreamRequest,
            message: StopAppStreamRequest(
                requestId: requestID,
                streamId: streamId
            )
        )
    }

    // MARK: Window Manipulation (fire-and-forget)

    /// WindowManipulationResponse에 requestID가 없으므로 sendRequest 패턴을 쓸 수 없음.
    /// fire-and-forget으로 전송한다.
    func sendWindowManipulation(
        windowID: UInt64,
        operation: WindowManipulationRequest.Operation
    ) async throws {
        try await self.handle.send(
            opcode: .windowManipulationRequest,
            message: WindowManipulationRequest(
                windowID: windowID,
                operation: operation,
                extraArgs: [:],
                flags: 0
            )
        )
    }

    // MARK: Event Handlers

    func handleAppStreamWindowEvent(_ event: AppStreamWindowEvent) async {
        continuation.yield(.appStreamWindowEvent(event))
    }
}
