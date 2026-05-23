//
//  CJKEmulateWin32HangulToggleHack.swift
//  CJKKeyboardHacks
//
//  Created by Gyuhwan Park on 2/14/26.
//

import Foundation
import NoctilucaPluginKit

/// Win32 스타일의 한/영 토글 키 (한/영, Right Alt, Right Meta) 를 받아 한국어 IM 과
/// ASCII IM 사이를 토글한다. 실제 IM 전환과 워크어라운드 윈도우 관리는
/// `CJKInputMethodManager` 에 위임한다.
final class CJKEmulateWin32HangulToggleHack: KeyboardHackPluginV1 {
    static let id: String =
        "app.noctiluca.hidio.hack.cjk.emulate_win32_hangul_toggle"

    static let desiredKeyEvents: Set<NoctilucaPluginKit.LinuxKeycode> = [
        .KEY_RIGHTMETA,
        .KEY_RIGHTALT,
        .KEY_HANGEUL,
    ]

    required init() {}

    func onKeyDown(_ keyCode: NoctilucaPluginKit.LinuxKeycode) async -> NoctilucaPluginKit.KeyboardHackResult {
        guard Self.desiredKeyEvents.contains(keyCode) else {
            return .passthrough
        }

        await CJKInputMethodManager.shared.toggleBetweenAsciiAnd(
            Locale.Language(languageCode: .korean)
        )

        // IM 전환 직후 키 입력이 다음 파이프라인으로 누설되지 않도록 짧게 대기.
        try? await Task.sleep(for: .milliseconds(128))
        return .stop
    }

    func onKeyUp(_ keyCode: NoctilucaPluginKit.LinuxKeycode) async -> NoctilucaPluginKit.KeyboardHackResult {
        if Self.desiredKeyEvents.contains(keyCode) {
            return .stop
        }
        return .passthrough
    }
}
