import XCTest
import AVFoundation
import VideoToolbox
import SiriusKitClient
@testable import Noctiluca_Navigator

// FIXME: NoctilucaClientTests target 이 SiriusKitCore framework 와 직접 link 되지 않아
// CodecFourCC.avc1 / CodecOptions / FrameDataHeader 등이 link 단계에서 undefined symbol 로 떨어진다.
// 우선 fsaccess 단위 테스트가 돌아갈 수 있도록 본 파일을 임시로 컴파일에서 제외.
// 향후 NoctilucaClientTests 의 Frameworks build phase 에 SiriusKitCore 를 추가하거나
// SiriusKitClient 가 해당 심볼을 재노출하면 #if false 를 제거할 것.
#if false

final class VTVideoDecoderFallbackTests: XCTestCase {
    func testCreationAttemptsOrder() {
        let attempts = VTVideoDecoder.decompressionSessionCreationAttempts

#if targetEnvironment(simulator)
        XCTAssertEqual(attempts, [
            VTDecompressionSessionCreationAttempt(requiresHardwareDecoder: false, backend: .software),
        ])
#else
        XCTAssertEqual(attempts, [
            VTDecompressionSessionCreationAttempt(requiresHardwareDecoder: true, backend: .hardware),
            VTDecompressionSessionCreationAttempt(requiresHardwareDecoder: false, backend: .software),
        ])
#endif
    }

    func testDecodeRetriesAllConfiguredAttemptsWhenSessionCreationFails() throws {
        let attempts = VTVideoDecoder.decompressionSessionCreationAttempts
        var observedRequiresHardwareFlags: [Bool] = []
        var creationCallCount = 0

        let decoder = VTVideoDecoder(
            workerQueue: DispatchQueue(label: "test.VTVideoDecoder.worker"),
            callbackQueue: DispatchQueue(label: "test.VTVideoDecoder.callback"),
            decompressionSessionCreateHandler: { _, decoderSpecification, _, _, _ in
                creationCallCount += 1

                let specification = decoderSpecification as NSDictionary?
                let requiresHardware =
                    specification?[kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder] != nil
                observedRequiresHardwareFlags.append(requiresHardware)

                return OSStatus(paramErr)
            }
        )

        try decoder.prepare(
            with: VideoDecoderConfiguration(
                codec: makeCodec(),
                initialFormatDescription: try makeH264FormatDescription()
            )
        )
        try decoder.start()

        let payload = Data([0x00])
        let frame = EncodedFrameInput(
            header: FrameDataHeader(
                frameID: 1,
                frameLength: UInt32(payload.count),
                presentationTimestamp: 0
            ),
            data: payload,
            formatDescription: nil
        )

        XCTAssertThrowsError(try decoder.decode(frame)) { error in
            guard case let VideoDecoderError.decompressionSessionFailed(status) = error else {
                XCTFail("Expected decompressionSessionFailed, got: \(error)")
                return
            }

            XCTAssertEqual(status, OSStatus(paramErr))
        }

        XCTAssertEqual(creationCallCount, attempts.count)
        XCTAssertEqual(
            observedRequiresHardwareFlags,
            attempts.map(\.requiresHardwareDecoder)
        )
    }

    func testDecoderTypeNameIsNeutralBeforeSessionCreation() {
        let decoder = VTVideoDecoder()
        XCTAssertEqual(decoder.decoderTypeName, "VideoToolbox")
    }

    private func makeCodec() -> Codec {
        Codec(
            fourCC: .avc1,
            frameRate: 60.0,
            size: nil,
            options: CodecOptions(),
            quality: .auto(mode: .balancedPriority)
        )
    }

    private func makeH264FormatDescription() throws -> CMFormatDescription {
        var formatDescription: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCMVideoCodecType_H264,
            width: 1920,
            height: 1080,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )

        guard status == noErr, let formatDescription else {
            throw NSError(domain: "VTVideoDecoderFallbackTests", code: Int(status))
        }

        return formatDescription
    }
}

#endif // FIXME: re-enable once SiriusKitCore symbols can be linked from the test target.
