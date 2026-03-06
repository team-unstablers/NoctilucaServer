//
//  CodecOptionsParserTests.swift
//  NoctilucaServerTests
//
//  Created by Coding Assistant on 1/6/25.
//

import XCTest
@testable import NoctilucaServerTestsHost

/*
final class CodecOptionsParserTests: XCTestCase {
    
    func testParseAsDictionaryHandlesNilAndEmptyInput() {
        XCTAssertTrue(CodecOptionsParser.parseAsDictionary(optionsString: nil).isEmpty)
        XCTAssertTrue(CodecOptionsParser.parseAsDictionary(optionsString: "").isEmpty)
        XCTAssertTrue(CodecOptionsParser.parseAsDictionary(optionsString: "   ").isEmpty)
    }
    
    func testParseAsDictionaryStripsRequiredAndNormalizesKeys() {
        let parsed = CodecOptionsParser.parseAsDictionary(
            optionsString: " Profile : 'High' !required ; hardware-acceleration:'forced'!required; level: 4.1; invalid ; color-format: 'yuv420'"
        )
        
        XCTAssertEqual(parsed["profile"], "High")
        XCTAssertEqual(parsed["hardware-acceleration"], "forced")
        XCTAssertEqual(parsed["color-format"], "yuv420")
        XCTAssertNil(parsed["level"])
        XCTAssertEqual(parsed.count, 3)
    }
    
    func testParseReturnsCodecOptionsWithRequiredPragma() {
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
        
        XCTAssertEqual(parsed.mandatory[.profile], CodecOptionValue(rawValue: "main"))
        XCTAssertEqual(parsed.mandatory[.hardwareAcceleration], CodecOptionValue(rawValue: "forced"))
        XCTAssertNil(parsed.mandatory[.level])
        
        XCTAssertEqual(parsed.optional[.level], CodecOptionValue(rawValue: "4.2"))
        XCTAssertEqual(parsed.optional[.colorFormat], CodecOptionValue(rawValue: "yuv420"))
        XCTAssertNil(parsed.optional[.colorDepth])
        XCTAssertNil(parsed.optional[.dynamicRange])
        
        XCTAssertEqual(parsed.mandatory.count, 2)
        XCTAssertEqual(parsed.optional.count, 2)
    }
    
    func testSerializeAndParseRoundTrip() {
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
        
        XCTAssertEqual(reparsed, original)
    }
}
*/
