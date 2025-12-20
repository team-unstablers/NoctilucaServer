//
//  AVFoundationScreenRecorder.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/12/25.
//

import Foundation
import AVFoundation

import SiriusKit

fileprivate extension SiriusKit.Codec {
    var minimumFrameInterval: CMTime {
        guard let frameRate = self.frameRate, frameRate > 0.0 else {
            return .zero
        }
        
        // 1 / {frameRate} 초 간격
        return CMTime(value: 1, timescale: CMTimeScale(frameRate))
    }
}

class AVFoundationScreenRecorder: NSObject, ScreenRecorder {
    private let logger = NoctilucaLogger(category: "AVFoundationScreenRecorder")
    
    let id: UUID = UUID()
    
    var queue: DispatchQueue
    weak var delegate: (any ScreenRecorderDelegate)?
    
    private var captureSession = AVCaptureSession()
    
    private var screenInput: AVCaptureScreenInput? = nil
    private var captureOutput: AVCaptureVideoDataOutput? = nil
    
    init(queue: DispatchQueue) {
        self.queue = queue
    }
    
    func prepare(with args: ScreenRecorderArgs) async throws {
        let source = args.source
        let codec = args.codec
        let flags = args.flags

        guard case .entireDisplay(let rawDisplayID) = source else {
            logger.error("prepare(): AVFoundationScreenRecorder only supports entire display capture.")
            throw ScreenRecorderPrepareError.invalidSource
        }
        
        let displayID: CGDirectDisplayID = if source.requiresPrimaryDisplay {
            CGMainDisplayID()
        } else {
            CGDirectDisplayID(rawDisplayID)
        }
        
        guard let screenInput = AVCaptureScreenInput(displayID: displayID) else {
            logger.error("prepare(): Failed to create AVCaptureScreenInput for display ID: \(displayID)")
            throw ScreenRecorderPrepareError.internalError
        }
        
        let captureOutput = AVCaptureVideoDataOutput()
        
        captureSession.beginConfiguration()
        
        // TODO: 추후 커서 숨기거나 해야 함
        
        screenInput.minFrameDuration = codec.minimumFrameInterval
        
        screenInput.capturesCursor = flags.contains(.showCursor)
        screenInput.removesDuplicateFrames = true
        
        captureOutput.alwaysDiscardsLateVideoFrames = true
        
        captureOutput.setSampleBufferDelegate(self, queue: self.queue)
        captureOutput.videoSettings = [
            (kCVPixelBufferPixelFormatTypeKey as String): kCVPixelFormatType_32BGRA,
        ]
        
        if (!captureSession.canAddInput(screenInput)) {
            throw ScreenRecorderPrepareError.internalError
        }
        captureSession.addInput(screenInput)
        captureSession.addOutput(captureOutput)

        captureSession.commitConfiguration()
    }
    
    func start() async throws {
        captureSession.startRunning()
    }
    
    func stop() async throws {
        captureSession.stopRunning()
    }
}

extension AVFoundationScreenRecorder: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // TODO: copy samplebuffer
        
        self.delegate?.screenRecorder(self, didCaptureFrame: sampleBuffer)
    }
}
