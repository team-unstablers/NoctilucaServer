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

class ProjectionSession: Identifiable {
    private let logger = NoctilucaLogger(category: "ProjectionSession")
    
    private let recorderQueue: DispatchQueue = .global(qos: .userInteractive)
    
    let id: UUID
    let dataChannel: ProjectionDataChannel
    private let preferredRecorderType: ScreenRecorderType
    
    private var recorderArgs: ScreenRecorderArgs!
    
    var recorder: any ScreenRecorder
    var encoder: any VideoEncoder
    var codec: Codec?
    
    private let frameQueue = FrameQueue<EncodedFrame>(capacity: 4)
    
    private var encoderEventLoopTask: Task<Void, Error>?
    private var senderEventLoopTask: Task<Void, Error>?
    
    private var qualityPlanner: (any QualityPlanner)?
    private var pressureAccumulator: Float = 0.0
    private var pressureWindowCount: Int = 0
    private let pressureWindowSize: Int = 30 // ~0.5s at 60fps

    private let frameDropController = FrameDropController()
    private var originalFrameRate: Float = 30.0
    private var currentAppliedFrameRate: Float? = nil

    private var screenLockCancellable: AnyCancellable!
    
    // FIXME
    var targetBitrate = 0
    var maxBitrate = 0

    init(id: UUID, dataChannel: ProjectionDataChannel, preferredRecorderType: ScreenRecorderType) async {
        self.id = id
        self.dataChannel = dataChannel
        self.preferredRecorderType = preferredRecorderType
        
        self.recorder = await ScreenRecorderFactory.create(preferred: preferredRecorderType, queue: recorderQueue)
        self.encoder = VTVideoEncoder()
        
        self.screenLockCancellable = await ScreenLockObserver.shared.$isScreenLocked
            .receive(on: RunLoop.main)
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
        try? await self.recorder.stop()
        
        self.recorder = await ScreenRecorderFactory.create(preferred: preferredRecorderType, queue: recorderQueue)
        self.recorder.delegate = self
        
        do {
            try await self.recorder.prepare(with: recorderArgs)
            try await self.recorder.start()
        } catch {
            self.logger.error("Failed to reconfigure recorder for projection session \(self.id): \(error)")
        }
    }
    
    private func encoderEventLoopMain() async throws {
        for await event in self.encoder.events {
            switch event {
            case .parameterSetChanged(let parameterSetMessage):
                try await dataChannel.send(parameterSetMessage: parameterSetMessage)
            case .frameEncoded(let encodedFrame):
                await processEncodedFrame(encodedFrame)
            case .errorOccurred(let error):
                // TODO: handle errors
                self.logger.error("Encoder error occurred in projection session \(self.id): \(error)")
                return
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
    
    func handlePerformanceReport(_ report: ProjectionPerformanceReport) {
        guard let planner = self.qualityPlanner else { return }
        planner.feed(report: report)
        applyQualityPlan()
    }

    func prepare(_ request: ProjectionRequest, codec: Codec) async throws {
        guard let recorderSource = request.viewport.toScreenRecorderSource() else {
            // TODO: throw .invalidSource
            fatalError()
        }
        
        let recorderArgs = ScreenRecorderArgs(
            // FIXME
            source: recorderSource,
            codec: codec,
            flags: request.viewport.flags
        )
        
        try await self.recorder.prepare(with: recorderArgs)
        
        self.recorderArgs = recorderArgs
        
        self.codec = codec

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
        
        let (qualityPlanner, frameRate) = Self.makeQualityPlanner(codec: codec)
        self.qualityPlanner = qualityPlanner
        self.originalFrameRate = frameRate
        self.currentAppliedFrameRate = nil
        frameDropController.configure(frameRate: frameRate)

        if let planner = self.qualityPlanner {
            _ = self.encoder.updateTargetBitrate(planner.targetBitrateKbps())
            _ = self.encoder.updateMaxBitrate(bitrateKbps: planner.maxBitrateKbps())
        }
        
        
        self.encoderEventLoopTask = Task {
            try await self.encoderEventLoopMain()
        }
        
        self.senderEventLoopTask = Task {
            try await self.senderEventLoopMain()
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
    
    func stop() async throws {
        // Task 취소
        encoderEventLoopTask?.cancel()
        encoderEventLoopTask = nil
        
        senderEventLoopTask?.cancel()
        senderEventLoopTask = nil

        await frameQueue.clear()
        await frameQueue.cancelWaiter()

        // Combine 구독 취소
        screenLockCancellable?.cancel()
        screenLockCancellable = nil

        var firstError: Error?

        // recorder/encoder 정리
        do {
            try await self.recorder.stop()
        } catch {
            self.logger.error("Failed to stop recorder for projection session \(self.id): \(error)")
            if firstError == nil { firstError = error }
        }

        do {
            try self.encoder.stop()
        } catch {
            self.logger.error("Failed to stop encoder for projection session \(self.id): \(error)")
            if firstError == nil { firstError = error }
        }

        do {
            try await dataChannel.close()
        } catch {
            self.logger.warning("Failed to close projection data channel \(self.dataChannel.identifier): \(error)")
            if firstError == nil { firstError = error }
        }

        if let firstError {
            throw firstError
        }
    }

    deinit {
        encoderEventLoopTask?.cancel()
        senderEventLoopTask?.cancel()
        screenLockCancellable?.cancel()
        
        let frameQueue = self.frameQueue
        Task {
            await frameQueue.cancelWaiter()
        }
    }
}

extension ProjectionSession: ScreenRecorderDelegate {
    func screenRecorderDidStart(_ recorder: any ScreenRecorder) {
        self.logger.info("Screen recorder started for projection session \(self.id)")
    }
    
    func screenRecorder(_ recorder: any ScreenRecorder, didStopWithError error: (any Error)?) {
        self.logger.info("Screen recorder stopped for projection session \(self.id), error: \(String(describing: error))")
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
