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

fileprivate extension AudioRecorderArgs {
    /// Create a default SCStreamConfiguration based on the codec settings.
    func createSCStreamConfiguration() -> SCStreamConfiguration {
        let configuration: SCStreamConfiguration
        
        configuration = SCStreamConfiguration()
        
        configuration.width = 32
        configuration.height = 32
        
        configuration.capturesAudio = true
        
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

fileprivate extension AudioRecorderSource {
    
    @MainActor
    func createSCContentFilter() async throws -> SCContentFilter {
        switch self {
        case .desktopSession:
            return try await __desktopSession__createSCContentFilter()
        case .applicationAudioPID(let pid):
            return try await __applicationPID__createSCContentFilter()
        case .applicationAudioBundleID(let bundleID):
            return try await __applicationBundleID__createSCContentFilter()
            
        default:
            fatalError("not implemented")
        }
    }
    
    /// 전체 디스플레이에 대한 SCContentFilter 생성
    @MainActor
    func __desktopSession__createSCContentFilter() async throws -> SCContentFilter {
        guard case .desktopSession = self else {
            fatalError("__desktopSession__createSCContentFilter() called on non-entireDisplay source")
        }
        
        let shareableContent = try await SCShareableContent.current

        let displayID: CGDirectDisplayID = CGMainDisplayID()
       
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
    
    @MainActor
    func __applicationPID__createSCContentFilter() async throws -> SCContentFilter {
        guard case .applicationAudioPID(let pid) = self else {
            fatalError("__applicationPID__createSCContentFilter() called on non-window source")
        }
        
        let shareableContent = try await SCShareableContent.current
        
        guard let application = shareableContent.applications.first(where: { $0.processID == pid }) else {
            throw ScreenRecorderPrepareError.invalidSource
        }
        
        guard let display = shareableContent.displays.first else {
            throw ScreenRecorderPrepareError.internalError
        }
        
        return SCContentFilter(
            display: display,
            including: [application],
            exceptingWindows: []
        )
    }
    
        
    @MainActor
    func __applicationBundleID__createSCContentFilter() async throws -> SCContentFilter {
        guard case .applicationAudioBundleID(let bundleID) = self else {
            fatalError("__applicationBundleID__createSCContentFilter() called on non-window source")
        }
        
        let shareableContent = try await SCShareableContent.current
        
        guard let application = shareableContent.applications.first(where: { $0.bundleIdentifier == bundleID }) else {
            throw ScreenRecorderPrepareError.invalidSource
        }
        
        guard let display = shareableContent.displays.first else {
            throw ScreenRecorderPrepareError.internalError
        }
        
        return SCContentFilter(
            display: display,
            including: [application],
            exceptingWindows: []
        )
    }
}


class ScreenCaptureKitAudioRecorder: NSObject, AudioRecorder {
    private let logger = NoctilucaLogger(category: "ScreenCaptureKitAudioRecorder")
    
    let id: UUID = UUID()
    
    var queue: DispatchQueue
    weak var delegate: (any AudioRecorderDelegate)?
    
    private var stream: SCStream?
    
    init(queue: DispatchQueue) {
        self.queue = queue
    }
    
    @MainActor
    func prepare(with args: AudioRecorderArgs) async throws {
        let source = args.source
        let codec = args.codec
        
        if case .microphone(_) = args.source {
            fatalError("not implemented")
        }
        
        let configuration = args.createSCStreamConfiguration()
                    
        configuration.minimumFrameInterval = CMTime(value: 30, timescale: CMTimeScale(1))
        
        // HACK: 최소 2 이상이어야 함, macOS 14쯤때부터 1로 설정하면 지랄나더라
        configuration.queueDepth = 2
        configuration.showsCursor = false
        
        let filter = try await source.createSCContentFilter()
        
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        
        self.stream = stream
        
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: self.queue)
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
            try stream.removeStreamOutput(self, type: .audio)
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

extension ScreenCaptureKitAudioRecorder: SCStreamDelegate {
    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        logger.error("didStopWithError: \(error.localizedDescription)")
        delegate?.audioRecorder(self, didStopWithError: error)
    }
}

extension ScreenCaptureKitAudioRecorder: SCStreamOutput {
    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }

        self.delegate?.audioRecorder(self, didCaptureFrame: sampleBuffer)
        
    }
}
