//
//  XPCServerRoleClientTransport.swift
//  SiriusKit
//
//  Created by Claude on 2/20/26.
//

import Foundation
import SiriusKitCore

/// 데몬을 통해 프록시되는 개별 QUIC 클라이언트 연결을 나타내는 가상 트랜스포트.
///
/// noctilucad가 QUIC 연결을 수락하고 MainChannel 인증을 완료한 후,
/// XPC를 통해 이 트랜스포트에 스트림 이벤트를 전달한다.
actor XPCServerRoleClientTransport: ServerRoleClientTransport {
    nonisolated let id: ServerRoleClientTransportIdentifier
    nonisolated(unsafe) weak var delegate: ServerRoleClientTransportDelegate?

    /// 사전 인증 메타데이터. NoctilucaClientSession이 pre-auth 모드를 감지하는 데 사용한다.
    let metadata: SiriusXPCAuthMetadata

    private weak var rootTransport: XPCServerRoleRootTransport?

    private var streams: [StreamIdentifier: XPCStream] = [:]
    private var isFinalized: Bool = false

    nonisolated var remoteEndpoint: SREndpoint? {
        SREndpoint.parse(metadata.remoteAddress)
    }

    init(
        id: ServerRoleClientTransportIdentifier,
        metadata: SiriusXPCAuthMetadata,
        rootTransport: XPCServerRoleRootTransport
    ) {
        self.id = id
        self.metadata = metadata
        self.rootTransport = rootTransport
    }

    // MARK: - TransportLayer

    func disconnect() async {
        guard !isFinalized else { return }
        isFinalized = true

        let snapshot = Array(streams.values)
        streams.removeAll()

        for stream in snapshot {
            try? await stream.close()
        }

        // 데몬에 연결 끊기 요청
        await rootTransport?.requestDisconnectClient(id)

        await delegate?.clientTransportDidClose(self)
    }

    func openStream() async -> Result<SiriusKitCore.Stream, TransportLayerError> {
        let streamID = StreamIdentifier()

        guard let rootTransport else {
            return .failure(.openStreamFailed(error: nil))
        }

        let success = await rootTransport.requestOpenStream(clientID: id, streamID: streamID)

        guard success else {
            return .failure(.openStreamFailed(error: nil))
        }

        let stream = XPCStream(id: streamID, clientTransport: self)
        streams[streamID] = stream
        return .success(stream)
    }

    func issueResumeTicket() async throws {
        // NO-OP: QUIC 계층은 데몬이 관리
    }

    // MARK: - XPC → RootTransport → 여기로 들어오는 핸들러

    /// 데몬에서 원격 스트림 열림을 알렸을 때 호출한다.
    func handleRemoteStreamOpen(streamID: StreamIdentifier) async {
        let stream = XPCStream(id: streamID, clientTransport: self)
        streams[streamID] = stream

        do {
            try await delegate?.clientTransportDidOpenRemoteStream(self, stream: stream)
        } catch {
            await delegate?.clientTransport(self, didEncounterError: error)
        }
    }

    /// 데몬에서 스트림 데이터를 수신했을 때 호출한다.
    func handleStreamData(streamID: StreamIdentifier, data: Data) {
        guard let stream = streams[streamID] else { return }
        stream.feedData(data)
    }

    /// 데몬에서 스트림 종료를 알렸을 때 호출한다.
    func handleStreamClose(streamID: StreamIdentifier) async {
        guard let stream = streams[streamID] else { return }
        stream.feedClose()
        streams.removeValue(forKey: streamID)
        await delegate?.clientTransportDidCloseStream(self, stream: stream)
    }

    /// 데몬에서 스트림 에러를 알렸을 때 호출한다.
    func handleStreamError(streamID: StreamIdentifier, description: String) {
        guard let stream = streams[streamID] else { return }
        let error = XPCTransportError.remoteStreamError(description)
        stream.feedError(error)
    }

    /// 데몬에서 클라이언트 연결 종료를 알렸을 때 호출한다.
    func handleDisconnect() async {
        guard !isFinalized else { return }
        isFinalized = true

        let snapshot = Array(streams.values)
        streams.removeAll()

        for stream in snapshot {
            stream.feedClose()
        }

        await delegate?.clientTransportDidClose(self)
    }

    // MARK: - XPCStream에서 호출하는 데몬 요청 메서드

    func writeToStream(_ streamID: StreamIdentifier, data: Data) async -> Result<UInt32, StreamError> {
        guard let rootTransport else {
            return .failure(.endOfStream)
        }

        return await rootTransport.requestWriteStreamData(clientID: id, streamID: streamID, data: data)
    }

    func closeStream(_ streamID: StreamIdentifier) async {
        await rootTransport?.requestCloseStream(clientID: id, streamID: streamID)
        streams.removeValue(forKey: streamID)
    }

    func setStreamServiceClass(_ streamID: StreamIdentifier, serviceClass: ServiceClass) async {
        await rootTransport?.requestSetStreamServiceClass(
            clientID: id,
            streamID: streamID,
            serviceClass: serviceClass
        )
    }
}

// MARK: - Errors

enum XPCTransportError: Error, LocalizedError {
    case remoteStreamError(String)
    case daemonConnectionLost

    var errorDescription: String? {
        switch self {
        case .remoteStreamError(let desc):
            return "Remote stream error: \(desc)"
        case .daemonConnectionLost:
            return "XPC connection to daemon was lost"
        }
    }
}
