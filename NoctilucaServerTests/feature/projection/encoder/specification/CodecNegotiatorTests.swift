//
//  CodecNegotiatorTests.swift
//  NoctilucaServerTests
//
//  Created by Coding Assistant on 2/26/26.
//

import XCTest
import SiriusKit
@testable import NoctilucaServerTestsHost

final class CodecSpecificationMergingTests: XCTestCase {

    // MARK: - merging(with:) Tests

    func testMergingAdoptsClientOptionalWhenServerIsAuto() {
        let serverSpec = CodecSpecification(fourCC: .hvc1)
            .option(.displayDensity, .kDisplayDensityAuto)
            .option(.colorFormat, .kColorFormatAuto)

        let clientCodec = Codec(
            fourCC: .hvc1,
            frameRate: nil,
            size: nil,
            options: CodecOptions(
                mandatory: [:],
                optional: [
                    .displayDensity: .kDisplayDensityBest,
                    .colorFormat: .kColorFormatYUV420
                ]
            ),
            quality: .auto(mode: .balancedPriority)
        )

        let merged = serverSpec.merging(with: clientCodec)

        XCTAssertEqual(merged.options[.displayDensity], .kDisplayDensityBest)
        XCTAssertEqual(merged.options[.colorFormat], .kColorFormatYUV420)
    }

    func testMergingPreservesServerConcreteValue() {
        let serverSpec = CodecSpecification(fourCC: .hvc1)
            .option(.colorRange, .kColorRangeLimited)
            .option(.dynamicRange, .kDynamicRangeSDR)

        let clientCodec = Codec(
            fourCC: .hvc1,
            frameRate: nil,
            size: nil,
            options: CodecOptions(
                mandatory: [:],
                optional: [
                    .colorRange: .kColorRangeFull,
                    .dynamicRange: .kDynamicRangeHDR
                ]
            ),
            quality: .auto(mode: .balancedPriority)
        )

        let merged = serverSpec.merging(with: clientCodec)

        // XCTAssertEqual(merged.options[.colorRange], .kColorRangeLimited, "서버의 구체적 값(limited)이 유지되어야 함")
        XCTAssertEqual(merged.options[.colorRange], .kColorRangeFull, "color range에 한해서는 클라이언트의 요구 사항이 반영되어야 함")
        XCTAssertEqual(merged.options[.dynamicRange], .kDynamicRangeSDR,
                       "서버의 구체적 값(SDR)이 유지되어야 함")
    }

    func testMergingAdoptsClientKeyWhenServerLacks() {
        let serverSpec = CodecSpecification(fourCC: .hvc1)
            .option(.colorFormat, .kColorFormatAuto)

        let clientCodec = Codec(
            fourCC: .hvc1,
            frameRate: nil,
            size: nil,
            options: CodecOptions(
                mandatory: [:],
                optional: [
                    .displayDensity: .kDisplayDensityBest,
                    .quantizeLevel: .kQuantizeLevel2
                ]
            ),
            quality: .auto(mode: .balancedPriority)
        )

        let merged = serverSpec.merging(with: clientCodec)

        XCTAssertEqual(merged.options[.displayDensity], .kDisplayDensityBest,
                       "서버에 없는 키는 클라이언트 값이 채택되어야 함")
        XCTAssertEqual(merged.options[.quantizeLevel], .kQuantizeLevel2,
                       "서버에 없는 키는 클라이언트 값이 채택되어야 함")
    }

    func testMergingFrameRate() {
        // 서버 auto(0) + 클라이언트 30 → 30 채택
        var serverSpec = CodecSpecification(fourCC: .hvc1)
        serverSpec.frameRate = 0

        let clientCodec30 = Codec(
            fourCC: .hvc1,
            frameRate: 30.0,
            size: nil,
            options: CodecOptions(),
            quality: .auto(mode: .balancedPriority)
        )

        let merged1 = serverSpec.merging(with: clientCodec30)
        XCTAssertEqual(merged1.frameRate, 30.0)

        // 서버 60 + 클라이언트 30 → 서버 60 유지
        var serverSpec60 = CodecSpecification(fourCC: .hvc1)
        serverSpec60.frameRate = 60.0

        let merged2 = serverSpec60.merging(with: clientCodec30)
        XCTAssertEqual(merged2.frameRate, 60.0,
                       "서버가 구체적 frameRate를 가지면 유지되어야 함")
    }

    func testMergingMandatoryTakesPriorityOverOptional() {
        let serverSpec = CodecSpecification(fourCC: .hvc1)
            .option(.colorFormat, .kColorFormatAuto)

        let clientCodec = Codec(
            fourCC: .hvc1,
            frameRate: nil,
            size: nil,
            options: CodecOptions(
                mandatory: [.colorFormat: .kColorFormatYUV420],
                optional: [.colorFormat: .kColorFormatYUV444]
            ),
            quality: .auto(mode: .balancedPriority)
        )

        let merged = serverSpec.merging(with: clientCodec)

        XCTAssertEqual(merged.options[.colorFormat], .kColorFormatYUV420,
                       "클라이언트 mandatory가 optional보다 우선해야 함")
    }
}


final class BalancedCodecNegotiatorTests: XCTestCase {

    // MARK: - negotiate() Tests

    func testNegotiateReturnsClientQuality() {
        let negotiator = BalancedCodecNegotiator(specifications: [.hevc])

        let clientCodec = Codec(
            fourCC: .hvc1,
            frameRate: nil,
            size: nil,
            options: CodecOptions(),
            quality: .constantBitrate(bitrateKbps: 5000)
        )

        let result = negotiator.negotiate(with: [clientCodec])

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.fourCC, .hvc1)
        XCTAssertEqual(result?.quality, .constantBitrate(bitrateKbps: 5000),
                       "협상 결과에 클라이언트의 quality가 반영되어야 함")
    }

    func testNegotiateRespectsClientOrder() {
        // 서버: [avc1, hvc1] 순서, 클라이언트: [hvc1, avc1] 순서
        let negotiator = BalancedCodecNegotiator(specifications: [.h264, .hevc])

        let clientCodecs = [
            Codec(fourCC: .hvc1, frameRate: nil, size: nil,
                  options: CodecOptions(), quality: .auto(mode: .balancedPriority)),
            Codec(fourCC: .avc1, frameRate: nil, size: nil,
                  options: CodecOptions(), quality: .auto(mode: .balancedPriority))
        ]

        let result = negotiator.negotiate(with: clientCodecs)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.fourCC, .hvc1,
                       "클라이언트의 1순위(hvc1)가 선택되어야 함")
    }

    func testNegotiateFallbackWhenNoCompatible() {
        // 서버와 클라이언트가 같은 FourCC를 가지지만 mandatory 옵션이 비호환
        let serverSpec = CodecSpecification(fourCC: .avc1)
            .option(.profile, .kProfileH264Baseline)

        let negotiator = BalancedCodecNegotiator(specifications: [serverSpec])

        let clientCodec = Codec(
            fourCC: .avc1,
            frameRate: nil,
            size: nil,
            options: CodecOptions(
                mandatory: [.profile: .kProfileH264High],
                optional: [:]
            ),
            quality: .auto(mode: .balancedPriority)
        )

        let result = negotiator.negotiate(with: [clientCodec])

        // isCompatible이 실패하므로 머지 경로를 타지 않고 fallback으로 가야 함
        XCTAssertNotNil(result, "FourCC가 같으므로 fallback이 동작해야 함")
        XCTAssertEqual(result?.fourCC, .avc1)
    }

    func testNegotiateReturnsNilWhenNoMatch() {
        let negotiator = BalancedCodecNegotiator(specifications: [.hevc])

        // 0.9.10 에서 제거된 fourCC (zrle) 또는 임의 unknown fourCC 가 와이어로
        // 들어와도 negotiator 는 panic 없이 nil 을 반환해야 한다.
        let clientCodec = Codec(
            fourCC: .zrle,
            frameRate: nil,
            size: nil,
            options: CodecOptions(),
            quality: .auto(mode: .balancedPriority)
        )

        let result = negotiator.negotiate(with: [clientCodec])

        XCTAssertNil(result, "deprecated/unknown fourCC 만 들어오면 negotiator 는 nil 을 반환해야 함")
    }

    func testNegotiateMergesClientOptionalOptions() {
        let negotiator = BalancedCodecNegotiator(specifications: [.hevc])

        let clientCodec = Codec(
            fourCC: .hvc1,
            frameRate: nil,
            size: nil,
            options: CodecOptions(
                mandatory: [:],
                optional: [.displayDensity: .kDisplayDensityBest]
            ),
            quality: .auto(mode: .balancedPriority)
        )

        let result = negotiator.negotiate(with: [clientCodec])

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.option(.displayDensity), .kDisplayDensityBest,
                       "클라이언트의 optional displayDensity가 협상 결과에 반영되어야 함")
    }
}
