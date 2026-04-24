//
//  CJKEmulateWin32HangulToggleHack.swift
//  SamplePluginBundle
//
//  Created by Gyuhwan Park on 2/14/26.
//

@preconcurrency import AppKit

import Carbon
import NoctilucaPluginKit

import Gesu

final class CJKEmulateWin32HangulToggleHack: KeyboardHackPluginV1 {
    static let id: String =
        "app.noctiluca.hidio.hack.cjk.emulate_win32_hangul_toggle"

    static let name: String =
        String(
            localized: "app.noctiluca.hidio.hack.cjk.emulate_win32_hangul_toggle.name",
            defaultValue: ""
        )

    static let description: String =
        String(
            localized: "app.noctiluca.hidio.hack.cjk.emulate_win32_hangul_toggle.description",
            defaultValue: ""
        )

    static let authors: [String] = [
        "Gyuhwan Park <unstabler@unstabler.pl>"
    ]

    static let license: SoftwareLicense = .mit

    static let version: UInt32 = 1

    static let displayVersion: String = "1.0.0"

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
    private func activateWorkaroundWindowAndRestore() async {
        await withCheckedContinuation { cont in
            let previousApp = NSWorkspace.shared.frontmostApplication

            DispatchQueue.main.async {
                self.workaroundWindow.setIsVisible(true)
                self.workaroundWindow.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.075) {
                    self.workaroundWindow.orderOut(nil)
                    self.workaroundWindow.setIsVisible(false)

                    guard let previousApp else {
                        cont.resume()
                        return
                    }

                    var resumed = false
                    var observer: NSObjectProtocol?

                    observer = NSWorkspace.shared.notificationCenter.addObserver(
                        forName: NSWorkspace.didActivateApplicationNotification,
                        object: nil,
                        queue: .main
                    ) { notification in
                        guard !resumed,
                              let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                              app == previousApp else {
                            return
                        }
                        resumed = true
                        if let obs = observer {
                            NSWorkspace.shared.notificationCenter.removeObserver(obs)
                        }
                        cont.resume()
                    }

                    // 타임아웃 폴백 (1초 이내에 복귀하지 않으면 강제 resume)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        guard !resumed else { return }
                        resumed = true
                        if let obs = observer {
                            NSWorkspace.shared.notificationCenter.removeObserver(obs)
                        }
                        cont.resume()
                    }

                    previousApp.activate(options: [.activateIgnoringOtherApps])
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
