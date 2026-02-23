//
//  AVFoundationScreenRecorder.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/12/25.
//

import Foundation
import CoreVideo
import ScreenCaptureKit

import SiriusKit

fileprivate struct FrameInfo {
    init?(from sampleBuffer: CMSampleBuffer) {
        let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer,
                createIfNecessary: true
        ) as? [[SCStreamFrameInfo: Any]]
        guard let attachments = attachmentsArray?.first else {
            return nil
        }

        guard let rawStatus = attachments[.status] as? Int,
              let status = SCFrameStatus(rawValue: rawStatus) else {
            return nil
        }

        self.status = status
        displayTime = attachments[.displayTime] as? UInt64
        scaleFactor = attachments[.scaleFactor] as? Double
        contentScale = attachments[.contentScale] as? Double
        if let contentRectDict = attachments[.contentRect] as? NSDictionary {
            contentRect = CGRect(dictionaryRepresentation: contentRectDict)
        }
        if let dirtyRectsDict = attachments[.dirtyRects] as? [NSDictionary] {
            dirtyRects = dirtyRectsDict.compactMap { CGRect(dictionaryRepresentation: $0) }
        }
    }

    var status: SCFrameStatus
    var displayTime: UInt64?
    var scaleFactor: Double?
    var contentScale: Double?
    var contentRect: CGRect?
    var dirtyRects: [CGRect]?
}

fileprivate extension ScreenRecorderArgs {
    /// Create a default SCStreamConfiguration based on the codec settings.
    func createSCStreamConfiguration() -> SCStreamConfiguration {
        let configuration: SCStreamConfiguration
        
        if #available(macOS 15.0, *) {
            // SCStreamConfiguration(preset:)은 macOS 15.0부터 사용할 수 있습니다.
            // (= HDR 캡쳐는 macOS 15.0부터 지원합니다.)
            if codec.isHDREnabled {
                // Apple의 HDR용 프리셋을 반환한다
                return SCStreamConfiguration(preset: .captureHDRStreamCanonicalDisplay)
            } else {
                configuration = SCStreamConfiguration()
            }
        } else {
            configuration = SCStreamConfiguration()
        }

        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        
        return configuration
    }
}

fileprivate extension SCShareableContent {
    static func currentAppWindow(windowID: Int) async throws -> SCWindow? {
        if #available(macOS 14.4, *) {
            return try await SCShareableContent.currentProcess.windows.first(where: {$0.windowID == windowID})
        } else {
            // 더 비효율적일 수도 있음
            return try await SCShareableContent.current.windows.first(where: {$0.windowID == windowID})
        }
    }
}

fileprivate extension ScreenRecorderSource {
    @MainActor
    func contentSize() async throws -> CGSize? {
        switch self {
        case .entireDisplay:
            return __entireDisplay__contentSize()
        case .window:
            return try await __window__contentSize()
            
        case .displayRegion:
            fatalError("not implemented")
        }
    }
    
    @MainActor
    func __entireDisplay__contentSize() -> CGSize? {
        guard case .entireDisplay(let rawDisplayID) = self else {
            fatalError("__entireDisplay__contentSize() called on non-entireDisplay source")
        }
        
        let displayID: CGDirectDisplayID = if self.requiresPrimaryDisplay {
            CGMainDisplayID()
        } else {
            CGDirectDisplayID(rawDisplayID)
        }
        
        guard let display = DisplayLayoutManager.shared.displayLayouts[displayID] else {
            return nil
        }
        
        return display.frame.size
    }
    
    @MainActor
    func __window__contentSize() async throws -> CGSize? {
        guard case .window(let windowID) = self else {
            fatalError("__window__contentSize() called on non-window source")
        }
        
        let shareableContent = try await SCShareableContent.current
        
        guard let window = shareableContent.windows.first(where: { $0.windowID == windowID }) else {
            throw ScreenRecorderPrepareError.invalidSource
        }
        
        return window.frame.size
    }
    
    @MainActor
    func createSCContentFilter() async throws -> SCContentFilter {
        switch self {
        case .entireDisplay:
            return try await __entireDisplay__createSCContentFilter()
        case .window:
            return try await __window__createSCContentFilter()
            
        case .displayRegion:
            fatalError("not implemented")
        }
    }
    
    /// 전체 디스플레이에 대한 SCContentFilter 생성
    @MainActor
    func __entireDisplay__createSCContentFilter() async throws -> SCContentFilter {
        guard case .entireDisplay(let rawDisplayID) = self else {
            fatalError("__entireDisplay__createSCContentFilter() called on non-entireDisplay source")
        }
        
        let shareableContent = try await SCShareableContent.current

        let displayID: CGDirectDisplayID = if self.requiresPrimaryDisplay {
            CGMainDisplayID()
        } else {
            CGDirectDisplayID(rawDisplayID)
        }
        
        guard let display = shareableContent.displays.first(where: { $0.displayID == displayID }) else {
            throw ScreenRecorderPrepareError.invalidSource
        }
        
        let dummyWindowManager = ScreenCaptureKitWorkaroundDummyWindow.windowManager
        guard let dummyNSWindow = await dummyWindowManager.window(for: displayID),
              let dummyWindow = try await SCShareableContent.currentAppWindow(windowID: dummyNSWindow.windowNumber)
        else {
            throw ScreenRecorderPrepareError.internalError
        }
        
        let filter = SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: [dummyWindow]
        )
        
        return filter
    }
    
    /// 특정 윈도우 핸들에 SCContentFilter 생성
    @MainActor
    func __window__createSCContentFilter() async throws -> SCContentFilter {
        guard case .window(let windowID) = self else {
            fatalError("__window__createSCContentFilter() called on non-window source")
        }
        
        let shareableContent = try await SCShareableContent.current
        
        guard let window = shareableContent.windows.first(where: { $0.windowID == windowID }) else {
            throw ScreenRecorderPrepareError.invalidSource
        }
        
        return SCContentFilter(desktopIndependentWindow: window)
    }
}

fileprivate extension SiriusKit.Codec {
    var minimumFrameInterval: CMTime {
        guard let frameRate = self.frameRate, frameRate > 0.0 else {
            // 30fps
            return CMTime(value: 1, timescale: CMTimeScale(30))
        }
        
        // 1 / {frameRate} 초 간격
        return CMTime(value: 1, timescale: CMTimeScale(frameRate))
    }
}

class ScreenCaptureKitScreenRecorder: NSObject, ScreenRecorder {
    private let logger = NoctilucaLogger(category: "ScreenCaptureKitScreenRecorder")
    
    let id: UUID = UUID()
    
    var queue: DispatchQueue
    weak var delegate: (any ScreenRecorderDelegate)?
    
    private var stream: SCStream?
    
    init(queue: DispatchQueue) {
        self.queue = queue
    }
    
    @MainActor
    func prepare(with args: ScreenRecorderArgs) async throws {
        let source = args.source
        let codec = args.codec
        let flags = args.flags
        
        if !SystemCapability.HDR.screenCaptureKitSupportsHDRCapture,
              codec.isHDREnabled
        {
            // 이 버전의 OS에서는 HDR 캡쳐를 지원하지 않으므로 경고 메시지를 띄운다.
            logger.warning("prepare(): capturing HDR content requires macOS 15.0 or later.")
        }
        
        let configuration = args.createSCStreamConfiguration()
        /*
        configuration.pixelFormat = kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
        configuration.colorSpaceName = CGColorSpace.displayP3_HLG
        configuration.colorMatrix = kCVImageBufferYCbCrMatrix_ITU_R_2020
        configuration.captureDynamicRange = .hdrLocalDisplay
         */
        
        if let displayDensity = codec.option(.displayDensity) {
            switch displayDensity {
            case .kDisplayDensityAuto:
                // It's automatic, そばにいるだけで…
                configuration.captureResolution = .automatic
            case .kDisplayDensityBest:
                configuration.captureResolution = .best
            case .kDisplayDensityPerformance:
                configuration.captureResolution = .nominal
            default:
                break
            }
        }
        
        // XXX: 잠깐만, 이거 여기서 하면 안될거같은데?
        // FIXME: 일단 이거 디스플레이 오리지널 사이즈 구해서 설정하는걸로 해야해요
        /*
        if let desiredSize = codec.size {
            configuration.width = Int(desiredSize.width)
            configuration.height = Int(desiredSize.height)
        }
         */
        
        if let contentSize = try await source.contentSize() {
            configuration.width = Int(contentSize.width)
            configuration.height = Int(contentSize.height)
        }
        
        configuration.minimumFrameInterval = codec.minimumFrameInterval
        
        // HACK: 최소 2 이상이어야 함, macOS 14쯤때부터 1로 설정하면 지랄나더라
        configuration.queueDepth = 2
        configuration.showsCursor = flags.contains(.showCursor)
        
        let filter = try await source.createSCContentFilter()
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        
        self.stream = stream
        
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.queue)
    }
    
    func start() async throws {
        try await stream?.startCapture()
    }
    
    func stop() async throws {
        guard let stream = self.stream else {
            return
        }

        defer {
            self.stream = nil
        }

        // SCStream output 제거 시도 (실패해도 계속 진행)
        do {
            try stream.removeStreamOutput(self, type: .screen)
        } catch {
            logger.warning("Failed to remove stream output: \(error)")
        }

        // Capture 중지 (반드시 시도, 실패 시 throw)
        do {
            try await stream.stopCapture()
        } catch {
            logger.error("Failed to stop capture: \(error)")
            throw error
        }
    }
}

extension ScreenCaptureKitScreenRecorder: SCStreamDelegate {
    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        logger.error("didStopWithError: \(error.localizedDescription)")
        delegate?.screenRecorder(self, didStopWithError: error)
    }
}

extension ScreenCaptureKitScreenRecorder: SCStreamOutput {
    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        
        guard let frameInfo = FrameInfo(from: sampleBuffer) else {
            return
        }
        
        guard frameInfo.status == .complete else {
            return
        }
        
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }

        self.delegate?.screenRecorder(self, didCaptureFrame: sampleBuffer)
        
        
        /*
        if (frameInfo.status != .complete) {
            return
        }
        
        if (subscriptions.count == 0) {
            return
        }
        
        let frameSize = CVImageBufferGetEncodedSize(sampleBuffer.imageBuffer!)
        let scaleFactor = frameInfo.scaleFactor ?? 1.0
        
        if (frameSize != self.frameSize || scaleFactor != self.scaleFactor) {
            logger.debug("screen resolution changed to \(frameSize) @ \(scaleFactor)x")
            
            self.frameSize = frameSize
            self.scaleFactor = scaleFactor
            
            subscriptions.forEach { subscriber in
                subscriber.screenResolutionChanged(to: frameSize, scaleFactor: scaleFactor)
            }
        }
        
        let now = CMTime(value: Int64(mach_absolute_time()), timescale: 1000000000)
        let frameTimestamp = sampleBuffer.presentationTimeStamp
        
        let timedelta = abs(now.seconds - frameTimestamp.seconds)
        
        if let dirtyRects = frameInfo.dirtyRects {
            subscriptions.forEach { subscriber in
                let sx = CGFloat(subscriber.mainViewport.width)  / self.frameSize.width
                let sy = CGFloat(subscriber.mainViewport.height) / self.frameSize.height
                
                dirtyRects.forEach { rect in
                    subscriber.screenUpdated(where: rect.scale(sx: sx, sy: sy))
                }
            }
            
            subscriptions.forEach { subscriber in
                if (!subscriber.suppressOutput) {
                    notifyScreenReady(which: sampleBuffer, to: subscriber)
                }
            }
         
        }
         */
    }
}
