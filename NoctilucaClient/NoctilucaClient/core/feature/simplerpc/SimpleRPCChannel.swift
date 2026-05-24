//
//  SimpleRPCChannel.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 5/23/26.
//

import Foundation
import SiriusKitClient

enum SimpleRPCError: Error {
    /// 응답이 도착했지만 code 가 .success 가 아닙니다.
    case failed(code: SimpleRPCErrorCode, retval: String?)
    /// 응답을 기다리는 중 채널이 닫혔습니다.
    case channelClosed
}

final class SimpleRPCChannel: Channel, ChannelEventConsumer {
    private let logger = NoctilucaLogger(category: "SimpleRPCChannel")

    let handle: ChannelHandle

    let state = SimpleRPCChannelState()

    // Rule I 패턴 2: init 마지막 대입 후 수정 없음.
    nonisolated(unsafe) private var channelEventCompatBridge:
        ChannelEventCompatBridge<SimpleRPCChannel>!

    init(handle: ChannelHandle) {
        self.handle = handle
        assert(handle.direction == .local,
               "SimpleRPCChannel must be opened from client side")

        self.channelEventCompatBridge =
            ChannelEventCompatBridge(consumer: self, handle: handle)
    }

    // MARK: - ChannelEventConsumer

    func handleChannelReady() async {
        await handle.setServiceClass(.default)
    }

    func handleFrame(frame: SiriusFrame) async throws {
        guard frame.isValid() else {
            throw ChannelError.invalidFrame
        }

        switch frame.opcode {
        case .simpleRpcResponse:
            let response = try SimpleRPCResponse.fromProtobufBytes(frame.data)
            let dispatched = await state.dispatchPendingRequest(
                response.requestId, response: response
            )
            if !dispatched {
                logger.warning("No pending request found for requestId: \(response.requestId)")
            }

        case .simpleRpcRequest:
            // 클라이언트는 RPC dispatch 인프라가 없습니다. 들어온 요청은 모두
            // notSupported 로 응답합니다. (decode 실패 시 spec violation 으로 drop.)
            do {
                let request = try SimpleRPCRequest.fromProtobufBytes(frame.data)
                logger.info("Received SimpleRPCRequest (operation=\(request.operation)); replying notSupported")
                let response = SimpleRPCResponse(
                    requestId: request.requestId,
                    code: .notSupported,
                    retval: nil
                )
                try await handle.send(opcode: .simpleRpcResponse, message: response)
            } catch {
                logger.warning("Failed to decode incoming SimpleRPCRequest: \(error)")
            }

        default:
            logger.warning("Unknown opcode: \(frame.opcode.rawValue)")
        }
    }

    func handleError(error: any Error) async {
        logger.error("channel error: \(error)")
        await state.cancelAllPending(with: error)
    }

    func handleStreamClose() async {
        logger.info("SimpleRPCChannel stream closed")
        await state.cancelAllPending(with: SimpleRPCError.channelClosed)
    }

    // MARK: - Public API

    /// 지정한 operation 으로 RPC 요청을 전송하고 응답을 await 합니다.
    ///
    /// 응답의 `code` 가 `.success` 인 경우 `retval` 을 반환하고, 그 외에는
    /// `SimpleRPCError.failed(code:retval:)` 를 throw 합니다.
    ///
    /// 별도의 timeout 처리는 두지 않습니다. 호출 측에서 `Task` cancellation 또는
    /// 외부 timeout 메커니즘으로 제어하십시오.
    func sendRequest(operation: String, args: [String]) async throws -> String? {
        let requestId = UUID()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { [weak self] continuation in
                guard let self = self else {
                    continuation.resume(throwing: SimpleRPCError.channelClosed)
                    return
                }

                Task {
                    await self.state.registerPendingRequest(requestId) { result in
                        switch result {
                        case .success(let response):
                            if response.code == .success {
                                continuation.resume(returning: response.retval)
                            } else {
                                continuation.resume(throwing: SimpleRPCError.failed(
                                    code: response.code,
                                    retval: response.retval
                                ))
                            }
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    }

                    let request = SimpleRPCRequest(
                        requestId: requestId,
                        operation: operation,
                        args: args
                    )

                    do {
                        try await self.handle.send(
                            opcode: .simpleRpcRequest,
                            message: request
                        )
                    } catch {
                        await self.state.removePendingRequest(requestId)
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: { [weak self] in
            Task {
                await self?.state.failPendingRequest(requestId, error: CancellationError())
            }
        }
    }
}
