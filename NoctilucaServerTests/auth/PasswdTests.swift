//
//  PasswdTests.swift
//  NoctilucaServerTests
//
//  Created by Coding Assistant on 4/30/26.
//

import XCTest

@testable import NoctilucaServerTestsHost

final class PasswdTests: XCTestCase {

    // MARK: - __getpwnam

    func testGetpwnamReturnsRootEntry() throws {
        let entry = try Passwd.__getpwnam("root")

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.uid, 0)
        XCTAssertEqual(entry?.username, "root")
    }

    func testGetpwnamReturnsNilForNonexistentUser() throws {
        let unlikelyName = "nch002-nonexistent-\(UUID().uuidString)"

        let entry = try Passwd.__getpwnam(unlikelyName)

        XCTAssertNil(entry)
    }

    // MARK: - __getpwuid

    func testGetpwuidReturnsRootEntry() throws {
        let entry = try Passwd.__getpwuid(0)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.uid, 0)
        XCTAssertEqual(entry?.username, "root")
    }

    // MARK: - __getgrgid_gr_name

    func testGetgrgidReturnsWheelForGid0() throws {
        let groupName = try Passwd.__getgrgid_gr_name(0)

        XCTAssertEqual(groupName, "wheel")
    }
}
