//
//  V1DraftManifestDecodingTests.swift
//  NoctilucaServerTests
//
//  Created by Coding Assistant on 5/17/26.
//
//  ../NoctilucaPluginSystem/examples/server/ 의 공식 매니페스트 예시들이
//  v1-draft Codable 구현을 통해 손상 없이 디코딩되는지 검증한다.
//  원본 파일과 동기화 필요 — 스펙이 갱신되면 raw 문자열도 함께 갱신할 것.
//

import XCTest

@testable import NoctilucaPluginKit
@testable import NoctilucaServerTestsHost

final class V1DraftManifestDecodingTests: XCTestCase {

    // MARK: - cjk-assist.json (multi-export, license object)

    /// 원본: `NoctilucaPluginSystem/examples/server/official/cjk-assist.json`
    private static let cjkAssistJSON = #"""
    {
      "$schema": "https://noctiluca.app/schemas/server/pluginkit/v1-draft/20260516.json",
      "pluginKitVersion": "20260516",
      "id": "app.noctiluca.server.plugins.cjk-assist",
      "name": {
        "default": "CJK Input Assist",
        "ko": "CJK 입력 지원",
        "ja": "CJK入力アシスト",
        "zh-Hans": "CJK 输入辅助"
      },
      "authors": [
        "Gyuhwan Park★ <unstabler@unstabler.pl>"
      ],
      "description": {
        "default": "Provides additional features for CJK input assistance.",
        "ko": "CJK 입력 지원을 위한 추가 기능을 제공합니다.",
        "ja": "CJK入力アシストのための追加機能を提供します。",
        "zh-Hans": "为 CJK 输入辅助提供附加功能。"
      },
      "license": {
        "type": "proprietary",
        "name": "Noctiluca Server EULA",
        "url": "https://noctiluca.app/docs/eula/server"
      },
      "url": "https://noctiluca.app",
      "isolationPolicy": "isolate",
      "exports": [
        {
          "type": "keyboard_hack_v1",
          "id": "app.noctiluca.hidio.hack.cjk.emulate_win32_hangul_toggle",
          "name": {
            "default": "Keyboard Hack: Emulate Win32-style Han/Eng Toggle",
            "ko": "키보드 핵: Win32 스타일의 한/영 전환",
            "ja": "キーボードハック: Win32スタイルのハングル/英語切り替え",
            "zh-Hans": "键盘 Hack：模拟 Win32 风格的韩/英切换"
          },
          "description": {
            "default": "Emulates Win32-style Han/Eng toggle key behavior.",
            "ko": "Win32 스타일의 한/영 키를 통한 입력 언어 전환 동작을 에뮬레이트합니다.",
            "ja": "Win32スタイルのハングル/英語切り替えキーの動作をエミュレートします。",
            "zh-Hans": "模拟 Win32 风格的韩/英切换键的行为。"
          },
          "authors": [
            "Gyuhwan Park★ <unstabler@unstabler.pl>"
          ],
          "license": {
            "type": "proprietary",
            "name": "Noctiluca Server EULA",
            "url": "https://noctiluca.app/docs/eula/server"
          },
          "version": 1,
          "displayVersion": "1.0.0",
          "desiredKeyEvents": [
            "KEY_HANGEUL",
            "KEY_RIGHTALT",
            "KEY_RIGHTMETA"
          ]
        },
        {
          "type": "rpc_handler_v1",
          "id": "app.noctiluca.rpchandler.cjk.switch_im",
          "name": {
            "default": "RPC Handler: Switch Input Method",
            "ko": "RPC 핸들러: 입력 방법 전환",
            "ja": "RPCハンドラー: 入力メソッドの切り替え",
            "zh-Hans": "RPC 处理器：切换输入法"
          },
          "description": {
            "default": "Provides functionality for clients to switch input methods (IM).",
            "ko": "클라이언트들에게 입력 방법 (IM)을 전환할 수 있는 기능을 제공합니다.",
            "ja": "クライアントに入力メソッド (IM) を切り替える機能を提供します。",
            "zh-Hans": "为客户端提供切换输入法 (IM) 的功能。"
          },
          "authors": [
            "Gyuhwan Park★ <unstabler@unstabler.pl>"
          ],
          "license": {
            "type": "proprietary",
            "name": "Noctiluca Server EULA",
            "url": "https://noctiluca.app/docs/eula/server"
          },
          "version": 1,
          "displayVersion": "1.0.0",
          "supportedOperations": [
            "app.noctiluca.rpc.switch-im"
          ]
        }
      ]
    }
    """#

    func testDecodeOfficialCJKAssistExample() throws {
        let data = Data(Self.cjkAssistJSON.utf8)
        let manifest = try JSONDecoder().decode(PluginBundleManifestV1Draft.self, from: data)

        // Bundle-level fields
        XCTAssertEqual(manifest.id, "app.noctiluca.server.plugins.cjk-assist")
        XCTAssertEqual(manifest.pluginKitVersion, .v1)
        XCTAssertEqual(manifest.isolationPolicy, .isolate)
        XCTAssertEqual(manifest.url, "https://noctiluca.app")
        XCTAssertEqual(manifest.authors, ["Gyuhwan Park★ <unstabler@unstabler.pl>"])

        // Localized strings: default 키 + locale 키 모두 보존
        XCTAssertEqual(manifest.name.strings["default"], "CJK Input Assist")
        XCTAssertEqual(manifest.name.strings["ko"], "CJK 입력 지원")
        XCTAssertEqual(manifest.bundleDescription.strings["default"],
                       "Provides additional features for CJK input assistance.")

        // Bundle license = proprietary object form
        guard case .proprietary(let licenseName, let licenseURL) = manifest.license else {
            XCTFail("Expected bundle license = .proprietary, got \(manifest.license)")
            return
        }
        XCTAssertEqual(licenseName, "Noctiluca Server EULA")
        XCTAssertEqual(licenseURL?.absoluteString, "https://noctiluca.app/docs/eula/server")

        // Exports: 2개 (keyboard_hack_v1, rpc_handler_v1)
        XCTAssertEqual(manifest.exports.count, 2)

        // Export 0: keyboard_hack_v1
        guard case .keyboardHack(let keyboardHack) = manifest.exports[0] else {
            XCTFail("Expected exports[0] = .keyboardHack, got \(manifest.exports[0])")
            return
        }
        XCTAssertEqual(keyboardHack.id, "app.noctiluca.hidio.hack.cjk.emulate_win32_hangul_toggle")
        XCTAssertEqual(keyboardHack.type, .keyboardHack)
        XCTAssertEqual(keyboardHack.version, 1)
        XCTAssertEqual(keyboardHack.displayVersion, "1.0.0")
        XCTAssertEqual(keyboardHack.desiredKeyEvents,
                       ["KEY_HANGEUL", "KEY_RIGHTALT", "KEY_RIGHTMETA"])

        // Export 1: rpc_handler_v1
        guard case .rpcHandler(let rpcHandler) = manifest.exports[1] else {
            XCTFail("Expected exports[1] = .rpcHandler, got \(manifest.exports[1])")
            return
        }
        XCTAssertEqual(rpcHandler.id, "app.noctiluca.rpchandler.cjk.switch_im")
        XCTAssertEqual(rpcHandler.type, .rpcHandler)
        XCTAssertEqual(rpcHandler.supportedOperations, ["app.noctiluca.rpc.switch-im"])
    }

    // MARK: - nonke-auth.json (single auth_v1 export, license = string form)

    /// 원본: `NoctilucaPluginSystem/examples/server/nonke-auth.json`
    private static let nonkeAuthJSON = #"""
    {
      "$schema": "https://noctiluca.app/schemas/server/pluginkit/v1-draft/20260516.json",
      "pluginKitVersion": "20260516",
      "id": "com.example.nocplugins.nonke-auth-support",
      "name": {
        "default": "NONKE-v1 Auth Support",
        "ko": "NONKE-v1 인증 지원",
        "ja": "NONKE-v1 認証サポート",
        "zh-Hans": "NONKE-v1 认证支持"
      },
      "authors": [
        "Aya Ueno <g16.h18@lab.example.com>"
      ],
      "description": {
        "default": "Provides an implementation of NONKE-v1 (Nonce-Originated Negotiated Key Exchange Version 1, arVix 8.10.26), a heterogeneous noise-based network authentication method.",
        "ko": "혼합(heterogeneous) 노이즈 기반 네트워크 인증 방식인 NONKE-v1 (Nonce-Originated Negotiated Key Exchange Version 1, arVix 8.10.26)에 대한 구현을 제공합니다.",
        "ja": "ヘテロジニアス（混合）ノイズベースのネットワーク認証方式である NONKE-v1 (Nonce-Originated Negotiated Key Exchange Version 1, arVix 8.10.26) の実装を提供します。",
        "zh-Hans": "提供基于异构（混合）噪声的网络认证方式 NONKE-v1 (Nonce-Originated Negotiated Key Exchange Version 1, arVix 8.10.26) 的实现。"
      },
      "license": "mit",
      "url": "https://oss.example.com/nonke-auth",
      "isolationPolicy": "isolate",
      "exports": [
        {
          "type": "auth_v1",
          "id": "com.example.nocplugin.auth.nonke",
          "name": {
            "default": "NONKE-v1 Auth Plugin",
            "ko": "NONKE-v1 인증 플러그인",
            "ja": "NONKE-v1 認証プラグイン",
            "zh-Hans": "NONKE-v1 认证插件"
          },
          "description": {
            "default": "Provides an implementation of NONKE-v1 (Nonce-Originated Negotiated Key Exchange Version 1, arVix 8.10.26), a heterogeneous noise-based network authentication method.",
            "ko": "혼합(heterogeneous) 노이즈 기반 네트워크 인증 방식인 NONKE-v1 (Nonce-Originated Negotiated Key Exchange Version 1, arVix 8.10.26)에 대한 구현을 제공합니다.",
            "ja": "ヘテロジニアス（混合）ノイズベースのネットワーク認証方式である NONKE-v1 (Nonce-Originated Negotiated Key Exchange Version 1, arVix 8.10.26) の実装を提供します。",
            "zh-Hans": "提供基于异构（混合）噪声的网络认证方式 NONKE-v1 (Nonce-Originated Negotiated Key Exchange Version 1, arVix 8.10.26) 的实现。"
          },
          "authors": [
            "Aya Ueno <g16.h18@lab.example.com>"
          ],
          "license": "mit",
          "version": 1,
          "displayVersion": "1.0.0",
          "supportedMethods": ["com.example.auth.nonke.v1"]
        }
      ]
    }
    """#

    func testDecodeNonkeAuthExample() throws {
        let data = Data(Self.nonkeAuthJSON.utf8)
        let manifest = try JSONDecoder().decode(PluginBundleManifestV1Draft.self, from: data)

        // Bundle-level fields
        XCTAssertEqual(manifest.id, "com.example.nocplugins.nonke-auth-support")
        XCTAssertEqual(manifest.pluginKitVersion, .v1)
        XCTAssertEqual(manifest.isolationPolicy, .isolate)
        XCTAssertEqual(manifest.url, "https://oss.example.com/nonke-auth")

        // Bundle license = string form "mit" → .mit
        if case .mit = manifest.license {
            // OK
        } else {
            XCTFail("Expected bundle license = .mit, got \(manifest.license)")
        }

        // Localized strings — string form 이 아닌 dict form 이라도 default key 노출
        XCTAssertEqual(manifest.name.strings["default"], "NONKE-v1 Auth Support")
        XCTAssertEqual(manifest.name.strings["ja"], "NONKE-v1 認証サポート")

        // Exports: 1개 (auth_v1)
        XCTAssertEqual(manifest.exports.count, 1)

        guard case .auth(let auth) = manifest.exports[0] else {
            XCTFail("Expected exports[0] = .auth, got \(manifest.exports[0])")
            return
        }
        XCTAssertEqual(auth.id, "com.example.nocplugin.auth.nonke")
        XCTAssertEqual(auth.type, .auth)
        XCTAssertEqual(auth.version, 1)
        XCTAssertEqual(auth.displayVersion, "1.0.0")
        XCTAssertEqual(auth.supportedMethods, ["com.example.auth.nonke.v1"])

        // Per-export license 도 string 형태 "mit" 으로 디코딩되는지
        if case .mit = auth.license {
            // OK
        } else {
            XCTFail("Expected auth export license = .mit, got \(auth.license)")
        }
    }
}
