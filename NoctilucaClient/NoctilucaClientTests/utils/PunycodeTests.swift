//
//  NoctilucaClientTests.swift
//  NoctilucaClientTests
//
//  Created by Gyuhwan Park on 12/22/25.
//

import XCTest
@testable import NoctilucaClient

final class PunycodeTests: XCTestCase {
    private let punycode = Punycode()

    func testEncodeSingleLabel() {
        let input = "b\u{00FC}cher"
        XCTAssertEqual(punycode.encode(input), "xn--bcher-kva")
    }

    func testEncodeHostnameWithMultipleLabels() {
        let input = "www.b\u{00FC}cher.de"
        XCTAssertEqual(punycode.encode(input), "www.xn--bcher-kva.de")
    }

    func testEncodeKeepsAsciiLabels() {
        XCTAssertEqual(punycode.encode("Example.COM"), "Example.COM")
    }

    func testEncodeLowercasesPunycodePrefix() {
        XCTAssertEqual(punycode.encode("XN--BCHER-KVA"), "xn--bcher-kva")
    }

    func testDecodeSingleLabel() {
        XCTAssertEqual(punycode.decode("xn--bcher-kva"), "b\u{00FC}cher")
    }

    func testDecodeHostnameWithMultipleLabels() {
        XCTAssertEqual(punycode.decode("www.xn--bcher-kva.de"), "www.b\u{00FC}cher.de")
    }

    func testDecodeInvalidPunycodeReturnsOriginal() {
        XCTAssertEqual(punycode.decode("xn--$$$"), "xn--$$$")
        XCTAssertEqual(punycode.decode("www.xn--$$$.de"), "www.xn--$$$.de")
    }

    func testIsPunycode() {
        XCTAssertFalse(punycode.isPunycode("example.com"))
        XCTAssertTrue(punycode.isPunycode("xn--bcher-kva"))
        XCTAssertTrue(punycode.isPunycode("www.xn--bcher-kva.de"))
    }

    func testKnownExamples() {
        let manana = "ma\u{00F1}ana"
        XCTAssertEqual(punycode.encode(manana), "xn--maana-pta")
        XCTAssertEqual(punycode.decode("xn--maana-pta"), manana)

        let example = "\u{4F8B}\u{5B50}"
        XCTAssertEqual(punycode.encode(example), "xn--fsqu00a")
        XCTAssertEqual(punycode.decode("xn--fsqu00a"), example)

        let korea = "\u{D55C}\u{AD6D}"
        XCTAssertEqual(punycode.encode(korea), "xn--3e0b707e")
        XCTAssertEqual(punycode.decode("xn--3e0b707e"), korea)
    }
}
