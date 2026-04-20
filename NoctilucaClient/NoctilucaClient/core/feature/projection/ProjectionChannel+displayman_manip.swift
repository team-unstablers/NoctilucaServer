//
//  ProjectionChannel+displayman_manip.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 4/20/26.
//

import Foundation
import SiriusKitClient

// MARK: - Displayman Manipulation (DisplayTransactionRequest/Response)

extension ProjectionChannel {

    /// DisplayTransactionRequest를 전송하고 서버의 DisplayTransactionResponse를 기다립니다.
    ///
    /// - Parameters:
    ///   - operations: 하나의 트랜잭션으로 묶을 DisplayOperation 배열. 서버는 원자적으로 처리합니다.
    ///   - mainDisplayID: 트랜잭션 완료 후 main display로 지정할 displayID (선택).
    ///   - timeout: 서버 응답 대기 시간. 초과 시 `displayTransactionTimedOut`가 throw 됩니다.
    /// - Returns: 성공한 `DisplayTransactionResponse`.
    /// - Throws:
    ///   - `ProjectionChannelError.displayTransactionFailed` — 서버가 `isSuccess=false` 로 응답한 경우.
    ///   - `ProjectionChannelError.displayTransactionTimedOut` — 응답 대기가 `timeout`을 초과한 경우.
    ///   - `CancellationError` — 호출 Task가 취소된 경우.
    ///   - 전송 실패 시 underlying error.
    func requestDisplayTransaction(
        operations: [DisplayOperation],
        mainDisplayID: UInt32? = nil,
        timeout: TimeInterval = 15.0
    ) async throws -> DisplayTransactionResponse {
        let transactionID = UUID()
        let request = DisplayTransactionRequest(
            transactionID: transactionID,
            operations: operations,
            mainDisplayID: mainDisplayID
        )

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { [weak self] continuation in
                guard let self = self else {
                    continuation.resume(throwing: ProjectionChannelError.channelClosed)
                    return
                }

                Task {
                    await self.registerPendingDisplayTransaction(
                        transactionID: transactionID,
                        timeout: timeout,
                        continuation: continuation
                    )

                    do {
                        try await self.handle.send(
                            opcode: .displayTransactionRequest,
                            message: request
                        )
                    } catch {
                        _ = await self.state.failPendingDisplayTransaction(
                            transactionID,
                            error: error
                        )
                    }
                }
            }
        } onCancel: { [weak self] in
            Task {
                _ = await self?.state.failPendingDisplayTransaction(
                    transactionID,
                    error: CancellationError()
                )
            }
        }
    }
}
