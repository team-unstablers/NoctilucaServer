//
//  SimpleQUICClient.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/23/25.
//

import Foundation
import Network

@testable import SiriusKit

enum SimpleQUICClientEvent {
    case connected
    case disconnected
    
    case mainStreamOpen
    
    case messageSent(opcode: MessageOpcode)
    
    case error(error: (any Error))
}

// 단일 스트림을 열고 간단한 메시지를 주고받는 QUIC 클라이언트.
final class SimpleQUICClient: @unchecked Sendable {
    let events: AsyncStream<SimpleQUICClientEvent>
    let continuation: AsyncStream<SimpleQUICClientEvent>.Continuation
    
    private let queue = DispatchQueue(label: "so.libsirius.SiriusKit.simplequicclient")
    private var connection: NWConnection?
    
    let host: String
    let port: UInt16
    
    init(host: String, port: UInt16) {
        self.host = host
        self.port = port
        
        var continuationLocal: AsyncStream<SimpleQUICClientEvent>.Continuation!
        
        self.events = AsyncStream<SimpleQUICClientEvent>(SimpleQUICClientEvent.self, bufferingPolicy: .unbounded) { continuation in
            continuationLocal = continuation
        }
        
        self.continuation = continuationLocal
    }
    
    func connect() async {
        let parameters = self.makeParameters()
        let endpoint = NWEndpoint.hostPort(host: .init(self.host), port: .init(integerLiteral: self.port))
        let connection = NWConnection(to: endpoint, using: parameters)

        self.connection = connection

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let resumer = ResumeOnce(continuation: cont)

            Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                if resumer.isResumed { return }

                self?.continuation.yield(.error(error: SimpleQUICClientError.connectTimeout))
                self?.continuation.yield(.disconnected)
                connection.cancel()
                resumer.resume()
            }

            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }

                switch state {
                case .ready:
                    self.continuation.yield(.connected)
                    self.continuation.yield(.mainStreamOpen)
                    resumer.resume()
                case .waiting(let error):
                    self.continuation.yield(.error(error: error))
                case .failed(let error):
                    self.continuation.yield(.error(error: error))
                    self.continuation.yield(.disconnected)
                    resumer.resume()
                case .cancelled:
                    self.continuation.yield(.disconnected)
                    resumer.resume()
                default:
                    break
                }
            }

            connection.start(queue: self.queue)
        }
    }

    private final class ResumeOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var resumed = false
        private let cont: CheckedContinuation<Void, Never>

        init(continuation: CheckedContinuation<Void, Never>) {
            self.cont = continuation
        }

        var isResumed: Bool {
            lock.withLock { resumed }
        }

        func resume() {
            let shouldResume: Bool = lock.withLock {
                guard !resumed else { return false }
                resumed = true
                return true
            }
            if shouldResume { cont.resume() }
        }
    }
    
    func send(_ frame: SiriusFrame) async {
        guard let connection else {
            self.continuation.yield(.error(error: SimpleQUICClientError.connectionNotReady))
            return
        }
        
        let data = self.encode(frame: frame)
        
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                if let error {
                    self?.continuation.yield(.error(error: error))
                } else {
                    self?.continuation.yield(.messageSent(opcode: frame.opcode))
                }
                
                cont.resume()
            })
        }
    }
    
    func recv() async -> SiriusFrame? {
        guard let connection else {
            self.continuation.yield(.error(error: SimpleQUICClientError.connectionNotReady))
            return nil
        }
        
        return await withCheckedContinuation { cont in
            connection.receive(minimumIncompleteLength: 6, maximumLength: Int(Int32.max)) { [weak self] content, _, isComplete, error in
                if let error {
                    self?.continuation.yield(.error(error: error))
                    cont.resume(returning: nil)
                    return
                }
                
                guard let content else {
                    cont.resume(returning: nil)
                    return
                }
                
                guard let frame = content.toSiriusFrame(),
                      frame.isValid()
                else {
                    cont.resume(returning: nil)
                    return
                }
                
                cont.resume(returning: frame)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func encode(frame: SiriusFrame) -> Data {
        var payload = Data(capacity: 6 + frame.data.count)
        
        var opcode = frame.opcode.rawValue.bigEndian
        var length = (frame.length == 0 ? UInt32(frame.data.count) : frame.length).bigEndian
        
        withUnsafeBytes(of: &opcode) { payload.append(contentsOf: $0) }
        withUnsafeBytes(of: &length) { payload.append(contentsOf: $0) }
        payload.append(frame.data)
        
        return payload
    }
    
    private func makeParameters() -> NWParameters {
        let options = NWProtocolQUIC.Options()
        options.alpn = [SiriusQUICAlpn.siriusV1.rawValue]
        options.direction = .bidirectional
        
        sec_protocol_options_set_verify_block(options.securityProtocolOptions, { _, _, completion in
            completion(true)
        }, self.queue)
        
        return NWParameters(quic: options)
    }
}

private enum SimpleQUICClientError: Error {
    case connectionNotReady
    case connectTimeout
}
