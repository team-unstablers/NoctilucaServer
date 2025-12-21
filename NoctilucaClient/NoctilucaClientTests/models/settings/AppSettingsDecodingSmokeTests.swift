//
//  AppSettingsDecodingSmokeTests.swift
//  NoctilucaClientTests
//
//  Created by Coding Assistant on 12/21/25.
//

import XCTest
@testable import NoctilucaClient

final class AppSettingsDecodingSmokeTests: XCTestCase {
    func testDecodeLegacyProjectionKeyAndInvalidEnums() {
        let json = """
        {
          "schemaVersion": "2",
          "projection": {
            "redirectionMethod": "cocoaEventTap",
            "mouseMoveMode": "relative",
            "modifierKeyOverrides": {
              "capsLock": "command",
              "control": "control"
            }
          },
          "security": {
            "tlsValidationPolicy": "unknown",
            "disableClientVersionAnnouncement": "nope"
          }
        }
        """

        let data = Data(json.utf8)

        do {
            let settings = try JSONDecoder().decode(AppSettings.self, from: data)

            XCTAssertEqual(settings.schemaVersion, AppSettings.currentSchemaVersion)
            XCTAssertEqual(settings.input.redirectionMethod, .cocoaEventTap)
            XCTAssertEqual(settings.input.mouseMoveMode, .relative)
            XCTAssertEqual(settings.input.modifierKeyOverrides.capsLock, .command)
            XCTAssertEqual(settings.input.modifierKeyOverrides.control, .control)
            XCTAssertEqual(settings.security.tlsValidationPolicy, .default)
            XCTAssertEqual(settings.security.disableClientVersionAnnouncement, false)
        } catch {
            XCTFail("Decoding failed: \(error)")
        }
    }
}
