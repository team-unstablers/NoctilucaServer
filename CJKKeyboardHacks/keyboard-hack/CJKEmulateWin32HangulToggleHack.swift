//
//  CJKEmulateWin32HangulToggleHack.swift
//  SamplePluginBundle
//
//  Created by Gyuhwan Park on 2/14/26.
//

@preconcurrency import AppKit

import ApplicationServices
import Carbon
import NoctilucaPluginKit

import Gesu

final class CJKEmulateWin32HangulToggleHack: KeyboardHackPluginV1 {
    static let id: String =
        "app.noctiluca.hidio.hack.cjk.emulate_win32_hangul_toggle"

    static let desiredKeyEvents: Set<NoctilucaPluginKit.LinuxKeycode> = [
        .KEY_RIGHTMETA,
        .KEY_RIGHTALT,
        .KEY_HANGEUL,
    ]

    nonisolated(unsafe) private var workaroundWindow: NSWindow!

    required init() {
        DispatchQueue.main.sync {
            self.workaroundWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            self.workaroundWindow.title = "CJKEmulateWin32HangulToggleHack Workaround Window"
            self.workaroundWindow.animationBehavior = .none
            self.workaroundWindow.alphaValue = 0
            self.workaroundWindow.isOpaque = false
            self.workaroundWindow.level = .floating
            self.workaroundWindow.isReleasedWhenClosed = false
            self.workaroundWindow.setFrame(NSRect(x: -100, y: -100, width: 1, height: 1), display: false)
        }
    }

    /// 워크어라운드 윈도우를 잠시 활성화한 뒤 원래 앱으로 포커스를 복귀시킨다.
    /// TISSelectInputSource()가 비활성 앱에서 조용히 실패하는 문제를 우회하기 위한 목적.
    /// 복귀에는 AXUIElement(kAXFrontmostAttribute)를 사용한다. NSWorkspace 경로보다
    /// 동기적이라 알림 대기/타임아웃 폴백이 불필요하다. (Accessibility 권한 필요)
    private func activateWorkaroundWindowAndRestore() async {
        await withCheckedContinuation { cont in
            let previousApp = NSWorkspace.shared.frontmostApplication

            DispatchQueue.main.async {
                self.workaroundWindow.setIsVisible(true)
                self.workaroundWindow.makeKeyAndOrderFront(nil)

                let ourPid = NSRunningApplication.current.processIdentifier
                let axSelf = AXUIElementCreateApplication(ourPid)
                AXUIElementSetAttributeValue(
                    axSelf,
                    kAXFrontmostAttribute as CFString,
                    true as CFTypeRef
                )

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) {
                    self.workaroundWindow.orderOut(nil)
                    self.workaroundWindow.setIsVisible(false)

                    if let pid = previousApp?.processIdentifier {
                        let axApp = AXUIElementCreateApplication(pid)
                        AXUIElementSetAttributeValue(
                            axApp,
                            kAXFrontmostAttribute as CFString,
                            true as CFTypeRef
                        )
                    }

                    cont.resume()
                }
            }
        }
    }

    private func findASCIICapableInputSource() -> TISInputSource? {
        let list = TISCreateASCIICapableInputSourceList().takeRetainedValue() as? [TISInputSource]
        return list?.first
    }

    private func findKorean2BulsikInputSource() -> TISInputSource? {
        let list = TISCreateInputSourceList([
            kTISPropertyInputModeID: "com.apple.inputmethod.Korean.2SetKorean" as CFString
        ] as CFDictionary, false)
        return (list?.takeRetainedValue() as? [TISInputSource])?.first
    }

    func onKeyDown(_ keyCode: NoctilucaPluginKit.LinuxKeycode) async -> NoctilucaPluginKit.KeyboardHackResult {
        if keyCode == .KEY_RIGHTALT || keyCode == .KEY_RIGHTMETA || keyCode == .KEY_HANGEUL {
            await Task { @MainActor in
                let current = TISCopyCurrentKeyboardInputSource()?.takeUnretainedValue()
                guard let abc = findASCIICapableInputSource(),
                      let ko2Bulsik = findKorean2BulsikInputSource() else {
                    return
                }

                if current == ko2Bulsik {
                    TISSelectInputSource(abc)
                } else {
                    TISSelectInputSource(ko2Bulsik)
                    await activateWorkaroundWindowAndRestore()
                }
            }

            try? await Task.sleep(for: .milliseconds(250))
            return .stop
        }

        return .passthrough
    }

    func onKeyUp(_ keyCode: NoctilucaPluginKit.LinuxKeycode) async -> NoctilucaPluginKit.KeyboardHackResult {
        if keyCode == .KEY_RIGHTALT || keyCode == .KEY_RIGHTMETA || keyCode == .KEY_HANGEUL {
            return .stop
        }
        return .passthrough
    }
}
