//
//  SimpleRPCChannel.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 5/22/26.
//

import Foundation

import SiriusKit

import NoctilucaPluginKit
import NoctilucaPluginKitHostCore

/// SimpleRPC 채널의 호스트 측 구현체 (responder).
///
/// `simpleRpcRequest` 를 수신하면 `SimpleRPCHandlerRegistry` 로 dispatch 한
/// 뒤 결과를 `simpleRpcResponse` 로 회신한다. 다수의 요청이 동시에 진행될
/// 수 있으므로 각 요청은 독립 `Task` 로 spawn 하고, 채널 종료 시 모두
/// 취소한다.
///
/// 현 시점에서 호스트는 *요청자* 역할을 하지 않으므로 수신한
/// `simpleRpcResponse` 는 매칭할 in-flight 요청이 없다. mdproto 명세상
/// unsolicited 응답은 silently drop 해야 하므로 디버그 로그만 남기고
/// 흘려보낸다. 추후 호스트-initiated RPC 가 도입되면 in-flight 응답 라우팅
/// 테이블을 이곳에 추가하면 된다.
final class SimpleRPCChannel: Channel, ChannelEventConsumer {
    private static let defaultServiceClass: ServiceClass = .default

    let handle: ChannelHandle

    private let logger = NoctilucaLogger(category: "SimpleRPCChannel")
    private let registry: SimpleRPCHandlerRegistry
    private let state = State()

    /// in-flight responder task 추적용 상태.
    ///
    /// `SimpleRPCRequest.requestId` 는 발신측이 부여하는 값이라 충돌
    /// 가능성이 있으므로, 같은 id 가 재사용되면 새 task 가 기존 task 를
    /// 덮어쓴다 (mdproto: "uniqueness within currently in-flight requests"
    /// 는 발신측 책임).
    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var inFlight: [UUID: Task<Void, Never>] = [:]
        private var closed: Bool = false

        /// 요청 task 를 등록한다. 이미 채널이 닫혀 있으면 false 를 반환하며
        /// 호출자는 spawn 한 task 를 즉시 취소해야 한다.
        func insert(_ requestId: UUID, task: Task<Void, Never>) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if closed {
                return false
            }
            inFlight[requestId] = task
            return true
        }

        func remove(_ requestId: UUID) {
            lock.lock()
            defer { lock.unlock() }
            inFlight.removeValue(forKey: requestId)
        }

        /// 채널을 닫힘 상태로 표시하고 진행 중인 모든 task 를 꺼내 반환한다.
        /// 이후 등장하는 `insert` 는 모두 거부된다.
        func drain() -> [Task<Void, Never>] {
            lock.lock()
            defer { lock.unlock() }
            closed = true
            let tasks = Array(inFlight.values)
            inFlight.removeAll()
            return tasks
        }
    }

    // ~Copyable CompatBridge; init 마지막 대입 후 수정 없음.
    nonisolated(unsafe) private var channelEventCompatBridge:
        ChannelEventCompatBridge<SimpleRPCChannel>!

    convenience init(handle: ChannelHandle) {
        self.init(handle: handle, registry: .shared)
    }

    init(handle: ChannelHandle, registry: SimpleRPCHandlerRegistry) {
        self.handle = handle
        self.registry = registry

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
        case .simpleRpcRequest:
            let request = try SimpleRPCRequest.fromProtobufBytes(frame.data)
            spawnRequestHandler(request)

        case .simpleRpcResponse:
            // 호스트는 현 시점에 outbound 요청을 보내지 않으므로 매칭할
            // in-flight 요청이 없다. mdproto: unsolicited response 는
            // silently drop.
            logger.debug("ignoring SimpleRPCResponse (no outstanding outbound request)")

        default:
            logger.warning("received unexpected opcode: \(frame.opcode) - ignoring")
        }
    }

    func handleError(error: any Error) async {
        logger.error("channel error: \(error)")
        cancelAllInFlight()
    }

    func handleStreamClose() async {
        cancelAllInFlight()
    }

    // MARK: - Request dispatch

    private func spawnRequestHandler(_ request: SimpleRPCRequest) {
        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.dispatch(request)
        }
        if !state.insert(request.requestId, task: task) {
            task.cancel()
            logger.warning("dropped SimpleRPCRequest received after channel close: operation='\(request.operation)'")
        }
    }

    private func dispatch(_ request: SimpleRPCRequest) async {
        defer { state.remove(request.requestId) }

        let result = await registry.dispatch(
            operation: request.operation,
            args: request.args
        )

        // 채널이 닫히는 사이 dispatch 가 완료된 경우 — 응답을 더 이상 보내선
        // 안 된다 (mdproto: "No further SimpleRPCResponse MAY be sent on a
        // channel after it has closed").
        if Task.isCancelled {
            return
        }

        let response = result.toSiriusResponse(requestId: request.requestId)

        do {
            try await handle.send(opcode: .simpleRpcResponse, message: response)
        } catch {
            logger.warning("failed to send SimpleRPCResponse for '\(request.operation)': \(error)")
        }
    }

    private func cancelAllInFlight() {
        for task in state.drain() {
            task.cancel()
        }
    }
}
