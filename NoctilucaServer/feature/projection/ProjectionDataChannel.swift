//
//  ProjectionDataChannel.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/12/25.
//

import SiriusKit

import CoreMedia

protocol ProjectionDataChannelDelegate: AnyObject, Sendable {
    func projectionDataChannelDidClose(_ channel: ProjectionDataChannel)
    func projectionDataChannel(_ channel: ProjectionDataChannel, didEncounterError error: any Error)
}

// MARK: - ProjectionDataChannelState

/// `ProjectionDataChannel` 의 가변 상태(delegate weak ref) 를 격리하는 actor.
///
/// `Channel` 프로토콜이 Sendable 요구를 갖게 되었으므로, `weak var delegate` 같은
/// 가변 필드를 채널 본체에 직접 둘 수 없다 (Rule G). 이 채널은 채널 본체와 세션/
/// ProjectionChannel 사이에서 delegate 를 여러 경로(설정/해제) 로 갱신하므로
/// "init 직후 1회" 패턴에 해당하지 않아, actor 격리가 가장 안전하다.
actor ProjectionDataChannelState {
    private weak var delegate: ProjectionDataChannelDelegate?

    func setDelegate(_ delegate: ProjectionDataChannelDelegate?) {
        self.delegate = delegate
    }

    func getDelegate() -> ProjectionDataChannelDelegate? {
        return self.delegate
    }
}

// MARK: - ProjectionDataChannel

final class ProjectionDataChannel: Channel, ChannelEventConsumer {
    let handle: ChannelHandle

    private static let defaultServiceClass: ServiceClass = .realtimeVideo

    private let logger = NoctilucaLogger(category: "ProjectionDataChannel")

    let state = ProjectionDataChannelState()

    // ~Copyable CompatBridge; init 마지막 대입 후 수정 없음. (Rule I 패턴 2)
    nonisolated(unsafe) private var channelEventCompatBridge:
        ChannelEventCompatBridge<ProjectionDataChannel>!

    init(handle: ChannelHandle) {
        self.handle = handle
        self.channelEventCompatBridge =
            ChannelEventCompatBridge(consumer: self, handle: handle)
    }

    // MARK: - ChannelEventConsumer

    func handleChannelReady() async {
        await handle.setServiceClass(Self.defaultServiceClass)
    }

    func handleFrame(frame: SiriusFrame) async throws {
        // 서버 사이드 구현이므로 별도 처리를 하지 않는다 (= 클라이언트로 보내기만 하는 역할.)
    }

    func handleError(error: any Error) async {
        let delegate = await state.getDelegate()
        delegate?.projectionDataChannel(self, didEncounterError: error)
    }

    func handleStreamClose() async {
        let delegate = await state.getDelegate()
        delegate?.projectionDataChannelDidClose(self)
    }

    // MARK: - Send helpers

    func send(parameterSetMessage: CodecParameterSetMessage) async throws {
        handle.send(nonblocking: .codecParameterSets, message: parameterSetMessage)
    }

    func send(degradationNotice: DegradationNotice) async throws {
        handle.send(nonblocking: .degradationNotice, message: degradationNotice)
    }

    func send(videoFrame frame: EncodedFrame) {
        let serializedHeader = frame.header.serialize()
        let frameData = frame.data

        // header.count / frameData.count / header / frameData
        let siriusFrameSize = ((4 + 4) + serializedHeader.count + frameData.count)
        var siriusFrameData = Data(count: siriusFrameSize)

        // perform memcpy
        // 1. header size
        let headerSize = UInt32(serializedHeader.count).bigEndian
        withUnsafeBytes(of: headerSize) { ptr in
            siriusFrameData.replaceSubrange(0..<4, with: ptr)
        }

        // 2. frame data size
        let frameDataSize = UInt32(frameData.count).bigEndian
        withUnsafeBytes(of: frameDataSize) { ptr in
            siriusFrameData.replaceSubrange(4..<8, with: ptr)
        }

        // 3. header bytes
        // FIXME: 얘네 좀 더 빠른 방법 없음?
        let range = 8..<(8 + serializedHeader.count)
        siriusFrameData.replaceSubrange(range, with: serializedHeader)

        // 4. frame data bytes
        // FIXME: 얘네 좀 더 빠른 방법 없음?
        let frameDataRange = (8 + serializedHeader.count)..<siriusFrameSize
        siriusFrameData.replaceSubrange(frameDataRange, with: frameData)

        let siriusFrame = SiriusFrame(
            opcode: .frameData,
            length: UInt32(siriusFrameSize),
            data: consume siriusFrameData
        )

        handle.send(nonblocking: consume siriusFrame)
    }

    func send(audioFrame frame: EncodedAudioFrame) {
        let serializedHeader = frame.header.serialize()
        let frameData = frame.data

        // header.count / frameData.count / header / frameData
        let siriusFrameSize = ((4 + 4) + serializedHeader.count + frameData.count)
        var siriusFrameData = Data(count: siriusFrameSize)

        // perform memcpy
        // 1. header size
        let headerSize = UInt32(serializedHeader.count).bigEndian
        withUnsafeBytes(of: headerSize) { ptr in
            siriusFrameData.replaceSubrange(0..<4, with: ptr)
        }

        // 2. frame data size
        let frameDataSize = UInt32(frameData.count).bigEndian
        withUnsafeBytes(of: frameDataSize) { ptr in
            siriusFrameData.replaceSubrange(4..<8, with: ptr)
        }

        // 3. header bytes
        let range = 8..<(8 + serializedHeader.count)
        siriusFrameData.replaceSubrange(range, with: serializedHeader)

        // 4. frame data bytes
        let frameDataRange = (8 + serializedHeader.count)..<siriusFrameSize
        siriusFrameData.replaceSubrange(frameDataRange, with: frameData)

        let siriusFrame = SiriusFrame(
            opcode: .frameData,
            length: UInt32(siriusFrameSize),
            data: consume siriusFrameData
        )

        handle.send(nonblocking: consume siriusFrame)
    }
}
