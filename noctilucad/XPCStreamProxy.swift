//
//  XPCStreamProxy.swift
//  noctilucad
//
//  Created by Claude on 2/20/26.
//

import Foundation
import SiriusKit

/// 실제 QUIC Stream의 이벤트를 XPC를 통해 에이전트로 포워딩하는 프록시.
///
/// 데몬이 QUIC 스트림에서 수신한 프레임 데이터를 에이전트에 전달하고,
/// 에이전트에서 온 쓰기 요청을 실제 QUIC 스트림에 기록한다.
class XPCStreamProxy {
    let streamID: StreamIdentifier
    let stream: SiriusKit.Stream
    let clientID: UUID
    let agentProxy: SiriusAgentXPCInterface

    private var forwardingTask: Task<Void, Never>?

    init(
        streamID: StreamIdentifier,
        stream: SiriusKit.Stream,
        clientID: UUID,
        agentProxy: SiriusAgentXPCInterface
    ) {
        self.streamID = streamID
        self.stream = stream
        self.clientID = clientID
        self.agentProxy = agentProxy
    }

    deinit {
        forwardingTask?.cancel()
    }

    /// 스트림 이벤트 포워딩을 시작한다.
    ///
    /// 실제 QUIC 스트림의 `events`를 소비하여 에이전트에 XPC 메시지로 전달한다.
    func startForwarding() {
        forwardingTask = Task { [weak self] in
            guard let self else { return }

            for await event in stream.events {
                guard !Task.isCancelled else { break }

                switch event {
                case .frame(let frame):
                    let rawData = Self.serializeFrame(frame)
                    agentProxy.clientDidReceiveStreamData(
                        clientID as NSUUID,
                        streamID: streamID as NSUUID,
                        data: rawData as NSData
                    )

                case .closed:
                    agentProxy.clientStreamDidClose(
                        clientID as NSUUID,
                        streamID: streamID as NSUUID
                    )

                case .error(let error):
                    agentProxy.clientStreamDidError(
                        clientID as NSUUID,
                        streamID: streamID as NSUUID,
                        errorDescription: error.localizedDescription as NSString
                    )
                }
            }
        }
    }

    /// 포워딩을 중단한다.
    func stopForwarding() {
        forwardingTask?.cancel()
        forwardingTask = nil
    }

    /// 에이전트에서 온 쓰기 요청을 실제 QUIC 스트림에 기록한다.
    func write(_ data: Data) async -> (bytesWritten: UInt32, error: String?) {
        let result = await stream.write(data)
        switch result {
        case .success(let count):
            return (count, nil)
        case .failure(let error):
            return (0, error.localizedDescription)
        }
    }

    /// 에이전트에서 온 종료 요청을 실제 QUIC 스트림에 전달한다.
    func close() async {
        stopForwarding()
        try? await stream.close()
    }

    /// 에이전트에서 온 서비스 클래스 설정 요청을 실제 QUIC 스트림에 전달한다.
    func setServiceClass(_ rawValue: UInt8) async {
        guard let serviceClass = ServiceClass(xpcRawValue: rawValue) else { return }
        try? await stream.setServiceClass(serviceClass)
    }

    // MARK: - Frame Serialization

    /// SiriusFrame을 raw bytes ([opcode 2B BE][length 4B BE][payload])로 직렬화한다.
    private static func serializeFrame(_ frame: SiriusFrame) -> Data {
        var data = Data(capacity: 6 + Int(frame.length))
        var opcode = frame.opcode.rawValue.bigEndian
        var length = frame.length.bigEndian
        withUnsafeBytes(of: &opcode) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(frame.data)
        return data
    }
}
