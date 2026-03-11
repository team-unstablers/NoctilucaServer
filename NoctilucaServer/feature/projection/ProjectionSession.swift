//
//  ProjectionSession.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/12/25.
//

import Foundation
import Combine

import CoreGraphics
import CoreMedia

import SiriusKit

enum ProjectionSessionError: Error {
    case invalidSource
}

protocol ProjectionSessionDelegate: AnyObject {
    func projectionSession(_ session: ProjectionSession, didChangeResolution newCodec: Codec)
    func projectionSession(_ session: ProjectionSession, didFailWithError error: Error)
}

class ProjectionSession: Identifiable {
    private let logger = NoctilucaLogger(category: "ProjectionSession")
    
    private let recorderQueue = DispatchQueue(
        label: "app.noctiluca.server.projection.recorder.video",
        // 가장 높은 우선순위
        qos: .userInteractive
    )
    
    let id: UUID
    let dataChannel: ProjectionDataChannel
    private let preferredRecorderType: ScreenRecorderType
    
    private var recorderArgs: ScreenRecorderArgs!
    
    var recorder: any ScreenRecorder
    var encoder: any VideoEncoder
    var codec: Codec?
    
    private let frameQueue = FrameQueue<EncodedFrame>(capacity: 8)
    
    private var encoderEventLoopTask: Task<Void, Error>?
    private var senderEventLoopTask: Task<Void, Error>?
    
    private var qualityPlanner: (any QualityPlanner)?
    private var pressureAccumulator: Float = 0.0
    private var pressureWindowCount: Int = 0
    private let pressureWindowSize: Int = 30 // ~0.5s at 60fps

    private var lastSentDegradationNotice: DegradationNotice?
    private var recentEncodingFailure: Bool = false

    private let frameDropController = FrameDropController()
    private var originalFrameRate: Float = 30.0
    private var currentAppliedFrameRate: Float? = nil

    private var screenLockCancellable: AnyCancellable!
    private var displayChangeCancellable: AnyCancellable?

    weak var sessionDelegate: ProjectionSessionDelegate?

    private var originalRequest: ProjectionRequest?

    // FIXME
    var targetBitrate = 0
    var maxBitrate = 0

    private var isReconfiguring = false
    private var isStopped = false

    init(id: UUID, dataChannel: ProjectionDataChannel, preferredRecorderType: ScreenRecorderType) async {
        self.id = id
        self.dataChannel = dataChannel
        self.preferredRecorderType = preferredRecorderType
        
        self.recorder = await ScreenRecorderFactory.create(preferred: preferredRecorderType, queue: recorderQueue)
        self.encoder = VTVideoEncoder()
        
        self.screenLockCancellable = await ScreenLockObserver.shared.$isScreenLocked
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] isLocked in
                Task {
                    await self?.reconfigureRecorder()
                }
            }
        
        self.recorder.delegate = self
    }
    
    private func reconfigureRecorder() async {
        guard !isReconfiguring else {
            logger.info("reconfigureRecorder(): already in progress, skipping")
            return
        }
        guard !isStopped else { return }

        isReconfiguring = true
        defer { isReconfiguring = false }

        let maxRetries = 2
        var lastError: Error? = nil

        // 기존 recorder 확실히 중지
        try? await self.recorder.stop()
        self.recorder.delegate = nil

        for attempt in 0...maxRetries {
            if attempt > 0 {
                try? await Task.sleep(for: .milliseconds(500 * attempt))
                guard !isStopped else { return }
            }

            let newRecorder = await ScreenRecorderFactory.create(
                preferred: preferredRecorderType,
                queue: recorderQueue
            )
            newRecorder.delegate = self
            self.recorder = newRecorder

            do {
                try await self.recorder.prepare(with: recorderArgs)
                try await self.recorder.start()
                logger.info("reconfigureRecorder(): succeeded (attempt \(attempt))")
                return
            } catch {
                lastError = error
                logger.warning("reconfigureRecorder(): attempt \(attempt) failed: \(error)")
                try? await self.recorder.stop()
            }
        }

        // 모든 재시도 실패
        logger.error("reconfigureRecorder(): all retries exhausted for projection session \(self.id)")
        dataChannel.projectionDelegate?.projectionDataChannel(
            dataChannel,
            didEncounterError: lastError ?? ScreenRecorderPrepareError.internalError
        )
    }

    private func handleDisplayLayoutChange(_ layouts: [CGDirectDisplayID: NOCScreen]) async {
        guard !isStopped, !isReconfiguring else { return }
        guard let displayID = recorderArgs?.source.monitoredDisplayID else { return }

        guard let newScreen = layouts[displayID] else {
            // 디스플레이가 사라짐 → 에러 전파 (Phase 4에서 ProjectionChannel이 처리)
            logger.warning("Monitored display \(displayID) no longer available")
            sessionDelegate?.projectionSession(self, didFailWithError: ScreenRecorderPrepareError.invalidSource)
            return
        }

        let newSize = newScreen.frame.size
        guard let currentCodec = self.codec,
              let currentSize = currentCodec.size?.cgSize,
              currentSize != newSize else {
            return
        }

        logger.info("Display resolution changed: \(currentSize) -> \(newSize) for projection session \(self.id)")
        await reconfigureForResolutionChange(newSize: newSize)
    }

    private func reconfigureForResolutionChange(newSize: CGSize) async {
        guard !isStopped, let currentCodec = self.codec, let request = self.originalRequest else { return }

        // codec에 새 해상도 반영
        let updatedCodec = Codec(
            fourCC: currentCodec.fourCC,
            frameRate: currentCodec.frameRate,
            size: SRSize(width: newSize.width, height: newSize.height),
            options: currentCodec.options,
            quality: currentCodec.quality
        )

        do {
            // prepare()가 encoder + event loop task를 모두 재생성
            try await self.prepare(request, codec: updatedCodec)
            // recorder도 새 해상도로 재구성
            await reconfigureRecorder()

            sessionDelegate?.projectionSession(self, didChangeResolution: updatedCodec)
            logger.info("Successfully reconfigured for resolution change to \(newSize)")
        } catch {
            logger.error("Failed to reconfigure for resolution change: \(error)")
            sessionDelegate?.projectionSession(self, didFailWithError: error)
        }
    }

    private func encoderEventLoopMain() async throws {
        for await event in self.encoder.events {
            switch event {
            case .parameterSetChanged(let parameterSetMessage):
                try await dataChannel.send(parameterSetMessage: parameterSetMessage)
            case .frameEncoded(let encodedFrame):
                await processEncodedFrame(encodedFrame)
            case .frameSkipped:
                recentEncodingFailure = true
            case .errorOccurred(let error):
                self.logger.error("Encoder error occurred in projection session \(self.id): \(error)")
                throw error
            case .stopped:
                return
            }
        }
    }
    
    private func processEncodedFrame(_ frame: consuming EncodedFrame) async {
        let dropped = await frameQueue.enqueue(frame)

        // 큐 드랍 기반 플러시 판정
        let flushResult = frameDropController.shouldFlushQueue(queueDropOccurred: dropped)
        if flushResult.shouldFlush {
            await frameQueue.clear()
        }
        if flushResult.needsKeyframe {
            self.encoder.forceKeyframe()
        }

        // 큐 압력을 QualityPlanner에 피드
        if let planner = self.qualityPlanner {
            let pressure = await frameQueue.pressure
            accumulateQueuePressure(pressure, planner: planner)
        }
    }
    
    private func senderEventLoopMain() async throws {
        while !Task.isCancelled {
            let frame: EncodedFrame
            do {
                frame = try await frameQueue.next()
            } catch is CancellationError {
                return
            }
            
            try await self.dataChannel.send(videoFrame: frame)
        }
    }

    private func handleLoopFailure(loopName: String, error: any Error) {
        guard !(error is CancellationError) else {
            return
        }

        self.logger.warning("Projection session \(self.id) \(loopName) loop failed: \(error)")

        self.dataChannel.projectionDelegate?.projectionDataChannel(
            self.dataChannel,
            didEncounterError: error
        )
    }
    
    func handlePerformanceReport(_ report: ProjectionPerformanceReport) {
        guard let planner = self.qualityPlanner else { return }
        planner.feed(report: report)
        applyQualityPlan()
    }

    func prepare(_ request: ProjectionRequest, codec: Codec) async throws {
        guard let recorderSource = request.viewport.toScreenRecorderSource() else {
            throw ProjectionSessionError.invalidSource
        }

        let recorderArgs = ScreenRecorderArgs(
            // FIXME
            source: recorderSource,
            codec: codec,
            flags: request.viewport.flags
        )

        try await self.recorder.prepare(with: recorderArgs)

        self.recorderArgs = recorderArgs
        self.originalRequest = request

        self.codec = codec

        // 디스플레이 해상도 변경 구독 (최초 prepare 시에만 설정)
        if displayChangeCancellable == nil {
            displayChangeCancellable = DisplayLayoutManager.shared.displayLayoutChangeSubject
                .receive(on: DispatchQueue.main)
                .sink { [weak self] layouts in
                    Task {
                        await self?.handleDisplayLayoutChange(layouts)
                    }
                }
        }

        // 기존 encoder event loop task 취소 및 encoder 정리
        encoderEventLoopTask?.cancel()
        encoderEventLoopTask = nil
        
        senderEventLoopTask?.cancel()
        senderEventLoopTask = nil
        await frameQueue.clear()
        await frameQueue.cancelWaiter()
        
        try? self.encoder.stop()

        switch codec.fourCC {
        case .zrle:
            encoder = ZRLEVideoEncoder()
        case .mjpg:
            encoder = MJPGVideoEncoder()
        case .webp:
            encoder = WebPVideoEncoder()
        default:
            encoder = VTVideoEncoder()
        }
        
        try self.encoder.prepare(with: .init(
            codec: codec,
            inputFormatDescription: nil
        ))
        
        let frameRate = codec.frameRate ?? 60.0
        self.originalFrameRate = frameRate
        self.currentAppliedFrameRate = nil
        self.lastSentDegradationNotice = nil
        self.recentEncodingFailure = false
        frameDropController.configure(frameRate: frameRate)

        if case .auto(_) = codec.quality {
            let (qualityPlanner, plannerFrameRate) = Self.makeQualityPlanner(codec: codec)
            self.qualityPlanner = qualityPlanner
            self.originalFrameRate = plannerFrameRate
            frameDropController.configure(frameRate: plannerFrameRate)

            if let autoPlanner = qualityPlanner as? AutoQualityPlanner {
                autoPlanner.onQualityAdjustment = { [weak self] event in
                    self?.handleQualityAdjustment(event, planner: autoPlanner)
                }
            }

            if let planner = self.qualityPlanner {
                _ = self.encoder.updateTargetBitrate(planner.targetBitrateKbps())
                _ = self.encoder.updateMaxBitrate(bitrateKbps: planner.maxBitrateKbps())
            }
        } else {
            self.qualityPlanner = nil
        }
        
        
        self.encoderEventLoopTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                try await self.encoderEventLoopMain()
            } catch {
                self.handleLoopFailure(loopName: "encoder", error: error)
            }
        }

        self.senderEventLoopTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                try await self.senderEventLoopMain()
            } catch {
                self.handleLoopFailure(loopName: "sender", error: error)
            }
        }
    }
    
    func start() async throws {
        do {
            try await self.recorder.start()
            try self.encoder.start()
        } catch {
            self.logger.error("Failed to start projection session \(self.id): \(error)")

            do {
                try await self.stop()
            } catch {
                self.logger.error("Failed to cleanup projection session after start failure \(self.id): \(error)")
            }

            throw error
        }
    }
    
    func stop() async {
        guard !isStopped else { return }

        defer {
            isStopped = true
        }

        // 1. Task 취소 (새로운 프레임 처리 중단)
        encoderEventLoopTask?.cancel()
        encoderEventLoopTask = nil

        senderEventLoopTask?.cancel()
        senderEventLoopTask = nil

        // 2. Combine 구독 취소 (reconfigureRecorder 호출 방지)
        screenLockCancellable?.cancel()
        screenLockCancellable = nil
        displayChangeCancellable?.cancel()
        displayChangeCancellable = nil

        // 3. Frame queue 정리
        await frameQueue.clear()
        await frameQueue.cancelWaiter()

        // 4. Recorder 정리 (캡처 중지)
        do {
            try await self.recorder.stop()
        } catch {
            self.logger.error("Failed to stop recorder for projection session \(self.id): \(error)")
        }

        // 5. Encoder 정리
        do {
            try self.encoder.stop()
        } catch {
            self.logger.error("Failed to stop encoder for projection session \(self.id): \(error)")
        }

        // 6. Data channel 정리
        do {
            try await dataChannel.close()
        } catch {
            self.logger.warning("Failed to close projection data channel \(self.dataChannel.identifier): \(error)")
        }
    }

    deinit {
        // 동기 작업 수행
        encoderEventLoopTask?.cancel()
        senderEventLoopTask?.cancel()
        screenLockCancellable?.cancel()
        displayChangeCancellable?.cancel()

        // VTVideoEncoder의 Unmanaged refCon retain cycle을 끊는다 (동기 메서드)
        try? encoder.stop()

        // Safety-net: stop() 미호출 시 async 리소스를 비동기적으로 정리
        guard !isStopped else { return }

        logger.warning("ProjectionSession \(self.id) deallocated without explicit stop() - triggering safety-net async cleanup")

        let recorder = self.recorder
        let dataChannel = self.dataChannel
        let frameQueue = self.frameQueue

        Task.detached {
            await frameQueue.cancelWaiter()
            try? await recorder.stop()
            try? await dataChannel.close()
        }
    }
}

extension ProjectionSession: ScreenRecorderDelegate {
    func screenRecorderDidStart(_ recorder: any ScreenRecorder) {
        self.logger.info("Screen recorder started for projection session \(self.id)")
    }
    
    func screenRecorder(_ recorder: any ScreenRecorder, didStopWithError error: (any Error)?) {
        self.logger.info("Screen recorder stopped for projection session \(self.id), error: \(String(describing: error))")

        if error != nil, !isStopped {
            Task {
                await self.reconfigureRecorder()
            }
        }
    }
    
    func screenRecorder(_ recorder: any ScreenRecorder, didCaptureFrame frameData: CMSampleBuffer) {
        // PTS 기반 드랍 판정 (인코딩 전)
        let ptsDropResult = frameDropController.shouldDropByPts(frameData)
        if ptsDropResult.shouldDrop {
            logger.trace("FRAME DROP: PTS-based drop occurred.")
            return
        }

        if ptsDropResult.needsKeyframe {
            encoder.forceKeyframe()
        }

        /*
        let pixelBuffer = frameData.imageBuffer
        CVBufferRemoveAttachment(pixelBuffer!, kCVImageBufferICCProfileKey)
        let colorAttachments: [CFString: Any] = [
            kCVImageBufferColorPrimariesKey: kCVImageBufferColorPrimaries_ITU_R_2020,
            kCVImageBufferTransferFunctionKey: kCVImageBufferTransferFunction_ITU_R_2100_HLG, // kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ, // HLG라면
            kCVImageBufferYCbCrMatrixKey: kCVImageBufferYCbCrMatrix_ITU_R_2020
        ]

        // 3. PixelBuffer에 태그 주입
        // CVBufferSetAttachments는 기존 키가 있으면 덮어씁니다.
        CVBufferSetAttachments(pixelBuffer!, colorAttachments as CFDictionary, .shouldPropagate)
         */

        try? encoder.encode(frameID: UInt64(Date().timeIntervalSince1970 * 1000), sampleBuffer: frameData)
    }
}

private extension ProjectionSession {
    func accumulateQueuePressure(_ pressure: Float, planner: any QualityPlanner) {
        pressureWindowCount += 1
        pressureAccumulator += pressure

        if pressureWindowCount >= pressureWindowSize {
            let avgPressure = pressureAccumulator / Float(pressureWindowCount)
            planner.feed(queuePressure: avgPressure)
            applyQualityPlan()
            pressureWindowCount = 0
            pressureAccumulator = 0.0
        }
    }
    
    static func makeQualityPlanner(codec: Codec) -> (planner: QualityPlanner, frameRate: Float) {
        // FIXME: 기본값 하드코딩하지 말고 실제 소스로부터 받아오도록. 기본값이 없으면 실제 소스의 해상도/프레임레이트를 측정해서 넣어야 함
        var frameRate = codec.frameRate ?? 60.0
        let resolution = codec.size ?? SRSize(width: 2880, height: 2560)

        // FIXME: 무조건 AutoQuality를 쓰는건 아니잖아요.
        let planner = AutoQualityPlanner(
            codec: codec.fourCC,
            resolution: resolution.cgSize,
            frameRate: frameRate,
            strategy: .balanced // FIXME: hard-coded strategy.
        )

        // FIXME: codec.options로부터 allow-degradation 옵션을 읽어오도록
        planner.allowDegradation = true
        return (planner, frameRate)
    }
    
    
    func applyQualityPlan() {
        guard let planner = self.qualityPlanner else { return }

        if self.targetBitrate != planner.targetBitrateKbps() {
            logger.debug("Applying quality plan: target bitrate = \(planner.targetBitrateKbps()) kbps, max bitrate = \(planner.maxBitrateKbps()) kbps")

            self.targetBitrate = planner.targetBitrateKbps()
            _ = self.encoder.updateTargetBitrate(self.targetBitrate)
        }

        if self.maxBitrate != planner.maxBitrateKbps() {
            self.maxBitrate = planner.maxBitrateKbps()
            _ = self.encoder.updateMaxBitrate(bitrateKbps: self.maxBitrate)
        }

        // degradation 적용
        let degradations = planner.plannedDegradations()
        applyDegradations(degradations)
    }

    func applyDegradations(_ degradations: [QualityDegradation]) {
        var qualityFactor: Float = 1.0
        var maxQuantizeLevel: Int = 0
        var targetFrameRate: Float? = nil

        for degradation in degradations {
            switch degradation {
            case .lowerQuality(let factor):
                qualityFactor *= factor
            case .increaseQuantization(let level):
                maxQuantizeLevel = max(maxQuantizeLevel, level)
            case .lowerFrameRate(let fps):
                targetFrameRate = min(targetFrameRate ?? fps, fps)
            case .lowerResolution:
                break // 아직 미구현
            }
        }

        _ = self.encoder.updateQuality(qualityFactor)
        _ = self.encoder.updateQuantizeLevel(maxQuantizeLevel)

        let effectiveFps = targetFrameRate ?? originalFrameRate
        applyFrameRateChange(effectiveFps)
    }

    func handleQualityAdjustment(_ event: QualityAdjustmentEvent, planner: AutoQualityPlanner) {
        let notice = buildDegradationNotice(from: event, planner: planner)

        // 이전에 보낸 notice와 동일하면 전송하지 않음
        if let last = lastSentDegradationNotice,
           last.reason.rawValue == notice.reason.rawValue,
           last.type.rawValue == notice.type.rawValue,
           last.additionalInfo.rawValue == notice.additionalInfo.rawValue {
            return
        }

        lastSentDegradationNotice = notice
        recentEncodingFailure = false

        let dataChannel = self.dataChannel
        Task {
            do {
                try await dataChannel.send(degradationNotice: notice)
            } catch {
                self.logger.warning("Failed to send DegradationNotice: \(error)")
            }
        }
    }

    func buildDegradationNotice(from event: QualityAdjustmentEvent, planner: AutoQualityPlanner) -> DegradationNotice {
        // 완전 회복 시 빈 notice
        if event.direction == .recovered && event.degradationIndex == 0 {
            return DegradationNotice(
                reason: DegradationReason(rawValue: 0),
                type: DegradationType(rawValue: 0),
                additionalInfo: DegradationAdditionalInfo(rawValue: 0)
            )
        }

        // reason 매핑
        var reason: DegradationReason = []
        switch event.trigger {
        case .clientFeedback:
            reason.insert(.poorClientDecodingPerformance)
        case .networkThroughput:
            reason.insert(.poorNetworkThroughput)
        case .both:
            reason.insert(.poorClientDecodingPerformance)
            reason.insert(.poorNetworkThroughput)
        }

        if recentEncodingFailure {
            reason.insert(.poorServerEncodingPerformance)
        }

        // type 매핑: 현재 활성화된 degradation steps로부터 판별
        var type: DegradationType = [.bitrateDegradation] // multiplier 감소는 항상 발생
        let degradations = planner.plannedDegradations()
        for degradation in degradations {
            switch degradation {
            case .lowerResolution:
                type.insert(.resolutionDegradation)
            case .lowerFrameRate:
                type.insert(.framerateDegradation)
            case .lowerQuality, .increaseQuantization:
                // 이미 bitrateDegradation에 포함
                break
            }
        }

        return DegradationNotice(
            reason: reason,
            type: type,
            additionalInfo: DegradationAdditionalInfo(rawValue: 0)
        )
    }

    func applyFrameRateChange(_ fps: Float) {
        guard currentAppliedFrameRate != fps else { return }
        currentAppliedFrameRate = fps

        if fps >= originalFrameRate {
            // 제한 해제
            frameDropController.configureMaxFrameRate(nil)
        } else {
            frameDropController.configureMaxFrameRate(fps)
        }
        frameDropController.configure(frameRate: fps)
        _ = encoder.updateExpectedFrameRate(fps)
    }
}

extension ProjectionSource {
    func toScreenRecorderSource() -> ScreenRecorderSource? {
        switch self.value {
        case .entireDisplay(let displaySource):
            let displayID = displaySource.displayID
            return .entireDisplay(displayID: Int64(displayID))
        case .region(let regionSource):
            let displayID = regionSource.displayID
            let region = regionSource.region
            
            return .displayRegion(displayID: Int64(displayID), region: region.cgRect)
        case .singleWindow(let windowSource):
            // FIXME: force unwrap
            guard let windowID = windowSource.windowID else {
                return nil
            }
            return .window(windowID: windowID)
        default:
            return nil
        }
    }
}
