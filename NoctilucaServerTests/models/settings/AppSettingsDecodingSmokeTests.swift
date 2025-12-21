//
//  AppSettingsDecodingSmokeTests.swift
//  NoctilucaServerTests
//
//  Created by Coding Assistant on 12/21/25.
//

import XCTest
import SiriusKit
@testable import NoctilucaServer

final class AppSettingsDecodingSmokeTests: XCTestCase {
    func testDecodeWithPartialAndInvalidValuesDoesNotThrow() {
        let json = """
        {
          "general": {
            "maxConcurrentSessions": 4
          },
          "security": {
            "maxLoginAttempts": "not-a-number"
          },
          "quicTransport": {
            "listenPort": "invalid",
            "tlsUseAutoconf": true,
            "tlsStrictValidation": "nope"
          },
          "projection": {
            "preferredScreenRecorder": "unknown",
            "codecSpecifications": [
              {
                "fourcc": "avc1",
                "options": {
                  "mandatory": { "profile": "high" },
                  "optional": { "color-format": "yuv420" }
                },
                "frame_rate": "sixty"
              },
              {
                "options": {
                  "profile": "baseline"
                }
              }
            ]
          },
          "unknown": {
            "foo": "bar"
          }
        }
        """

        let data = Data(json.utf8)

        do {
            let settings = try JSONDecoder().decode(AppSettings.self, from: data)

            XCTAssertEqual(settings.general.maxConcurrentSessions, 4)
            XCTAssertEqual(settings.security.maxLoginAttempts, 3)
            XCTAssertEqual(settings.quicTransport.listenPort, SiriusQUICDefaultPort)
            XCTAssertEqual(settings.quicTransport.tlsUseAutoconf, true)
            XCTAssertEqual(settings.quicTransport.tlsStrictValidation, false)
            XCTAssertEqual(settings.projection.preferredScreenRecorder, .screenCaptureKit)

            XCTAssertEqual(settings.projection.codecSpecifications.count, 2)

            let firstSpec = settings.projection.codecSpecifications.first
            XCTAssertEqual(firstSpec?.option(.profile), CodecOptionValue(rawValue: "high"))
            XCTAssertEqual(firstSpec?.option(.colorFormat), CodecOptionValue(rawValue: "yuv420"))
        } catch {
            XCTFail("Decoding failed: \(error)")
        }
    }
}
