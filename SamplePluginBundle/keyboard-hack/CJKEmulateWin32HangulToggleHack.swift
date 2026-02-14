//
//  CJKEmulateWin32HangulToggleHack.swift
//  SamplePluginBundle
//
//  Created by Gyuhwan Park on 2/14/26.
//

import Carbon
import NoctilucaPluginKit

class CJKEmulateWin32HangulToggleHack: KeyboardHackPluginV1 {
    static var id: String =
        "app.noctiluca.hidio.hack.cjk.emulate_win32_hangul_toggle"

    
    static var name: String =
        String(
            localized: "app.noctiluca.hidio.hack.cjk.emulate_win32_hangul_toggle.name",
            defaultValue: ""
        )
    
    static var description: String =
        String(
            localized: "app.noctiluca.hidio.hack.cjk.emulate_win32_hangul_toggle.description",
            defaultValue: ""
        )
    
    static var authors: [String] = [
        "Gyuhwan Park <unstabler@unstabler.pl>"
    ]
    
    static var license: SoftwareLicense = .mit
    
    static var version: UInt32 = 1
    
    static var displayVersion: String = "1.0.0"
    
    static var desiredKeyEvents: Set<NoctilucaPluginKit.LinuxKeycode> = [
        .KEY_RIGHTMETA,
        .KEY_RIGHTALT
    ]
    
    required init() {
    }
    
    func onKeyDown(_ keyCode: NoctilucaPluginKit.LinuxKeycode) async -> NoctilucaPluginKit.KeyboardHackResult {
        if keyCode == .KEY_RIGHTALT || keyCode == .KEY_RIGHTMETA {
            // ensure main thread
            await Task { @MainActor in
                print("right alt!")
                let current = TISCopyCurrentKeyboardInputSource()
                guard let asciiCapableInputList = TISCreateASCIICapableInputSourceList().takeRetainedValue() as? [TISInputSource],
                      let abc = asciiCapableInputList.first else {
                    return
                }
                
                let x = TISCreateInputSourceList([
                    kTISPropertyInputModeID: "com.apple.inputmethod.Korean.2SetKorean" as CFString
                ] as CFDictionary, false)
                guard let methods = x?.takeRetainedValue() as? [TISInputSource],
                      let ko2Bulsik = methods.first else {
                    return
                }
                
                if current?.takeUnretainedValue() == ko2Bulsik {
                    TISSelectInputSource(abc)
                } else {
                    // HACK: TISSelectInputSource()는 프로그래밍적 호출 시
                    // 조용히 실패하는 경우가 있음. 여러 런루프 사이클에 걸쳐
                    // 재시도하면 성공 확률이 올라감.
                    self.selectInputSourceWithRetry(ko2Bulsik)
                }
            }
            return .stop
        }
        
        return .passthrough
    }
    
    private func selectInputSourceWithRetry(_ source: TISInputSource, attempts: Int = 15) {
        TISSelectInputSource(source)
        if attempts > 1 {
            DispatchQueue.main.async {
                self.selectInputSourceWithRetry(source, attempts: attempts - 1)
            }
        }
    }

    func onKeyUp(_ keyCode: NoctilucaPluginKit.LinuxKeycode) async -> NoctilucaPluginKit.KeyboardHackResult {
        if keyCode == .KEY_RIGHTALT || keyCode == .KEY_RIGHTMETA {
            return .stop
        }
        return .passthrough
    }
    
    
}
