//
//  ProjectionChannel.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/12/25.
//

import Foundation
import Atomics

import CoreGraphics

import SiriusKitClient

enum ProjectionChannelError: Error {
    case sessionCreationCancelled
    case channelClosed
    case audioSessionCreationFailed(identifier: UUID, reason: AudioSessionFailureReason, message: String?)
    case audioSessionCreationTimedOut(identifier: UUID, timeout: TimeInterval)
    case audioSessionStartFailed(identifier: UUID, underlying: Error)
    case displayTransactionFailed(transactionID: UUID, reason: String?)
    case displayTransactionTimedOut(transactionID: UUID, timeout: TimeInterval)
}

extension ProjectionChannelError {
    var isRetryableAudioSessionCreationFailure: Bool {
        switch self {
        case .audioSessionCreationFailed(_, let reason, _):
            switch reason {
            case .codecNotSupported, .permissionDenied, .sourceNotFound:
                return false
            default:
                return true
            }
        case .audioSessionCreationTimedOut, .audioSessionStartFailed:
            return true
        default:
            return false
        }
    }
}

enum ProjectionChannelEvent: Sendable {
    /// 화면 프로젝션 세션이 생성되었습니다.
    case sessionCreated(ProjectionSession)
    /// 화면 프로젝션 세션이 종료되었습니다.
    case sessionDestroyed(UUID, reason: VideoSessionEndReason, message: String?)

    /// 오디오 프로젝션 세션이 생성되었습니다.
    case audioSessionCreated(AudioProjectionSession)
    /// 오디오 프로젝션 세션이 종료되었습니다.
    case audioSessionDestroyed(UUID, reason: AudioSessionEndReason, message: String?)

    /// 커서 이미지가 변경되었습니다.
    case cursorImageChanged(CursorImageEvent)

    /// 커서 위치가 변경되었습니다.
    case cursorMoved(CursorMoveEvent)

    /// AppStream 윈도우 이벤트 (appeared/disappeared/updated)
    case appStreamWindowEvent(AppStreamWindowEvent)
}

final class ProjectionChannel: Channel, ChannelEventConsumer {
    let logger = NoctilucaLogger(category: "ProjectionChannel")

    let handle: ChannelHandle

    private static let defaultServiceClass: ServiceClass = .userInput

    /// Request ID 생성을 위한 atomic 카운터
    private let requestCounter = ManagedAtomic<UInt64>(0)

    /// Actor-isolated mutable state
    let state = ProjectionChannelState()

    // Rule I 패턴 1: init 에서 1회 생성 후 참조 불변. 내부 가변 상태는 @MainActor
    // 로 격리되어 있어, 외부에서의 접근은 모두 await MainActor 경유로 이루어진다.
    nonisolated(unsafe) let displayLayoutManager = DisplayLayoutManager()

    /// 외부 노출 이벤트 스트림.
    nonisolated(unsafe) let events: AsyncStream<ProjectionChannelEvent>
    // Rule I 패턴 1: init 에서 1회 대입 후 불변.
    nonisolated(unsafe) let continuation: AsyncStream<ProjectionChannelEvent>.Continuation

    // ~Copyable CompatBridge; init 마지막 대입 후 수정 없음. (Rule I 패턴 2)
    nonisolated(unsafe) private var channelEventCompatBridge:
        ChannelEventCompatBridge<ProjectionChannel>!

    init(handle: ChannelHandle) {
        self.handle = handle
        assert(handle.direction == .local,
               "ProjectionChannel must be opened from client side")

        var continuationLocal: AsyncStream<ProjectionChannelEvent>.Continuation!
        self.events = AsyncStream<ProjectionChannelEvent>(
            ProjectionChannelEvent.self,
            bufferingPolicy: .unbounded
        ) { continuation in
            continuationLocal = continuation
        }
        self.continuation = continuationLocal

        self.channelEventCompatBridge =
            ChannelEventCompatBridge(consumer: self, handle: handle)
    }

    // MARK: - ChannelEventConsumer

    func handleChannelReady() async {
        await handle.setServiceClass(Self.defaultServiceClass)
    }

    func handleFrame(frame: SiriusFrame) async throws {
        guard frame.isValid() else {
            throw ChannelError.invalidFrame
        }

        switch frame.opcode {
        case .projectionSessionCreatedEvent:
            let event = try ProjectionSessionCreatedEvent.fromProtobufBytes(frame.data)
            self.logger.info("Received ProjectionSessionCreatedEvent: sessionId=\(event.identifier)")

            let dispatched = await state.dispatchPendingSession(event.identifier, message: event)
            if !dispatched {
                self.logger.warning("No pending session found for identifier: \(event.identifier)")
            }

        case .projectionSessionEndedEvent:
            let event = try ProjectionSessionEndedEvent.fromProtobufBytes(frame.data)
            await self.handleProjectionSessionEndedEvent(event)

        case .projectionSessionChangedEvent:
            let event = try ProjectionSessionChangedEvent.fromProtobufBytes(frame.data)
            await self.handleProjectionSessionChangedEvent(event)

        case .cursorEvent:
            let event = try CursorEvent.fromProtobufBytes(frame.data)
            try await self.handleCursorEvent(event)

        // MARK: - Displayman opcodes

        case .displayListResponse:
            let response = try DisplayListResponse.fromProtobufBytes(frame.data)
            await self.dispatchResponse(requestID: response.requestID, message: response)

        case .subscribeDisplayChangesResponse:
            let response = try SubscribeDisplayChangesResponse.fromProtobufBytes(frame.data)
            await self.dispatchResponse(requestID: response.requestID, message: response)

        case .displayChangedEvent:
            let event = try DisplayChangedEvent.fromProtobufBytes(frame.data)
            try await self.handleDisplayChangedEvent(event)

        case .displayTransactionResponse:
            let response = try DisplayTransactionResponse.fromProtobufBytes(frame.data)
            await self.handleDisplayTransactionResponse(response)

        // MARK: - Window Manager opcodes

        case .windowListResponse:
            let response = try WindowListResponse.fromProtobufBytes(frame.data)
            await self.dispatchResponse(requestID: response.requestID, message: response)

        case .getWindowInfoResponse:
            let response = try GetWindowInfoResponse.fromProtobufBytes(frame.data)
            await self.dispatchResponse(requestID: response.requestID, message: response)

        case .getWindowIconResponse:
            let response = try GetWindowIconResponse.fromProtobufBytes(frame.data)
            await self.dispatchResponse(requestID: response.requestID, message: response)

        case .getWindowThumbnailResponse:
            let response = try GetWindowThumbnailResponse.fromProtobufBytes(frame.data)
            await self.dispatchResponse(requestID: response.requestID, message: response)

        case .subscribeWindowEventsResponse:
            let response = try SubscribeWindowEventsResponse.fromProtobufBytes(frame.data)
            await self.dispatchResponse(requestID: response.requestID, message: response)

        case .unsubscribeWindowEventsResponse:
            let response = try UnsubscribeWindowEventsResponse.fromProtobufBytes(frame.data)
            await self.dispatchResponse(requestID: response.requestID, message: response)

        case .windowManipulationResponse:
            let response = try WindowManipulationResponse.fromProtobufBytes(frame.data)
            // WindowManipulationResponse에는 requestID가 없으므로 별도 처리
            // TODO: implement dispatch mechanism
            break

        case .windowChangedEvent:
            let event = try WindowChangedEvent.fromProtobufBytes(frame.data)
            await self.handleWindowChangedEvent(event)

        // MARK: - AppStream opcodes

        case .startAppStreamResponse:
            let response = try StartAppStreamResponse.fromProtobufBytes(frame.data)
            await self.dispatchResponse(requestID: response.requestId, message: response)

        case .stopAppStreamResponse:
            let response = try StopAppStreamResponse.fromProtobufBytes(frame.data)
            await self.dispatchResponse(requestID: response.requestId, message: response)

        case .appStreamWindowEvent:
            let event = try AppStreamWindowEvent.fromProtobufBytes(frame.data)
            await self.handleAppStreamWindowEvent(event)

        // MARK: - Audio projection opcodes

        case .audioSessionCreatedEvent:
            let event = try AudioSessionCreatedEvent.fromProtobufBytes(frame.data)
            await self.handleAudioSessionCreatedEvent(event)

        case .audioSessionCreationFailedEvent:
            let event = try AudioSessionCreationFailedEvent.fromProtobufBytes(frame.data)
            await self.handleAudioSessionCreationFailedEvent(event)

        case .audioSessionEndedEvent:
            let event = try AudioSessionEndedEvent.fromProtobufBytes(frame.data)
            await self.handleAudioSessionEndedEvent(event)

        default:
            break
        }
    }

    func handleError(error: any Error) async {
        logger.warning("ProjectionChannel error: \(error)")
        await cancelAllPending(with: error)
        continuation.finish()
    }

    func handleStreamClose() async {
        logger.info("ProjectionChannel stream closed")
        await cancelAllPending(with: ProjectionChannelError.channelClosed)
        continuation.finish()
    }

    private func cancelAllPending(with error: Error) async {
        await state.cancelAllPendingSessions(with: error)
        await state.cancelAllPendingRequests(with: error)
        await state.cancelAllPendingAudioSessionRequests()
        await state.cancelAllPendingDisplayTransactions(with: error)
    }

    /// 다음 request ID를 생성합니다.
    func nextRequestID() -> UInt64 {
        requestCounter.loadThenWrappingIncrement(ordering: .relaxed)
    }

    func dispatchResponse(requestID: UInt64, message: any DecodableSiriusMessage) async {
        let dispatched = await state.dispatchPendingRequest(requestID, message: message)
        if !dispatched {
            self.logger.warning("No pending request found for requestID: \(requestID)")
        }
    }

    func registerPendingAudioSessionRequest(
        identifier: UUID,
        timeout: TimeInterval,
        continuation: CheckedContinuation<AudioSessionCreatedEvent, Error>
    ) async {
        let timeoutNanoseconds = UInt64(max(0, timeout) * 1_000_000_000)
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            await self?.handleAudioSessionRequestTimeout(identifier: identifier, timeout: timeout)
        }

        await state.registerPendingAudioSessionRequest(identifier, request: PendingAudioSessionRequest(
            continuation: continuation,
            timeoutTask: timeoutTask
        ))
    }

    func sendStopAudioProjectionRequest(identifier: UUID) {
        Task { [weak self] in
            guard let self else { return }

            do {
                try await self.handle.send(
                    opcode: .stopAudioProjectionRequest,
                    message: StopAudioProjectionRequest(identifier: identifier)
                )
            } catch {
                self.logger.warning("Failed to send StopAudioProjectionRequest for \(identifier): \(error)")
            }
        }
    }

    private func handleAudioSessionRequestTimeout(identifier: UUID, timeout: TimeInterval) async {
        let didFailPending = await state.failPendingAudioSessionRequest(
            identifier,
            error: ProjectionChannelError.audioSessionCreationTimedOut(identifier: identifier, timeout: timeout)
        )
        if didFailPending {
            sendStopAudioProjectionRequest(identifier: identifier)
        }
    }

    func registerPendingDisplayTransaction(
        transactionID: UUID,
        timeout: TimeInterval,
        continuation: CheckedContinuation<DisplayTransactionResponse, Error>
    ) async {
        let timeoutNanoseconds = UInt64(max(0, timeout) * 1_000_000_000)
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            await self?.handleDisplayTransactionTimeout(transactionID: transactionID, timeout: timeout)
        }

        await state.registerPendingDisplayTransaction(transactionID, request: PendingDisplayTransaction(
            continuation: continuation,
            timeoutTask: timeoutTask
        ))
    }

    private func handleDisplayTransactionTimeout(transactionID: UUID, timeout: TimeInterval) async {
        _ = await state.failPendingDisplayTransaction(
            transactionID,
            error: ProjectionChannelError.displayTransactionTimedOut(transactionID: transactionID, timeout: timeout)
        )
    }

    func handleDisplayTransactionResponse(_ response: DisplayTransactionResponse) async {
        if response.isSuccess {
            let dispatched = await state.succeedPendingDisplayTransaction(response.transactionID, response: response)
            if !dispatched {
                self.logger.warning("No pending display transaction found for transactionID: \(response.transactionID)")
            }
        } else {
            self.logger.error("Display transaction failed: transactionID=\(response.transactionID), reason=\(response.reason ?? "(nil)")")
            let dispatched = await state.failPendingDisplayTransaction(
                response.transactionID,
                error: ProjectionChannelError.displayTransactionFailed(
                    transactionID: response.transactionID,
                    reason: response.reason
                )
            )
            if !dispatched {
                self.logger.warning("No pending display transaction found for transactionID: \(response.transactionID)")
            }
        }
    }


    func sendSessionRequest<T: DecodableSiriusMessage>(
        sessionID: UUID,
        opcode: MessageOpcode,
        message: any DecodableSiriusMessage
    ) async throws -> T {
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { [weak self] continuation in
                guard let self = self else {
                    continuation.resume(throwing: ProjectionChannelError.channelClosed)
                    return
                }

                Task {
                    await self.state.registerPendingSession(sessionID) { result in
                        switch result {
                        case .success(let response):
                            if let typedResponse = response as? T {
                                continuation.resume(returning: typedResponse)
                            } else {
                                continuation.resume(throwing: ChannelError.invalidFrame)
                            }
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    }

                    do {
                        try await self.handle.send(opcode: opcode, message: message)
                    } catch {
                        await self.state.removePendingSession(sessionID)
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: { [weak self] in
            Task {
                await self?.state.failPendingSession(sessionID, error: CancellationError())
            }
        }
    }

    func sendRequest<T: DecodableSiriusMessage>(
        requestID: UInt64,
        opcode: MessageOpcode,
        message: any DecodableSiriusMessage
    ) async throws -> T {
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { [weak self] continuation in
                guard let self = self else {
                    continuation.resume(throwing: ProjectionChannelError.channelClosed)
                    return
                }

                Task {
                    await self.state.registerPendingRequest(requestID) { result in
                        switch result {
                        case .success(let response):
                            if let typedResponse = response as? T {
                                continuation.resume(returning: typedResponse)
                            } else {
                                continuation.resume(throwing: ChannelError.invalidFrame)
                            }
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    }

                    do {
                        try await self.handle.send(opcode: opcode, message: message)
                    } catch {
                        await self.state.removePendingRequest(requestID)
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: { [weak self] in
            Task {
                await self?.state.failPendingRequest(requestID, error: CancellationError())
            }
        }
    }
}
