//
//  AppSettingsDecodingSmokeTests.swift
//  NoctilucaClientTests
//
//  Created by Coding Assistant on 12/21/25.
//

import XCTest
@testable import Noctiluca_Navigator

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
            // FIXME: AppSettings.Input.mouseMoveMode 가 모델에서 제거되어 컴파일이 깨진 상태.
            // 해당 필드가 다시 추가되거나 대체 API 가 정해지면 assertion 복원 필요.
            // XCTAssertEqual(settings.input.mouseMoveMode, .relative)
            XCTAssertEqual(settings.input.modifierKeyOverrides.capsLock, .command)
            XCTAssertEqual(settings.input.modifierKeyOverrides.control, .control)
            XCTAssertEqual(settings.security.tlsValidationPolicy, .default)
            XCTAssertEqual(settings.security.disableClientVersionAnnouncement, false)
        } catch {
            XCTFail("Decoding failed: \(error)")
        }
    }
}
