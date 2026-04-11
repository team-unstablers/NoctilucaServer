//
//  ScreenThumbnailer.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 3/14/26.
//

import Foundation
import CoreGraphics
import CoreMedia
import VideoToolbox

import SiriusKit

enum ScreenThumbnailerError: Error {
    case noImageBuffer
    case cgImageConversionFailed
}

/// ScreenCaptureKit 기반 one-shot 썸네일 캡처 유틸리티.
/// 단일 프레임을 캡처한 후 레코더를 정리한다.
final class ScreenThumbnailer: @unchecked Sendable {
    private static let queue: DispatchQueue = DispatchQueue(label: "app.noctiluca.server.projection.ScreenThumbnailer", attributes: .concurrent)

    private let recorder: any ScreenRecorder
    private let lock = NSLock()
    private var continuation: CheckedContinuation<CGImage, Error>?

    init(_ displayId: CGDirectDisplayID) async throws {
        self.recorder = await ScreenRecorderFactory.create(preferred: .screenCaptureKit, queue: Self.queue)
        self.recorder.delegate = self

        try await self.recorder.prepare(with: ScreenRecorderArgs(
            source: .entireDisplay(displayID: Int64(displayId)),
            codec: .init(fourCC: .avc1, frameRate: 1, size: nil, options: .init(), quality: .auto(mode: .balancedPriority)),
            flags: [],
        ))
    }

    func capture() async throws -> CGImage {
        try await recorder.start()

        defer {
            Task { [recorder] in
                try? await recorder.stop()
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
        }
    }
}

extension ScreenThumbnailer: ScreenRecorderDelegate {
    func screenRecorderDidStart(_ recorder: any ScreenRecorder) {}

    func screenRecorder(_ recorder: any ScreenRecorder, didStopWithError error: Error?) {
        guard let error else { return }

        lock.lock()
        let cont = self.continuation
        self.continuation = nil
        lock.unlock()

        NoctilucaLogger(category: "ScreenThumbnailer").error("ScreenRecorder error: \(error)")
        cont?.resume(throwing: error)
    }

    func screenRecorder(_ recorder: any ScreenRecorder, didCaptureFrame frameData: CMSampleBuffer) {
        lock.lock()
        let cont = self.continuation
        self.continuation = nil
        lock.unlock()

        guard let cont else { return }

        guard let pixelBuffer = frameData.imageBuffer else {
            cont.resume(throwing: ScreenThumbnailerError.noImageBuffer)
            return
        }

        var cgImage: CGImage?
        let status = VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)

        guard status == noErr, let image = cgImage else {
            cont.resume(throwing: ScreenThumbnailerError.cgImageConversionFailed)
            return
        }

        cont.resume(returning: image)
    }
}
