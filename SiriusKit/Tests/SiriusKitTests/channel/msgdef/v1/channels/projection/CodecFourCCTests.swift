//
//  CodecFourCCTests.swift
//  SiriusKitTests
//
//  Created by Kagamine Len on 4/12/26.
//

import Foundation
import Testing

@testable import SiriusKit

@Suite("CodecFourCC")
struct CodecFourCCTests {
    // MARK: - Initializers

    @Test("character initializer packs bytes in big-endian order")
    func characterInitializerPacksBigEndian() {
        let fourcc = CodecFourCC("A", "V", "C", "1")

        // 'A' = 0x41, 'V' = 0x56, 'C' = 0x43, '1' = 0x31
        #expect(fourcc.rawValue == 0x4156_4331)
    }

    @Test("raw value initializer preserves value")
    func rawValueInitializerPreservesValue() {
        let fourcc = CodecFourCC(rawValue: 0x4856_4331) // "HVC1"

        #expect(fourcc.rawValue == 0x4856_4331)
    }

    // MARK: - stringRepresentation

    @Test("stringRepresentation decodes bytes back to ASCII")
    func stringRepresentationDecodesBytesToAscii() {
        let fourcc = CodecFourCC(rawValue: 0x4D4A_5047) // "MJPG"

        #expect(fourcc.stringRepresentation == "MJPG")
    }

    @Test("character initializer and stringRepresentation round-trip")
    func characterInitAndStringRepresentationRoundTrip() {
        let fourcc = CodecFourCC("W", "E", "B", "P")

        #expect(fourcc.stringRepresentation == "WEBP")
    }

    // MARK: - Predefined constants

    @Test("predefined constants match documented FourCC codes")
    func predefinedConstantsMatchDocumentedCodes() {
        #expect(CodecFourCC.avc1.stringRepresentation == "AVC1")
        #expect(CodecFourCC.hvc1.stringRepresentation == "HVC1")
        #expect(CodecFourCC.vp80.stringRepresentation == "VP80")
        #expect(CodecFourCC.zrle.stringRepresentation == "ZRLE")
        #expect(CodecFourCC.mjpg.stringRepresentation == "MJPG")
        #expect(CodecFourCC.webp.stringRepresentation == "WEBP")
    }

    @Test("predefined constants have expected raw values")
    func predefinedConstantsHaveExpectedRawValues() {
        #expect(CodecFourCC.avc1.rawValue == 0x4156_4331)
        #expect(CodecFourCC.hvc1.rawValue == 0x4856_4331)
        #expect(CodecFourCC.vp80.rawValue == 0x5650_3830)
        #expect(CodecFourCC.zrle.rawValue == 0x5A52_4C45)
        #expect(CodecFourCC.mjpg.rawValue == 0x4D4A_5047)
        #expect(CodecFourCC.webp.rawValue == 0x5745_4250)
    }

    // MARK: - Equatable

    @Test("equal raw values produce equal instances")
    func equalRawValuesAreEqual() {
        let lhs = CodecFourCC("A", "V", "C", "1")
        let rhs = CodecFourCC(rawValue: 0x4156_4331)

        #expect(lhs == rhs)
        #expect(lhs == .avc1)
    }

    @Test("different raw values produce distinct instances")
    func differentRawValuesAreNotEqual() {
        #expect(CodecFourCC.avc1 != CodecFourCC.hvc1)
    }

    // MARK: - CustomDebugStringConvertible

    @Test("debugDescription includes ASCII and zero-padded hex")
    func debugDescriptionFormat() {
        #expect(CodecFourCC.avc1.debugDescription == "FourCC (AVC1, 0x41564331)")
        #expect(CodecFourCC.webp.debugDescription == "FourCC (WEBP, 0x57454250)")
    }

    // MARK: - Codable

    /// JSONEncoder/JSONDecoder는 플랫폼에 따라 최상위 fragment 지원이 다를 수 있어
    /// wrapper 구조체를 통해 검증합니다.
    private struct Wrapper: Codable, Equatable {
        let codec: CodecFourCC
    }

    @Test("encoding wraps FourCC as 4-character JSON string")
    func encodingProducesFourCharacterString() throws {
        let wrapper = Wrapper(codec: .avc1)

        let data = try JSONEncoder().encode(wrapper)
        let json = String(decoding: data, as: UTF8.self)

        #expect(json == #"{"codec":"AVC1"}"#)
    }

    @Test("decoding accepts a 4-character string")
    func decodingAcceptsFourCharacterString() throws {
        let json = Data(#"{"codec":"HVC1"}"#.utf8)

        let decoded = try JSONDecoder().decode(Wrapper.self, from: json)

        #expect(decoded.codec == .hvc1)
    }

    @Test("encode/decode round-trip preserves value")
    func codableRoundTripPreservesValue() throws {
        let original = Wrapper(codec: .mjpg)

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Wrapper.self, from: encoded)

        #expect(decoded == original)
    }

    @Test("decoding rejects strings shorter than 4 characters")
    func decodingRejectsShortStrings() {
        let json = Data(#"{"codec":"AVC"}"#.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Wrapper.self, from: json)
        }
    }

    @Test("decoding rejects strings longer than 4 characters")
    func decodingRejectsLongStrings() {
        let json = Data(#"{"codec":"AVC12"}"#.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Wrapper.self, from: json)
        }
    }

    @Test("decoding rejects empty strings")
    func decodingRejectsEmptyStrings() {
        let json = Data(#"{"codec":""}"#.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Wrapper.self, from: json)
        }
    }
}
