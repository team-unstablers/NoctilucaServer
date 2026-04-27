//
//  ProjectionSession.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/12/25.
//

import Darwin

import Foundation
import os
import Atomics

import CoreGraphics
@preconcurrency import CoreMedia

@preconcurrency import AVFoundation
import Metal

import SiriusKitClient

enum ProjectionSessionError: Error {
    case codecSizeUnavailable
}

enum ProjectionSessionEvent: Sendable {
    /// 프로젝션이 시작되었습니다.
    case projectionStarted

    /// 프로젝션이 중지될 예정입니다.
    case projectionWillStop

    /// 프로젝션이 중지되었습니다.
    // TODO: 이거 reason 있어야 하지 않아?
    case projectionStopped

    /// 오류가 발생했습니다.
    /// - Parameters:
    ///  - error: 발생한 오류
    ///  - fatal: 치명적인 오류인지 여부
    case errorOccurred(Error, fatal: Bool)

    /// 성능 보고서를 발행하였습니다.
    case performanceReportEmitted(ProjectionPerformanceReport)

    case sizeChanged(CGSize)

    /// 서버로부터 DegradationNotice를 수신하였습니다.
    case degradationNoticeReceived(DegradationNotice)

    /// 코덱 구성이 변경되었습니다 (디코더 교체).
    case codecConfigured
}

/// 프로젝션 세션 (클라이언트).
///
/// ## 동시성 모델
///
/// 이 타입은 `actor` 로 승격되어 있으며, custom executor 로
/// `DispatchSerialQueue` (`serialQueue`) 를 사용한다. 이 queue 는 동시에
/// VT/VPX 비디오 디코더의 `callbackQueue` 로 주입되므로,
/// 디코더 delegate 콜백이 actor executor 와 동일한 컨텍스트에서 실행되고
/// `assumeIsolated { me in ... }` 로 hop 없이 actor-isolated 상태에 접근할 수 있다.
///
/// 외부로는 `nonisolated let events: AsyncStream<ProjectionSessionEvent>` 를 노출하고,
/// 데이터 채널의 이벤트는 `dataChannelConsumerTask` 가 `for await` 으로 consume 한다.
actor ProjectionSession: Identifiable {
    private let logger = NoctilucaLogger(category: "ProjectionSession")

    // MARK: - Custom Executor

    /// 이 actor 가 사용하는 serial queue. 디코더 callbackQueue 로도 주입되어
    /// actor executor 와 디코더 콜백 컨텍스트를 하나로 합친다.
    nonisolated let serialQueue: DispatchSerialQueue = DispatchSerialQueue(
        label: "app.noctiluca.client.projection.session.serial",
        qos: .userInteractive
    )

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        serialQueue.asUnownedSerialExecutor()
    }

    // MARK: - Immutable (nonisolated let)

    nonisolated let id: UUID
    nonisolated let dataChannel: ProjectionDataChannel

    // Rule I 패턴 3: init 에서 1회 대입 후 read-only.
    nonisolated(unsafe) weak var controlChannel: ProjectionChannel?

    nonisolated let displayID: Int
    nonisolated let enableJitterBuffer: Bool
    nonisolated let jitterBufferPreset: AppSettings.JitterBufferPreset

    /// 현재 입력 데이터 레이트 (bytes per second)
    nonisolated let currentDataRate = ManagedAtomic<Int>(0)

    /// 현재 입력 데이터 레이트 (Kbps)
    nonisolated var currentDataRateKbps: Double {
        Double(currentDataRate.load(ordering: .relaxed)) * 8.0 / 1000.0
    }

    /// 외부로 노출되는 이벤트 스트림.
    nonisolated let events: AsyncStream<ProjectionSessionEvent>
    nonisolated private let continuation: AsyncStream<ProjectionSessionEvent>.Continuation

    // MARK: - Debug snapshot (nonisolated read)

    /// 디버그/진단 UI 에서 sync 로 읽을 수 있는 스냅샷.
    ///
    /// `@MainActor` SwiftUI 뷰에서 actor hop 없이 현재 세션 상태를 표시하기 위한
    /// 단방향 publication. 상태가 변경될 때마다 `updateDebugSnapshot()` 으로 갱신된다.
    struct DebugSnapshot: Sendable {
        let codec: Codec?
        let size: CGSize
        let decoderTypeName: String
    }

    nonisolated private let debugSnapshotLock = OSAllocatedUnfairLock<DebugSnapshot>(
        initialState: DebugSnapshot(codec: nil, size: .zero, decoderTypeName: "N/A")
    )

    nonisolated var debugSnapshot: DebugSnapshot {
        debugSnapshotLock.withLock { $0 }
    }

    // MARK: - Actor-isolated mutable state

    private(set) var decoder: (any VideoDecoder)?
    private var performanceReporter: ProjectionPerformanceReporter?

    private var jitterBuffer: VideoJitterBuffer?

    private(set) var codec: Codec?
    private var formatDescription: CMFormatDescription?
    private(set) var size: CGSize = .zero

    // 렌더러 등록 dict — 전부 actor-isolated 로 격리.
    private var displayLayers: [ObjectIdentifier: AVSampleBufferDisplayLayer] = [:]
    private var metalVideoRenderers: [ObjectIdentifier: MetalVideoRenderer] = [:]

    /// 데이터 채널 이벤트 consume 루프.
    private var dataChannelConsumerTask: Task<Void, Never>?

    private func currentDecoderTypeName() -> String {
        guard let decoder else { return "N/A" }
        switch decoder {
        case let vtDecoder as VTVideoDecoder: return vtDecoder.decoderTypeName
        case is VPXVideoDecoder: return "VP8"
        default: return "Unknown"
        }
    }

    /// actor-isolated 에서 현재 상태를 읽어 debugSnapshot 에 반영한다.
    private func updateDebugSnapshot() {
        let snapshot = DebugSnapshot(
            codec: self.codec,
            size: self.size,
            decoderTypeName: currentDecoderTypeName()
        )
        debugSnapshotLock.withLock { $0 = snapshot }
    }

    // MARK: - Init

    init(
        id: UUID,
        displayID: Int,
        dataChannel: ProjectionDataChannel,
        controlChannel: ProjectionChannel,
        enableJitterBuffer: Bool = false,
        jitterBufferPreset: AppSettings.JitterBufferPreset = .lowLatency
    ) {
        self.id = id
        self.displayID = displayID
        self.dataChannel = dataChannel
        self.controlChannel = controlChannel
        self.enableJitterBuffer = enableJitterBuffer
        self.jitterBufferPreset = jitterBufferPreset

        var continuationLocal: AsyncStream<ProjectionSessionEvent>.Continuation!
        self.events = AsyncStream<ProjectionSessionEvent>(
            ProjectionSessionEvent.self,
            bufferingPolicy: .unbounded
        ) { continuation in
            continuationLocal = continuation
        }
        self.continuation = continuationLocal
    }

    /// 초기화 시점에 호출. 디코더 / jitter buffer / consume 루프를 설치한다.
    ///
    /// `init` 에서 분리된 이유: VT 디코더의 callbackQueue 로 `serialQueue` 를 주입해야
    /// 하는데, 이는 actor-isolated 필드인 `decoder` 등을 건드려야 해서 actor-isolated
    /// 메서드 내부여야 한다.
    func setup() async {
        self.performanceReporter = ProjectionPerformanceReporter(sessionID: id, parent: self)

        if enableJitterBuffer {
            let buffer = VideoJitterBuffer(preset: jitterBufferPreset.bufferPreset)
            // onFrameReady 콜백은 display link main thread 에서 호출된다.
            // actor-isolated `displayLayers` 접근을 위해 actor 로 hop.
            buffer.onFrameReady = { [weak self] sampleBuffer in
                guard let self else { return }
                Task { [weak self] in
                    await self?.enqueueToAllDisplayLayers(sampleBuffer)
                }
            }
            self.jitterBuffer = buffer
            logger.info("Jitter buffer enabled for session \(self.id) (preset: \(self.jitterBufferPreset.rawValue))")
        }

        // 기본 디코더: VTVideoDecoder. callbackQueue 로 serialQueue 를 주입해
        // 디코더 콜백이 actor executor 위에서 실행되게 한다.
        let vtDecoder = VTVideoDecoder(
            workerQueue: DispatchQueue(
                label: "app.noctiluca.client.projection.session.decoder.worker",
                qos: .userInitiated
            ),
            callbackQueue: serialQueue
        )
        vtDecoder.delegate = self
        self.decoder = vtDecoder

        // 데이터 채널 이벤트 consume 루프 시작
        self.dataChannelConsumerTask = Task { [weak self] in
            await self?.consumeDataChannelEvents()
        }
    }

    deinit {
        // nonisolated context — actor-isolated 필드 직접 접근 금지.
        // 정상 경로에서는 stop() 이 상위에서 호출되어 정리가 끝나 있어야 한다.
        // 여기서는 nonisolated let 만 만지는 최소한의 safety-net 만 수행.
        continuation.finish()
    }

    // MARK: - Data channel consumer

    private func consumeDataChannelEvents() async {
        for await event in dataChannel.events {
            switch event {
            case .codecParameterSets(let message):
                handleCodecParameterSets(message)

            case .videoFrame(let frame):
                handleVideoFrame(frame)

            case .audioFrame:
                // 오디오는 AudioProjectionSession 가 자체 consumer 루프로 처리.
                break

            case .degradationNotice(let notice):
                continuation.yield(.degradationNoticeReceived(notice))

            case .closed, .error:
                // 데이터 채널이 닫히면 consume 루프를 종료한다.
                // 세션 stop 은 상위(ProjectionChannel+Session 의 sessionEnded 경로) 가 담당.
                return
            }
        }
    }

    private func handleCodecParameterSets(_ message: CodecParameterSetMessage) {
        guard let codec = self.codec?.fourCC else { return }

        do {
            switch codec {
            case .hvc1:
                self.formatDescription = try CMFormatDescription(
                    hevcParameterSets: message.parameterSets.map { $0.data }
                )

            case .avc1:
                self.formatDescription = try CMFormatDescription(
                    h264ParameterSets: message.parameterSets.map { $0.data }
                )

            default:
                return
            }
        } catch {
            logger.error("Failed to create format description: \(error.localizedDescription)")
            // 다음 키프레임을 받으면 되므로 fatal 까진 아님
            continuation.yield(.errorOccurred(error, fatal: false))
        }
    }

    private func handleVideoFrame(_ frame: EncodedFrameInput) {
        self.performanceReporter?.recordReceivedFrame(byteCount: frame.data.count)

        do {
            var header = frame.header
            var frameData = frame.data
            var formatDesc = self.formatDescription

            // Annex-B 형식 프레임: SPS/PPS/VPS 를 추출하고 AVCC 로 변환
            if let codec = self.codec?.fourCC,
               frame.header.flags.contains(.H264_HEVC_isAnnexBFormatted) {
                let parsed = AnnexBParser.parse(frame.data, codec: codec)

                if !parsed.parameterSets.isEmpty {
                    do {
                        switch codec {
                        case .hvc1:
                            formatDesc = try CMFormatDescription(hevcParameterSets: parsed.parameterSets)
                        case .avc1:
                            formatDesc = try CMFormatDescription(h264ParameterSets: parsed.parameterSets)
                        default:
                            break
                        }
                        self.formatDescription = formatDesc
                    } catch {
                        logger.error("Failed to create format description from Annex-B parameter sets: \(error.localizedDescription)")
                    }
                }

                frameData = parsed.videoData
                header = FrameDataHeader(
                    frameID: frame.header.frameID,
                    frameLength: UInt32(parsed.videoData.count),
                    presentationTimestamp: frame.header.presentationTimestamp,
                    flags: frame.header.flags
                )
            }

            try self.decoder?.decode(EncodedFrameInput(
                header: header,
                data: frameData,
                formatDescription: formatDesc
            ))
        } catch {
            logger.error("decoder decode error: \(error.localizedDescription)")
            continuation.yield(.errorOccurred(error, fatal: false))
            self.performanceReporter?.recordDroppedFrame()
        }
    }

    // MARK: - Size management

    private func setSize(_ newSize: CGSize) {
        if newSize != self.size {
            self.size = newSize
            updateDebugSnapshot()
            continuation.yield(.sizeChanged(newSize))
        }
    }

    // MARK: - Event emission (nonisolated helper for Reporter)

    /// ProjectionPerformanceReporter actor 에서 nonisolated 로 이벤트를 쏠 수 있게 한다.
    /// `continuation.yield` 자체는 concurrency-safe.
    nonisolated func emitEvent(_ event: ProjectionSessionEvent) {
        continuation.yield(event)
    }

    // MARK: - Renderer registration (actor-isolated)

    func registerDisplayLayer(_ layer: AVSampleBufferDisplayLayer) {
        displayLayers[ObjectIdentifier(layer)] = layer
    }

    func unregisterDisplayLayer(_ layer: AVSampleBufferDisplayLayer) {
        displayLayers.removeValue(forKey: ObjectIdentifier(layer))
    }

    private func enqueueToAllDisplayLayers(_ sampleBuffer: CMSampleBuffer) {
        for layer in displayLayers.values {
            layer.enqueue(sampleBuffer)
        }
    }

    func registerMetalVideoRenderer(_ renderer: MetalVideoRenderer) {
        metalVideoRenderers[ObjectIdentifier(renderer)] = renderer
        // 이미 코덱이 설정되어 있으면 즉시 메타데이터 전달
        if let codec {
            renderer.updateCodecMetadata(codec: codec)
        }
    }

    func unregisterMetalVideoRenderer(_ renderer: MetalVideoRenderer) {
        metalVideoRenderers.removeValue(forKey: ObjectIdentifier(renderer))
    }

    private var hasMetalVideoRenderers: Bool {
        !metalVideoRenderers.isEmpty
    }

    private func presentToAllMetalVideoRenderers(_ pixelBuffer: CVPixelBuffer) {
        for renderer in metalVideoRenderers.values {
            renderer.present(pixelBuffer)
        }
    }

    // MARK: - Prepare / Reconfigure

    func prepare(codec: Codec) async throws {
        guard let size = codec.size else {
            throw ProjectionSessionError.codecSizeUnavailable
        }
        self.codec = codec
        setSize(size.cgSize)

        // 기존 디코더 정리 (새 디코더로 교체 전)
        try? decoder?.stop()

        switch codec.fourCC {
        case .vp80:
            let vpxDecoder = VPXVideoDecoder(
                workerQueue: DispatchQueue(label: "app.noctiluca.client.projection.session.decoder.vpx.worker", qos: .userInitiated),
                callbackQueue: serialQueue
            )
            vpxDecoder.delegate = self
            decoder = vpxDecoder
            formatDescription = nil

        default:
            let vtDecoder = VTVideoDecoder(
                workerQueue: DispatchQueue(label: "app.noctiluca.client.projection.session.decoder.vt.worker", qos: .userInitiated),
                callbackQueue: serialQueue
            )
            vtDecoder.delegate = self
            decoder = vtDecoder
        }
        try decoder?.prepare(with: .init(codec: codec))

        // Metal 비디오 렌더러에 코덱 메타데이터 전달
        for renderer in metalVideoRenderers.values {
            renderer.updateCodecMetadata(codec: codec)
        }

        updateDebugSnapshot()
        continuation.yield(.codecConfigured)
    }

    /// 서버로부터 코덱/해상도 변경 통지를 받았을 때 디코더를 재구성합니다.
    func reconfigure(codec: Codec) async throws {
        logger.info("Reconfiguring session \(self.id) with new codec: \(codec.fourCC)")

        let previousSize = self.size
        try await prepare(codec: codec)

        if let newSize = codec.size?.cgSize, newSize != previousSize {
            continuation.yield(.sizeChanged(newSize))
        }
    }

    func start() async throws {
        do {
            try self.decoder?.start()
            self.jitterBuffer?.start()
            await self.performanceReporter?.start()

            continuation.yield(.projectionStarted)
        } catch {
            continuation.yield(.errorOccurred(error, fatal: true))
            throw error
        }
    }

    func stop(sendStopRequest: Bool = true) async throws {
        continuation.yield(.projectionWillStop)

        self.jitterBuffer?.stop()
        await self.performanceReporter?.stop()
        try self.decoder?.stop()

        dataChannelConsumerTask?.cancel()
        dataChannelConsumerTask = nil

        if sendStopRequest, let controlChannel = self.controlChannel {
            let sessionID = self.id
            let logger = self.logger
            Task { [weak controlChannel] in
                do {
                    try await controlChannel?.handle.send(
                        opcode: .stopProjectionRequest,
                        message: StopProjectionRequest(identifier: sessionID)
                    )
                } catch {
                    logger.warning("Failed to send StopProjectionRequest for session \(sessionID): \(error)")
                }
            }
        }

        continuation.yield(.projectionStopped)
        continuation.finish()

        try? await self.dataChannel.handle.close()
    }

}

// MARK: - VideoDecoderDelegate

extension ProjectionSession: VideoDecoderDelegate {
    nonisolated func videoDecoder(_ decoder: any VideoDecoder, didDecode frame: DecodedFrame) {
        // callbackQueue == serialQueue == actor executor 이므로 assumeIsolated 가능.
        self.assumeIsolated { me in
            me.onDecoded(frame: frame)
        }
    }

    nonisolated func videoDecoder(_ decoder: any VideoDecoder, didFailWith error: any Error) {
        self.assumeIsolated { me in
            me.logger.error("decoder error: \(error.localizedDescription)")
            me.continuation.yield(.errorOccurred(error, fatal: false))
        }
    }

    nonisolated func videoDecoder(_ decoder: any VideoDecoder, didDropFrameWithID frameID: UInt64, reason: String) {
        self.assumeIsolated { me in
            me.logger.error("dropped frame ID: \(frameID), reason: \(reason)")
            me.performanceReporter?.recordDroppedFrame()
        }
    }
}

extension ProjectionSession {
    fileprivate func onDecoded(frame: DecodedFrame) {
        self.performanceReporter?.recordDecodedFrame(decodeTimeMs: frame.decodeTimeMs)

        // Metal 비디오 렌더러가 등록되어 있으면 CVPixelBuffer 를 직접 전달
        if hasMetalVideoRenderers {
            presentToAllMetalVideoRenderers(frame.pixelBuffer)
            return
        }

        // Fallback: AVSampleBufferDisplayLayer 경로
        if let jitterBuffer {
            jitterBuffer.enqueue(pixelBuffer: frame.pixelBuffer, remotePTS: frame.pts.seconds)
        } else {
            let now = mach_absolute_time()
            let presentationTime = CMTimeMake(value: Int64(now), timescale: 1_000_000_000)

            do {
                let sampleBuffer = try CMSampleBuffer(
                    imageBuffer: frame.pixelBuffer,
                    formatDescription: CMFormatDescription(imageBuffer: frame.pixelBuffer),
                    sampleTiming: CMSampleTimingInfo(
                        duration: CMTime.invalid,
                        presentationTimeStamp: presentationTime,
                        decodeTimeStamp: CMTime.invalid
                    )
                )
                enqueueToAllDisplayLayers(sampleBuffer)
            } catch {
                logger.error("Failed to create CMSampleBuffer: \(error.localizedDescription)")
                performanceReporter?.recordDroppedFrame()
            }
        }
    }
}

// MARK: - Performance Reporter

private actor ProjectionPerformanceReporter {
    private let logger = SiriusLogger(category: "ProjectionPerformanceReporter", subsystem: "app.noctiluca.client")
    private let sessionID: UUID

    private weak var parent: ProjectionSession?

    // atomic 카운터 — nonisolated 메서드에서 lock-free 로 접근
    private let _received = ManagedAtomic<UInt32>(0)
    private let _decoded = ManagedAtomic<UInt32>(0)
    private let _dropped = ManagedAtomic<UInt32>(0)
    private let _decodeTimeSumUs = ManagedAtomic<UInt64>(0)
    private let _receivedBytes = ManagedAtomic<UInt64>(0)

    private var timerTask: Task<Void, Never>?

    init(sessionID: UUID, parent: ProjectionSession) {
        self.sessionID = sessionID
        self.parent = parent
    }

    // MARK: - Lifecycle

    func start() {
        guard timerTask == nil else { return }
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                await self.flush()
            }
        }
    }

    func stop() {
        timerTask?.cancel()
        timerTask = nil
    }

    // MARK: - Hot-path recording (nonisolated, lock-free)

    nonisolated func recordReceivedFrame(byteCount: Int) {
        _received.wrappingIncrement(ordering: .relaxed)
        _receivedBytes.wrappingIncrement(by: UInt64(byteCount), ordering: .relaxed)
    }

    nonisolated func recordDecodedFrame(decodeTimeMs: Double) {
        _decoded.wrappingIncrement(ordering: .relaxed)
        _decodeTimeSumUs.wrappingIncrement(
            by: UInt64((decodeTimeMs * 1000).rounded()),
            ordering: .relaxed
        )
    }

    nonisolated func recordDroppedFrame() {
        _dropped.wrappingIncrement(ordering: .relaxed)
    }

    // MARK: - Flush

    private nonisolated func snapshotAndReset() -> (received: UInt32, decoded: UInt32, dropped: UInt32, avgDecodeMs: UInt32, bytes: UInt64) {
        let received = _received.exchange(0, ordering: .relaxed)
        let decoded = _decoded.exchange(0, ordering: .relaxed)
        let dropped = _dropped.exchange(0, ordering: .relaxed)
        let decodeTimeSumUs = _decodeTimeSumUs.exchange(0, ordering: .relaxed)
        let receivedBytes = _receivedBytes.exchange(0, ordering: .relaxed)

        let avgDecodeMs: UInt32 = decoded > 0
            ? UInt32((Double(decodeTimeSumUs) / 1000.0 / Double(decoded)).rounded())
            : 0

        return (received, decoded, dropped, avgDecodeMs, receivedBytes)
    }

    private func flush() async {
        let snapshot = snapshotAndReset()

        // 1초 간격 flush 이므로 bytes == bytes/sec
        parent?.currentDataRate.store(Int(snapshot.bytes), ordering: .relaxed)

        if snapshot.received == 0 && snapshot.decoded == 0 && snapshot.dropped == 0 {
            return
        }

        let report = ProjectionPerformanceReport(
            identifier: sessionID,
            receivedFrameCount: snapshot.received,
            decodedFrameCount: snapshot.decoded,
            droppedFrameCount: snapshot.dropped,
            averageDecodeTimeMs: snapshot.avgDecodeMs
        )

        // 세션 이벤트 스트림에 실시간 report 를 push.
        parent?.emitEvent(.performanceReportEmitted(report))

        // 서버로 report 전송
        guard let controlChannel = parent?.controlChannel else { return }
        do {
            logger.info("Sending performance report for session \(self.sessionID): received=\(snapshot.received), decoded=\(snapshot.decoded), dropped=\(snapshot.dropped), avgDecodeMs=\(snapshot.avgDecodeMs)")
            try await controlChannel.handle.send(opcode: .projectionPerformanceReport, message: report)
        } catch {
            logger.warning("Failed to send performance report for session \(self.sessionID): \(error)")
        }
    }
}
