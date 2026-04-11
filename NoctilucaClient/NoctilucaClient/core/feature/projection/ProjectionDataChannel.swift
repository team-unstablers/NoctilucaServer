//
//  ProjectionDataChannel.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/12/25.
//

import Foundation

import CoreMedia

import SiriusKitClient

/// 프로젝션 데이터 채널이 외부로 노출하는 이벤트.
///
/// 기존 `ProjectionDataChannelDelegate` 기반 모델을 대체한다. 이 채널은 수신 전용이며,
/// 동일한 와이어 프레임에서 비디오용 `EncodedFrameInput` 과 오디오용 `EncodedAudioFrameInput`
/// 을 모두 yield 한다. 실제로 어느 것을 처리할지는 consumer(세션) 가 결정한다.
enum DataChannelEvent: Sendable {
    case codecParameterSets(CodecParameterSetMessage)
    case videoFrame(EncodedFrameInput)
    case audioFrame(EncodedAudioFrameInput)
    case degradationNotice(DegradationNotice)
    case closed
    case error(any Error)
}

final class ProjectionDataChannel: Channel, ChannelEventConsumer {
    private let logger = SiriusLogger(category: "ProjectionDataChannel", subsystem: "app.noctiluca.client")

    let handle: ChannelHandle

    private static let defaultServiceClass: ServiceClass = .realtimeVideo

    /// Consumer(세션)가 `for await`으로 소비하는 이벤트 스트림.
    ///
    /// `AsyncStream` unbounded buffer 는 consumer 가 아직 붙지 않은 시점에 도착한
    /// 프레임을 자연스럽게 축적하므로, v1 의 `requiresExplicitActivation=true` 로
    /// 보호하던 "세션 delegate 설정 전 프레임 유실" race 를 해결한다.
    nonisolated(unsafe) let events: AsyncStream<DataChannelEvent>
    private let continuation: AsyncStream<DataChannelEvent>.Continuation

    // ~Copyable CompatBridge; init 마지막 대입 후 수정 없음. (Rule I 패턴 2)
    nonisolated(unsafe) private var channelEventCompatBridge:
        ChannelEventCompatBridge<ProjectionDataChannel>!

    init(handle: ChannelHandle) {
        self.handle = handle

        var continuationLocal: AsyncStream<DataChannelEvent>.Continuation!
        self.events = AsyncStream<DataChannelEvent>(
            DataChannelEvent.self,
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
        switch frame.opcode {
        case .codecParameterSets:
            let message = try CodecParameterSetMessage.fromProtobufBytes(frame.data)
            continuation.yield(.codecParameterSets(message))

        case .frameData:
            try handleFrameData(frame)

        case .degradationNotice:
            let notice = try DegradationNotice.fromProtobufBytes(frame.data)
            continuation.yield(.degradationNotice(notice))

        default:
            break
        }
    }

    func handleError(error: any Error) async {
        continuation.yield(.error(error))
        continuation.finish()
    }

    func handleStreamClose() async {
        continuation.yield(.closed)
        continuation.finish()
    }

    // MARK: - Frame payload parsing

    private func handleFrameData(_ frame: SiriusFrame) throws {
        // <header length: uint32> <frame data length: uint32> <header bytes> <frame data bytes>
        let data = frame.data

        let headerLength = data.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let frameDataLength = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

        guard data.count == (8 + Int(headerLength) + Int(frameDataLength)) else {
            logger.error("Invalid frame data length: expected \(8 + Int(headerLength) + Int(frameDataLength)), got \(data.count)")
            throw ChannelError.invalidFrame
        }

        let rawHeader = data.subdata(in: 8..<(8 + Int(headerLength)))
        let header = try FrameDataHeader.fromProtobufBytes(rawHeader)
        let frameData = data.subdata(in: (8 + Int(headerLength))..<(8 + Int(headerLength) + Int(frameDataLength)))

        // 같은 와이어 프레임에서 비디오용 / 오디오용 event 를 모두 yield 한다.
        // 세션이 자신이 관심 있는 case 만 선별 처리한다.
        let videoFrameInput = EncodedFrameInput(
            header: header,
            data: frameData,
            formatDescription: nil
        )
        continuation.yield(.videoFrame(videoFrameInput))

        let audioFrameInput = EncodedAudioFrameInput(
            header: header,
            data: frameData
        )
        continuation.yield(.audioFrame(audioFrameInput))
    }
}
