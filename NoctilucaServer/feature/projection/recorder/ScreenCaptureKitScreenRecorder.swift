//
//  AVFoundationScreenRecorder.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/12/25.
//

import Foundation
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
        
        guard case .entireDisplay(let displayID) = source else {
            logger.error("prepare(): AVFoundationScreenRecorder only supports entire display capture.")
            throw ScreenRecorderPrepareError.invalidSource
        }
        
        
        guard let screenInput = AVCaptureScreenInput(displayID: displayID) else {
            logger.error("prepare(): Failed to create AVCaptureScreenInput for display ID: \(displayID)")
            throw ScreenRecorderPrepareError.internalError
        }
        
        let configuration = SCStreamConfiguration()
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.preservesAspectRatio = false
        
        configuration.queueDepth = 2
        configuration.showsCursor = true
        
        let display = try await SCShareableContent.current.displays.first!
        
        let contentFilter = SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: [
                try await SCShareableContent.currentProcess.windows.first!
            ]
        )
        
        let stream = SCStream(filter: contentFilter, configuration: configuration, delegate: self)
        
        self.stream = stream
        
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
    }
    
    func start() async throws {
        try await stream?.startCapture()
    }
    
    func stop() async throws {
        try await stream?.stopCapture()
    }
}

extension ScreenCaptureKitScreenRecorder: SCStreamDelegate {
    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        logger.error("didStopWithError: \(error.localizedDescription)")
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
