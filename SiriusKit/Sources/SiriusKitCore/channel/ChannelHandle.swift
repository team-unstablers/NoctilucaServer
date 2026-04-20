//
//  ChannelHandle.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 4/10/26.
//

import Foundation
internal import SwiftProtobuf
internal import Atomics

// MARK: - Types (from Channel.swift)

public typealias ChannelIdentifier = UUID

public enum ChannelDirection: Sendable {
    case local
    case remote
}

public enum ChannelError: Error {
    case invalidFrame
    case invalidArguments(String)
    /// 채널이 이미 닫혔습니다.
    case channelClosed
}

// MARK: - ChannelEvent

public enum ChannelEvent: Sendable {
    case ready
    case frameReceived(SiriusFrame)
    case error(any Error)
    case closed
}

// MARK: - ChannelLifecycleDelegate

internal protocol ChannelLifecycleDelegate: AnyObject {
    func channelDidClose(_ channel: any ChannelHandle)
    func channel(_ channel: any ChannelHandle, didEncounterError error: any Error)
}

// MARK: - ChannelHandle Protocol

public protocol ChannelHandle: AnyObject, Sendable {
    var feature: SiriusFeature { get }
    var identifier: ChannelIdentifier { get }
    var direction: ChannelDirection { get }

    var serviceClass: ServiceClass { get }

    var events: AsyncStream<ChannelEvent> { get }

    /// 현재 uplink (송신) 데이터 전송률 (bytes/sec)
    var uplinkDataRate: Double { get }
    /// 현재 downlink (수신) 데이터 전송률 (bytes/sec)
    var downlinkDataRate: Double { get }

    // MARK: - methods

    /// 채널의 서비스 클래스를 설정합니다.
    func setServiceClass(_ serviceClass: ServiceClass) async

    /// 채널의 송수신 스트림을 활성화합니다.
    /// - Note: 내부 구현체는 이 메소드가 호출되기 전까지 송수신을 하지 않고 대기해야 합니다.
    ///         `send(...)`가 activation 이전에 호출되면 내부 버퍼에 쌓였다가 activation 시점에 순서대로 flush됩니다.
    func activate() async throws

    /// 채널을 닫습니다.
    /// - Note: activation 이전에 호출되면 버퍼링된 async send는 `ChannelError.channelClosed`로 실패 처리됩니다.
    ///         Nonblocking send는 조용히 drop됩니다.
    func close() async throws

    /// 메시지를 전송합니다.
    func send(frame: consuming SiriusFrame) async throws
    /// 메시지를 전송하지만, 전송 완료를 대기하지 않습니다.
    func send(nonblocking frame: consuming SiriusFrame)

    /// 메시지를 전송합니다.
    func send(opcode: MessageOpcode, message: (any DecodableSiriusMessage)) async throws
    /// 메시지를 전송하지만, 전송 완료를 대기하지 않습니다.
    func send(nonblocking opcode: MessageOpcode, message: (any DecodableSiriusMessage))
}

// MARK: - ChannelHandleImpl

// 에이, SwiftLint 씨 너무 깐깐하시다.. ㅎㅎ;
// swiftlint:disable:next type_body_length
package final class ChannelHandleImpl: ChannelHandle {
    // MARK: - State machine

    private enum State {
        case preActivation
        case active
        case closed
    }

    private enum PendingSend {
        case async(data: Data, opcode: MessageOpcode, length: UInt32?, cont: CheckedContinuation<Void, any Error>)
        case nonblocking(data: Data, opcode: MessageOpcode, length: UInt32?)
    }

    // MARK: - private fields
    private static let sharedLogger = SiriusLogger(category: "Channel")
    private var logger: SiriusLogger { Self.sharedLogger }

    package let stream: Stream

    nonisolated(unsafe) package weak var session: (any SiriusSession)?
    nonisolated(unsafe) private var streamEventLoopTask: Task<Void, any Error>?

    /// lifecycle delegate는 `stateLock`으로 보호합니다.
    /// 직접 접근 대신 `setLifecycleDelegate(_:)` / `takeLifecycleDelegateForNotification()` /
    /// `suppressLifecycleNotifications()`를 사용하세요.
    nonisolated(unsafe) private weak var _lifecycleDelegate: ChannelLifecycleDelegate?
    nonisolated(unsafe) private var _lifecycleNotified: Bool = false

    // MARK: - public fields
    public let feature: SiriusFeature
    public let identifier: ChannelIdentifier
    public let direction: ChannelDirection

    nonisolated(unsafe) private(set) public var serviceClass: ServiceClass

    public let events: AsyncStream<ChannelEvent>
    private let eventsContinuation: AsyncStream<ChannelEvent>.Continuation

    // MARK: - Data Rate Monitoring
    private let _uplinkCounter = DataRateCounter()
    private let _downlinkCounter = DataRateCounter()

    public var uplinkDataRate: Double { _uplinkCounter.bytesPerSecond }
    public var downlinkDataRate: Double { _downlinkCounter.bytesPerSecond }

    // MARK: - Activation / Send buffering

    /// 활성화 완료 여부에 대한 fast-path 체크용 atomic.
    /// `true`일 때 send()는 lock 경합 없이 바로 stream.write()로 직행합니다.
    /// 실제 상태 전이는 `stateLock`으로 보호되는 `_state`에서 이루어집니다.
    private let isActivated = ManagedAtomic<Bool>(false)

    nonisolated(unsafe) private let stateLock = NSLock()
    nonisolated(unsafe) private var _state: State = .preActivation
    nonisolated(unsafe) private var _pendingSends: [PendingSend] = []
    nonisolated(unsafe) private var _eventLoopWaiter: CheckedContinuation<Void, Never>?

    package init(
        feature: SiriusFeature,
        session: any SiriusSession,
        stream: Stream,
        identifier: ChannelIdentifier,
        direction: ChannelDirection
    ) {
        self.feature = feature
        self.session = session
        self.stream = stream
        self.identifier = identifier
        self.direction = direction
        self.serviceClass = .default

        var continuationLocal: AsyncStream<ChannelEvent>.Continuation!
        self.events = AsyncStream<ChannelEvent>(bufferingPolicy: .unbounded) { continuation in
            continuationLocal = continuation
        }
        self.eventsContinuation = continuationLocal

        self.streamEventLoopTask = Task.detached(priority: .userInitiated) { [self] in
            do {
                try await self.streamEventLoop()
            } catch {
                self.logger.fatal("[\(self.identifier)] encountered error in stream event loop: \(error)")
                self.eventsContinuation.yield(.error(error))
                self.eventsContinuation.finish()
                self.takeLifecycleDelegateForNotification()?.channel(self, didEncounterError: error)
            }
        }
    }

    // MARK: - Lifecycle delegate

    /// lifecycle delegate를 설정합니다. `stateLock`으로 보호되어 스레드 안전합니다.
    internal func setLifecycleDelegate(_ delegate: ChannelLifecycleDelegate?) {
        stateLock.withLock {
            _lifecycleDelegate = delegate
        }
    }

    /// lifecycle 알림을 선제적으로 봉인합니다. 이후 `takeLifecycleDelegateForNotification()`은
    /// 항상 nil을 반환하여 콜백이 1회도 일어나지 않습니다. teardown 시 중복 unregister/race를
    /// 막기 위해 사용됩니다.
    internal func suppressLifecycleNotifications() {
        stateLock.withLock {
            _lifecycleNotified = true
            _lifecycleDelegate = nil
        }
    }

    /// lifecycle 콜백 1회 발사용으로 delegate를 소비합니다. 이미 한 번 반환됐거나
    /// `suppressLifecycleNotifications()`로 봉인된 경우 nil을 반환합니다.
    /// 호출자는 반환된 delegate를 lock 밖에서 호출해야 합니다 (reentrancy 회피).
    private func takeLifecycleDelegateForNotification() -> ChannelLifecycleDelegate? {
        stateLock.withLock {
            guard !_lifecycleNotified else { return nil }
            _lifecycleNotified = true
            let delegate = _lifecycleDelegate
            _lifecycleDelegate = nil
            return delegate
        }
    }

    // MARK: - Service Class

    public func setServiceClass(_ serviceClass: ServiceClass) async {
        self.serviceClass = serviceClass
        do {
            logger.debug("[\(self.identifier)] setting service class to \(serviceClass)")
            try await stream.setServiceClass(serviceClass)
        } catch {
            logger.error("[\(self.identifier)] failed to set service class \(serviceClass): \(error)")
        }
    }

    // MARK: - Activation

    public func activate() async throws {
        // Activation은 drain loop 방식으로 진행합니다:
        //   1) lock 안에서 pending 스냅샷을 꺼내거나, 비어 있으면 .active로 전이
        //   2) lock 밖에서 스냅샷을 순서대로 drain
        //   3) drain 중 새로 들어온 send는 다시 pending에 쌓이므로 loop로 재확인
        //   4) pending이 빌 때 비로소 .active로 전이 + atomic fast-path on
        drainLoop: while true {
            enum Step {
                case transitioned(waiter: CheckedContinuation<Void, Never>?)
                case closed
                case alreadyActive
                case drain([PendingSend])
            }

            let step: Step = stateLock.withLock {
                switch _state {
                case .closed:
                    return .closed
                case .active:
                    return .alreadyActive
                case .preActivation:
                    if _pendingSends.isEmpty {
                        _state = .active
                        isActivated.store(true, ordering: .releasing)
                        let waiter = _eventLoopWaiter
                        _eventLoopWaiter = nil
                        return .transitioned(waiter: waiter)
                    }
                    let snapshot = _pendingSends
                    _pendingSends = []
                    return .drain(snapshot)
                }
            }

            switch step {
            case .transitioned(let waiter):
                waiter?.resume()
                return
            case .alreadyActive:
                return
            case .closed:
                throw ChannelError.channelClosed
            case .drain(let pending):
                for pendingSend in pending {
                    await drainPendingSend(pendingSend)
                }
                continue drainLoop
            }
        }
    }

    private func drainPendingSend(_ pendingSend: PendingSend) async {
        switch pendingSend {
        case .async(let data, let opcode, let length, let cont):
            let result = await self.stream.write(frame: data, opcode: opcode, length: length)
            switch result {
            case .success:
                _uplinkCounter.record(SiriusFrame.headerSize + data.count)
                cont.resume()
            case .failure(let error):
                cont.resume(throwing: error)
            }
        case .nonblocking(let data, let opcode, let length):
            let result = self.stream.writeNonBlocking(frame: data, opcode: opcode, length: length)
            if case .success = result {
                _uplinkCounter.record(SiriusFrame.headerSize + data.count)
            }
        }
    }

    // MARK: - Close

    public func close() async throws {
        var waiter: CheckedContinuation<Void, Never>? = nil
        let pendingToFail: [PendingSend] = stateLock.withLock {
            switch _state {
            case .closed:
                return []
            case .preActivation, .active:
                _state = .closed
                isActivated.store(false, ordering: .releasing)
                let pending = _pendingSends
                _pendingSends = []
                waiter = _eventLoopWaiter
                _eventLoopWaiter = nil
                return pending
            }
        }

        // activation 대기 중인 event loop가 있으면 깨워줌
        waiter?.resume()

        // 버퍼링된 async send들은 ChannelError.channelClosed로 실패 처리
        for pendingSend in pendingToFail {
            switch pendingSend {
            case .async(_, _, _, let cont):
                cont.resume(throwing: ChannelError.channelClosed)
            case .nonblocking:
                break // drop
            }
        }

        try await self.stream.close()

        // 스트림에 이미 버퍼링된 메시지들이 모두 소비될 때까지 대기
        _ = await streamEventLoopTask?.result
    }

    // MARK: - Send

    public func send(frame: consuming SiriusFrame) async throws {
        let data = frame.data
        let opcode = frame.opcode
        let length = frame.length

        // Fast-path: 이미 활성화되어 있으면 lock 경합 없이 바로 write
        if isActivated.load(ordering: .acquiring) {
            try await sendDirectAsync(data: data, opcode: opcode, length: length)
            return
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
            enum Action {
                case buffered
                case directSend
                case fail
            }

            let action: Action = stateLock.withLock {
                switch _state {
                case .preActivation:
                    _pendingSends.append(.async(data: data, opcode: opcode, length: length, cont: cont))
                    return .buffered
                case .active:
                    return .directSend
                case .closed:
                    return .fail
                }
            }

            switch action {
            case .buffered:
                return // cont는 activate()/close() drain 단계에서 resume됨
            case .directSend:
                // atomic 체크와 lock 사이 race: activate()가 중간에 끼어든 경우
                Task {
                    do {
                        try await self.sendDirectAsync(data: data, opcode: opcode, length: length)
                        cont.resume()
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            case .fail:
                cont.resume(throwing: ChannelError.channelClosed)
            }
        }
    }

    public func send(nonblocking frame: consuming SiriusFrame) {
        let data = frame.data
        let opcode = frame.opcode
        let length = frame.length

        if isActivated.load(ordering: .acquiring) {
            sendDirectNonblocking(data: data, opcode: opcode, length: length)
            return
        }

        enum Action {
            case buffered
            case directSend
            case drop
        }

        let action: Action = stateLock.withLock {
            switch _state {
            case .preActivation:
                _pendingSends.append(.nonblocking(data: data, opcode: opcode, length: length))
                return .buffered
            case .active:
                return .directSend
            case .closed:
                return .drop
            }
        }

        switch action {
        case .buffered, .drop:
            return
        case .directSend:
            sendDirectNonblocking(data: data, opcode: opcode, length: length)
        }
    }

    public func send(opcode: MessageOpcode, message: (any DecodableSiriusMessage)) async throws {
        // swiftlint:disable:next force_cast
        let protobufMessage = (message as! any SiriusMessage).toProtobufMessage()
        let messageData = try protobufMessage.serializedData()

        if isActivated.load(ordering: .acquiring) {
            try await sendDirectAsync(data: messageData, opcode: opcode, length: nil)
            return
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
            enum Action {
                case buffered
                case directSend
                case fail
            }

            let action: Action = stateLock.withLock {
                switch _state {
                case .preActivation:
                    _pendingSends.append(.async(data: messageData, opcode: opcode, length: nil, cont: cont))
                    return .buffered
                case .active:
                    return .directSend
                case .closed:
                    return .fail
                }
            }

            switch action {
            case .buffered:
                return
            case .directSend:
                Task {
                    do {
                        try await self.sendDirectAsync(data: messageData, opcode: opcode, length: nil)
                        cont.resume()
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            case .fail:
                cont.resume(throwing: ChannelError.channelClosed)
            }
        }
    }

    public func send(nonblocking opcode: MessageOpcode, message: (any DecodableSiriusMessage)) {
        // swiftlint:disable:next force_cast
        let protobufMessage = (message as! any SiriusMessage).toProtobufMessage()
        guard let messageData = try? protobufMessage.serializedData() else {
            return
        }

        if isActivated.load(ordering: .acquiring) {
            sendDirectNonblocking(data: messageData, opcode: opcode, length: nil)
            return
        }

        enum Action {
            case buffered
            case directSend
            case drop
        }

        let action: Action = stateLock.withLock {
            switch _state {
            case .preActivation:
                _pendingSends.append(.nonblocking(data: messageData, opcode: opcode, length: nil))
                return .buffered
            case .active:
                return .directSend
            case .closed:
                return .drop
            }
        }

        switch action {
        case .buffered, .drop:
            return
        case .directSend:
            sendDirectNonblocking(data: messageData, opcode: opcode, length: nil)
        }
    }

    private func sendDirectAsync(data: Data, opcode: MessageOpcode, length: UInt32?) async throws {
        let result = await self.stream.write(frame: data, opcode: opcode, length: length)

        if case .failure(let error) = result {
            throw error
        }

        _uplinkCounter.record(SiriusFrame.headerSize + data.count)
    }

    private func sendDirectNonblocking(data: Data, opcode: MessageOpcode, length: UInt32?) {
        let result = self.stream.writeNonBlocking(frame: data, opcode: opcode, length: length)

        if case .failure(_) = result {
            return
        }

        _uplinkCounter.record(SiriusFrame.headerSize + data.count)
    }

    // MARK: - Event Loop

    private func streamEventLoop() async throws {
        logger.debug("[\(self.identifier)] streamEventLoop(): waiting for activation")

        // activation(또는 close)까지 대기
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            stateLock.withLock {
                switch _state {
                case .preActivation:
                    _eventLoopWaiter = cont
                case .active, .closed:
                    cont.resume()
                }
            }
        }

        // 깨어난 뒤 현재 상태 확인
        let isClosed: Bool = stateLock.withLock {
            if case .closed = _state { return true }
            return false
        }

        if isClosed {
            logger.debug("[\(self.identifier)] streamEventLoop(): channel is closing, aborting event loop")
            eventsContinuation.yield(.closed)
            eventsContinuation.finish()
            self.takeLifecycleDelegateForNotification()?.channelDidClose(self)
            return
        }

        eventsContinuation.yield(.ready)

        for await event in self.stream.events {
            switch event {
            case .frame(let frame):
                _downlinkCounter.record(SiriusFrame.headerSize + Int(frame.length))
                eventsContinuation.yield(.frameReceived(frame))
            case .closed:
                eventsContinuation.yield(.closed)
                eventsContinuation.finish()
                self.takeLifecycleDelegateForNotification()?.channelDidClose(self)
                return
            case .error(let error):
                eventsContinuation.yield(.error(error))
                eventsContinuation.finish()
                self.takeLifecycleDelegateForNotification()?.channel(self, didEncounterError: error)
                return
            }
        }
    }
}

package extension ChannelHandle {
    var asImpl: ChannelHandleImpl {
        guard let impl = self as? ChannelHandleImpl else {
            fatalError("ChannelHandle implementation is expected to be ChannelHandleImpl, but got \(type(of: self))")
        }
        
        return impl
    }
}
