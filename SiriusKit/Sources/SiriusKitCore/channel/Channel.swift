//
//  Channel.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/20/25.
//

import Foundation
internal import SwiftProtobuf

internal import Atomics

public typealias ChannelIdentifier = UUID

public enum ChannelDirection {
    case local
    case remote
}

internal protocol ChannelLifecycleDelegate: AnyObject {
    func channelDidClose(_ channel: Channel)
    func channel(_ channel: Channel, didEncounterError error: any Error)
}

public enum ChannelError: Error {
    case invalidFrame
    case invalidArguments(String)
}

open class Channel {
    public protocol HasFeature {
        var feature: SiriusFeature { get }
    }

    private static let sharedLogger = SiriusLogger(category: "Channel")
    private var logger: SiriusLogger { Self.sharedLogger }

    package weak var session: (any SiriusSession)?
    let stream: Stream

    private var streamEventLoopTask: Task<Void, any Error>?

    public let identifier: ChannelIdentifier
    public let direction: ChannelDirection
    
    open var serviceClass: ServiceClass { .default }

    internal weak var lifecycleDelegate: ChannelLifecycleDelegate?

    // MARK: - Data Rate Monitoring
    private let _uplinkCounter = DataRateCounter()
    private let _downlinkCounter = DataRateCounter()

    /// 현재 uplink (송신) 데이터 전송률 (bytes/sec)
    public var uplinkDataRate: Double { _uplinkCounter.bytesPerSecond }

    /// 현재 downlink (수신) 데이터 전송률 (bytes/sec)
    public var downlinkDataRate: Double { _downlinkCounter.bytesPerSecond }

    // MARK: - Explicit Activation

    private var _activationLock = NSLock()
    private var _activationContinuation: CheckedContinuation<Void, Never>?
    private var _isActivated = false
    private var _isClosing = false

    /// 이 채널이 프레임 처리를 시작하기 전 명시적인 `activate()` 호출을 필요로 하는지 여부.
    /// 서브클래스에서 `true`를 반환하면, `activate()`가 호출될 때까지 이벤트 루프가 대기합니다.
    open var requiresExplicitActivation: Bool { false }

    /// 이벤트 루프를 활성화합니다.
    /// `requiresExplicitActivation`이 `true`인 채널에서, delegate 설정 등 준비가 완료된 후 호출하세요.
    public func activate() {
        _activationLock.withLock {
            _isActivated = true
            _activationContinuation?.resume()
            _activationContinuation = nil
        }
    }

    private func waitForActivation() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            _activationLock.withLock {
                if _isActivated {
                    continuation.resume()
                } else {
                    _activationContinuation = continuation
                }
            }
        }
    }

    required public init(using streamHolder: StreamHolder, identifier: ChannelIdentifier, direction: ChannelDirection) {
        self.stream = streamHolder.stream
        self.identifier = identifier
        self.direction = direction
        
        Task.detached { [self] in
            do {
                self.logger.debug("[\(self.identifier)] setting service class to \(self.serviceClass)")
                try await stream.setServiceClass(self.serviceClass)
            } catch {
                self.logger.error("[\(self.identifier)] failed to set service class \(self.serviceClass): \(error)")
            }
        }

        self.streamEventLoopTask = Task.detached(priority: .userInitiated) { [self] in
            do {
                try await self.streamEventLoop()
            } catch {
                self.logger.fatal("[\(self.identifier)] encountered error in stream event loop: \(error)")
                self.lifecycleDelegate?.channel(self, didEncounterError: error)
            }
        }
    }

    public func close() async throws {
        releaseActivationWaitIfNeeded()
        try await self.stream.close()

        // 스트림에 이미 버퍼링된 메시지들이 모두 소비될 때까지 대기
        _ = await streamEventLoopTask?.result
    }

    /// close() 시 activation 대기 중인 이벤트 루프를 강제로 풀어줍니다.
    private func releaseActivationWaitIfNeeded() {
        _activationLock.withLock {
            _isClosing = true
            _activationContinuation?.resume()
            _activationContinuation = nil
        }
    }

    public func send(frame: consuming SiriusFrame) async throws {
#if DEBUG
        // self.logger.trace("[\(self.identifier)] frame SEND - opcode \(frame.opcode.hexString), length \(frame.data.count)")
#endif

        let frameByteCount = SiriusFrame.headerSize + frame.data.count
        let result = await self.stream.write(frame: frame.data, opcode: frame.opcode, length: frame.length)

        if case .failure(let error) = result {
            throw error
        }

        _uplinkCounter.record(frameByteCount)
    }
    
    public func sendNonBlocking(frame: consuming SiriusFrame) {
        let frameByteCount = SiriusFrame.headerSize + frame.data.count
        let result = self.stream.writeNonBlocking(frame: frame.data, opcode: frame.opcode, length: frame.length)

        if case .failure(_) = result {
            return
        }

        _uplinkCounter.record(frameByteCount)
    }

    public func send(opcode: MessageOpcode, message: (any DecodableSiriusMessage)) async throws {
        // swiftlint:disable:next force_cast
        let protobufMessage = (message as! any SiriusMessage).toProtobufMessage()
        let messageData = try protobufMessage.serializedData()

#if DEBUG
        // self.logger.trace("[\(self.identifier)] frame SEND - opcode \(opcode.hexString), length \(messageData.count)")
#endif

        let result = await self.stream.write(frame: messageData, opcode: opcode)

        if case .failure(let error) = result {
            throw error
        }

        _uplinkCounter.record(SiriusFrame.headerSize + messageData.count)
    }
    
    public func sendNonBlocking(opcode: MessageOpcode, message: (any DecodableSiriusMessage)) {
        // swiftlint:disable:next force_cast
        let protobufMessage = (message as! any SiriusMessage).toProtobufMessage()
        guard let messageData = try? protobufMessage.serializedData() else {
            return
        }

        let result = self.stream.writeNonBlocking(frame: messageData, opcode: opcode)

        if case .failure(_) = result {
            return
        }

        _uplinkCounter.record(SiriusFrame.headerSize + messageData.count)
    }

    private func streamEventLoop() async throws {
        if requiresExplicitActivation {
            logger.debug("[\(self.identifier)] streamEventLoop(): waiting for explicit activation")
            await waitForActivation()

            if _isClosing {
                logger.debug("[\(self.identifier)] streamEventLoop(): channel is closing, aborting event loop")
                return
            }
        }

        for await event in self.stream.events {
            switch event {
            case .frame(let frame):
                // 아, 이거 매크로로 하면 개편할텐데 ㅠ
#if DEBUG
                // self.logger.trace("[\(self.identifier)] frame RECV - opcode \(frame.opcode.hexString), length \(frame.length)")
#endif
                _downlinkCounter.record(SiriusFrame.headerSize + Int(frame.length))

                do {
                    try await self.handleFrame(frame: frame)
                } catch {
                    self.logger.error("[\(self.identifier)] streamEventLoop(): error occurred while handling frame: \(error)")
                }
            case .closed:
                self.handleStreamClose()
                self.lifecycleDelegate?.channelDidClose(self)
                return
            case .error(let error):
                self.handleStreamError(error: error)
                self.lifecycleDelegate?.channel(self, didEncounterError: error)
                return
            }

        }
    }

    open func handleFrame(frame: SiriusFrame) async throws {
        // to be overridden by subclasses
    }

    open func handleStreamClose() {
        // default implementation

    }

    open func handleStreamError(error: (any Error)) {
        // to be overridden by subclasses
        logger.error("[\(self.identifier)] stream encountered error: \(error)")
    }

    /// 채널이 ChannelStartResponse 교환 완료 후 완전히 준비되었을 때 호출됩니다.
    /// 서브클래스에서 오버라이드하여 post-open 로직을 실행할 수 있습니다.
    open func channelDidBecomeReady() {
        // default: no-op
    }
}

extension Channel {
    convenience init(stream: Stream, identifier: ChannelIdentifier, direction: ChannelDirection) {
        self.init(using: StreamHolder(stream: stream), identifier: identifier, direction: direction)
    }
}
