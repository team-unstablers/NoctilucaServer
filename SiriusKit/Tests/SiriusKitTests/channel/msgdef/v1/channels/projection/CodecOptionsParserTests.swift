//
//  CodecOptionsParserTests.swift
//  SiriusKitTests
//
//  Created by Kagamine Len on 4/25/26.
//

import Foundation
import Testing

@testable import SiriusKit

@Suite("CodecOptionsParser")
struct CodecOptionsParserTests {
    // MARK: - parseAsDictionary

    @Test("nil/빈 입력이면 빈 딕셔너리를 반환한다")
    func parseAsDictionaryHandlesNilAndEmptyInput() {
        #expect(CodecOptionsParser.parseAsDictionary(optionsString: nil).isEmpty)
        #expect(CodecOptionsParser.parseAsDictionary(optionsString: "").isEmpty)
        #expect(CodecOptionsParser.parseAsDictionary(optionsString: "   ").isEmpty)
    }

    @Test("!required 프래그마를 제거하고 키를 소문자화하며, 'value' 패턴이 아닌 항목은 무시한다")
    func parseAsDictionaryStripsRequiredAndNormalizesKeys() {
        let parsed = CodecOptionsParser.parseAsDictionary(
            optionsString: " Profile : 'High' !required ; hardware-acceleration:'forced'!required; level: 4.1; invalid ; color-format: 'yuv420'"
        )

        #expect(parsed["profile"] == "High")
        #expect(parsed["hardware-acceleration"] == "forced")
        #expect(parsed["color-format"] == "yuv420")
        #expect(parsed["level"] == nil)
        #expect(parsed.count == 3)
    }

    // MARK: - parse

    @Test("!required 프래그마를 기준으로 mandatory/optional을 분리한다")
    func parseReturnsCodecOptionsWithRequiredPragma() {
        let parsed = CodecOptionsParser.parse(
            optionsString: """
            profile: 'main' !required;
            color-depth: '10';
            dynamic-range: 'hdr';
            level: '4.2';
            hardware-acceleration:'forced'!required;
            color-format: 'yuv420'
            """
        )

        #expect(parsed.mandatory[.profile] == CodecOptionValue(rawValue: "main"))
        #expect(parsed.mandatory[.hardwareAcceleration] == CodecOptionValue(rawValue: "forced"))
        #expect(parsed.mandatory[.level] == nil)
        #expect(parsed.mandatory.count == 2)

        #expect(parsed.optional[.level] == CodecOptionValue(rawValue: "4.2"))
        #expect(parsed.optional[.colorFormat] == CodecOptionValue(rawValue: "yuv420"))
        #expect(parsed.optional[.colorDepth] == CodecOptionValue(rawValue: "10"))
        #expect(parsed.optional[.dynamicRange] == CodecOptionValue(rawValue: "hdr"))
        #expect(parsed.optional.count == 4)
    }

    // MARK: - serialize + round-trip

    @Test("serialize → parse 라운드트립은 원본과 동일한 CodecOptions를 반환한다")
    func serializeAndParseRoundTrip() {
        let original = CodecOptions(
            mandatory: [
                .hardwareAcceleration: CodecOptionValue(rawValue: "forced")
            ],
            optional: [
                .profile: CodecOptionValue(rawValue: "high"),
                .colorFormat: CodecOptionValue(rawValue: "yuv420p")
            ]
        )

        let serialized = CodecOptionsParser.serialize(options: original)
        let reparsed = CodecOptionsParser.parse(optionsString: serialized)

        #expect(reparsed == original)
    }
}
