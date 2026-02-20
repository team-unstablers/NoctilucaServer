//
//  XPCStream.swift
//  SiriusKit
//
//  Created by Claude on 2/20/26.
//

import Foundation
import SiriusKitCore

/// XPC를 통해 noctilucad와 데이터를 송수신하는 가상 스트림.
///
/// - 수신: 데몬이 `feedData(_:)`를 호출하면 `SiriusFrameStreamDecoder`로 프레임을 파싱하여 `events`에 yield.
/// - 송신: `write(_:)` 호출 시 데몬에 `writeStreamData` XPC 메시지를 전송.
class XPCStream: SiriusKitCore.Stream {
    private weak var clientTransport: XPCServerRoleClientTransport?
    private var decoder = SiriusFrameStreamDecoder()

    init(id: StreamIdentifier, clientTransport: XPCServerRoleClientTransport) {
        super.init()
        self.id = id
        self.clientTransport = clientTransport
    }

    // MARK: - Write (Agent → Daemon → QUIC → Client)

    override func write(_ data: Data) async -> Result<UInt32, StreamError> {
        guard let clientTransport else {
            return .failure(.endOfStream)
        }

        return await clientTransport.writeToStream(id, data: data)
    }

    override func close() async throws {
        guard let clientTransport else { return }

        await clientTransport.closeStream(id)
        continuation.yield(.closed)
        continuation.finish()
    }

    override func setServiceClass(_ serviceClass: ServiceClass) async throws {
        guard let clientTransport else { return }

        await clientTransport.setStreamServiceClass(id, serviceClass: serviceClass)
    }

    // MARK: - Data Feed (Daemon → Agent)

    /// 데몬에서 수신한 raw bytes를 프레임 단위로 파싱하여 events에 yield한다.
    ///
    /// 데이터는 Sirius 프레임 헤더(opcode 2B + length 4B)를 포함한 raw bytes이다.
    func feedData(_ data: Data) {
        decoder.append(data)

        while let frame = decoder.nextFrame() {
            continuation.yield(.frame(frame))
        }
    }

    /// 데몬에서 스트림 종료를 알렸을 때 호출한다.
    func feedClose() {
        continuation.yield(.closed)
        continuation.finish()
    }

    /// 데몬에서 스트림 에러를 알렸을 때 호출한다.
    func feedError(_ error: Error) {
        continuation.yield(.error(error))
        continuation.finish()
    }
}
