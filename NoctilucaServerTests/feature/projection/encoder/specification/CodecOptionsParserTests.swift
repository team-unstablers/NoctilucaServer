//
//  CodecOptionsParserTests.swift
//  NoctilucaServerTests
//
//  Created by Coding Assistant on 1/6/25.
//

import XCTest
@testable import NoctilucaServer

final class CodecOptionsParserTests: XCTestCase {
    
    func testParseAsDictionaryHandlesNilAndEmptyInput() {
        XCTAssertTrue(CodecOptionsParser.parseAsDictionary(optionsString: nil).isEmpty)
        XCTAssertTrue(CodecOptionsParser.parseAsDictionary(optionsString: "").isEmpty)
        XCTAssertTrue(CodecOptionsParser.parseAsDictionary(optionsString: "   ").isEmpty)
    }
    
    func testParseAsDictionaryRequiresQuotedValuesAndNormalizesKeys() {
        let parsed = CodecOptionsParser.parseAsDictionary(
            optionsString: " Profile : 'High' ; hardware-acceleration:'forced'; level: 4.1; invalid ; color-format: 'yuv420'"
        )
        
        XCTAssertEqual(parsed["profile"], "High")
        XCTAssertEqual(parsed["hardware-acceleration"], "forced")
        XCTAssertEqual(parsed["color-format"], "yuv420")
        XCTAssertNil(parsed["level"])
        XCTAssertEqual(parsed.count, 3)
    }
    
    func testParseFiltersUnsupportedKeys() {
        let parsed = CodecOptionsParser.parse(
            optionsString: "profile: 'main'; color-depth: '10'; dynamic-range: 'hdr'; level: '4.2'"
        )
        
        XCTAssertEqual(parsed[.profile], CodecOptionValue(rawValue: "main"))
        XCTAssertEqual(parsed[.level], CodecOptionValue(rawValue: "4.2"))
        XCTAssertNil(parsed[.colorDepth])
        XCTAssertNil(parsed[.dynamicRange])
        XCTAssertEqual(parsed.count, 2)
    }
    
    func testSerializeAndParseRoundTrip() {
        let original: [CodecOptionKey: CodecOptionValue] = [
            .hardwareAcceleration: CodecOptionValue(rawValue: "forced"),
            .profile: CodecOptionValue(rawValue: "high"),
            .colorFormat: CodecOptionValue(rawValue: "yuv420p")
        ]
        
        let serialized = CodecOptionsParser.serialize(options: original)
        let reparsed = CodecOptionsParser.parse(optionsString: serialized)
        
        XCTAssertEqual(reparsed, original)
    }
}
