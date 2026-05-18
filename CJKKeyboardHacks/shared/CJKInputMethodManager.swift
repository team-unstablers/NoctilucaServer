//
//  CJKInputMethodManager.swift
//  CJKKeyboardHacks
//
//  Created by Gyuhwan Park on 5/18/26.
//

@preconcurrency import AppKit

import ApplicationServices
import Carbon

/// CJK 입력 지원이 공통적으로 필요로 하는 두 가지 동작 — 입력 소스(IM) 전환과
/// 비활성 앱에서의 TISSelectInputSource 워크어라운드 — 을 한 곳에 모은다.
///
/// 키보드 핵(Win32-style 한/영 토글)과 RPC 핸들러(`app.noctiluca.rpc.switch-im`)
/// 양쪽에서 공유한다. `@MainActor` 격리로 TIS / NSWindow / AX API 호출 경로를
/// 단일 스레드로 직렬화한다.
@MainActor
final class CJKInputMethodManager {
    static let shared = CJKInputMethodManager()

    /// `app.noctiluca.rpc.switch-im` operation 이 받는 언어 토큰.
    /// 클라이언트의 입력 언어(BCP-47 단순화 형태) 를 그대로 받는다.
    enum LanguageToken: String, CaseIterable {
        case english = "en"
        case korean = "ko"
        case japanese = "ja"
        case chineseSimplified = "zh-Hans"
        case chineseTraditional = "zh-Hant"

        /// 매니페스트에 정의된 별칭 / 흔히 쓰이는 약어들을 흡수한다.
        init?(token: String) {
            let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
            switch normalized.lowercased() {
            case "en", "en-us", "abc", "latin", "ascii":
                self = .english
            case "ko", "ko-kr", "kor":
                self = .korean
            case "ja", "ja-jp", "jpn":
                self = .japanese
            case "zh-hans", "zh_cn", "zh-cn", "zh", "chs":
                self = .chineseSimplified
            case "zh-hant", "zh_tw", "zh-tw", "cht":
                self = .chineseTraditional
            default:
                return nil
            }
        }
    }

    /// IM 매칭에 사용할 후보 input source ID 들.
    /// 첫 매칭되는 것을 사용하며, 없으면 sourceLanguages 기반 fallback 으로 넘어간다.
    /// 서드 파티 IM 우선 옵션이 켜진 경우 `thirdParty` 배열을 먼저 시도한다.
    private struct InputSourceCandidates {
        let thirdParty: [String]
        let firstParty: [String]
        /// `kTISPropertyInputSourceLanguages` 기반 fallback 매칭에 사용할 BCP-47 prefix.
        /// 예: "ko" 는 "ko", "ko-KR" 모두 매칭.
        let languagePrefix: String
    }

    private static let candidatesByLanguage: [LanguageToken: InputSourceCandidates] = [
        .korean: InputSourceCandidates(
            thirdParty: [
                "pl.gureum.GureumIM.Korean",
                "pl.gureum.GureumIM",
            ],
            firstParty: [
                "com.apple.inputmethod.Korean.2SetKorean",
                "com.apple.inputmethod.Korean.3SetKorean",
            ],
            languagePrefix: "ko"
        ),
        .japanese: InputSourceCandidates(
            thirdParty: [
                "com.google.inputmethod.Japanese.base",
                "com.google.inputmethod.Japanese.Roman",
                "com.google.inputmethod.Japanese.Hiragana",
            ],
            firstParty: [
                "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese",
                "com.apple.inputmethod.Kotoeri.KanaTyping.Japanese",
            ],
            languagePrefix: "ja"
        ),
        .chineseSimplified: InputSourceCandidates(
            thirdParty: [
                "com.baidu.inputmethod.BaiduIM.Pinyin",
                "com.sogou.inputmethod.sogou.pinyin",
            ],
            firstParty: [
                "com.apple.inputmethod.SCIM.ITABC",
                "com.apple.inputmethod.SCIM.Shuangpin",
            ],
            languagePrefix: "zh-Hans"
        ),
        .chineseTraditional: InputSourceCandidates(
            thirdParty: [],
            firstParty: [
                "com.apple.inputmethod.TCIM.Zhuyin",
                "com.apple.inputmethod.TCIM.Cangjie",
            ],
            languagePrefix: "zh-Hant"
        ),
    ]

    /// TISSelectInputSource() 가 비활성 앱에서 조용히 실패하는 문제를 우회하기 위한
    /// 1x1 투명 윈도우. lazy 로 생성되며 앱 생명주기 동안 재사용된다.
    private var workaroundWindow: NSWindow?

    private init() {}

    // MARK: - Public API

    /// 현재 선택된 IM 의 source ID 를 반환한다.
    var currentInputSourceID: String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return nil
        }
        let cfString = Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue()
        return cfString as String
    }

    /// 현재 IM 이 주어진 언어 카테고리에 속하는지 검사한다.
    func currentInputMatches(_ language: LanguageToken) -> Bool {
        guard let currentID = currentInputSourceID,
              let candidates = Self.candidatesByLanguage[language] else {
            return language == .english && currentIsASCIICapable()
        }
        if candidates.thirdParty.contains(currentID) || candidates.firstParty.contains(currentID) {
            return true
        }
        return currentSourceLanguages().contains { $0.hasPrefix(candidates.languagePrefix) }
    }

    /// 주어진 언어에 해당하는 IM 으로 전환한다.
    /// - Parameters:
    ///   - language: 전환 대상 언어.
    ///   - preferThirdParty: 동일 언어에 대해 서드 파티 IM (구름 / Google / Baidu 등)
    ///     이 설치되어 있다면 우선하여 선택할지 여부.
    /// - Returns: 전환에 성공했는지 여부. 매칭되는 IM 이 없거나 TIS 가 실패하면 `false`.
    @discardableResult
    func switchInputMethod(to language: LanguageToken, preferThirdParty: Bool = false) async -> Bool {
        guard let target = resolveInputSource(for: language, preferThirdParty: preferThirdParty) else {
            return false
        }

        let status = TISSelectInputSource(target)
        guard status == noErr else {
            return false
        }

        // ASCII 가 아닌 IM (= IME 가 활성화되는 경우) 으로 전환했다면,
        // TIS 가 비활성 앱에서 조용히 무시되는 문제를 우회하기 위해
        // 워크어라운드 윈도우를 잠시 활성화한 뒤 원래 앱으로 포커스를 복귀시킨다.
        if language != .english {
            await activateWorkaroundWindowAndRestore()
        }
        return true
    }

    /// 한/영 토글: ASCII (= English) 와 주어진 CJK 언어를 번갈아 전환한다.
    /// 키보드 핵에서 사용한다.
    @discardableResult
    func toggleBetweenEnglishAnd(_ cjkLanguage: LanguageToken, preferThirdParty: Bool = false) async -> Bool {
        if currentInputMatches(cjkLanguage) {
            return await switchInputMethod(to: .english, preferThirdParty: preferThirdParty)
        }
        return await switchInputMethod(to: cjkLanguage, preferThirdParty: preferThirdParty)
    }

    // MARK: - Input source resolution

    private func resolveInputSource(for language: LanguageToken, preferThirdParty: Bool) -> TISInputSource? {
        if language == .english {
            return findASCIICapableInputSource()
        }

        guard let candidates = Self.candidatesByLanguage[language] else {
            return nil
        }

        let ordered: [[String]] = preferThirdParty
            ? [candidates.thirdParty, candidates.firstParty]
            : [candidates.firstParty, candidates.thirdParty]

        for group in ordered {
            for id in group {
                if let source = findInputSource(byID: id) {
                    return source
                }
            }
        }

        // 마지막 폴백 — sourceLanguages 에 prefix 가 매칭되는 첫 enabled IM 을 찾는다.
        return findEnabledInputSource(languagePrefix: candidates.languagePrefix)
    }

    private func findASCIICapableInputSource() -> TISInputSource? {
        guard let list = TISCreateASCIICapableInputSourceList().takeRetainedValue() as? [TISInputSource] else {
            return nil
        }
        return list.first
    }

    private func findInputSource(byID id: String) -> TISInputSource? {
        let filter: [CFString: Any] = [
            kTISPropertyInputSourceID: id as CFString
        ]
        guard let list = TISCreateInputSourceList(filter as CFDictionary, false)?
            .takeRetainedValue() as? [TISInputSource] else {
            return nil
        }
        return list.first
    }

    private func findEnabledInputSource(languagePrefix: String) -> TISInputSource? {
        guard let list = TISCreateInputSourceList(nil, false)?
            .takeRetainedValue() as? [TISInputSource] else {
            return nil
        }
        return list.first { source in
            sourceLanguages(of: source).contains { $0.hasPrefix(languagePrefix) }
        }
    }

    private func sourceLanguages(of source: TISInputSource) -> [String] {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else {
            return []
        }
        let array = Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as? [String]
        return array ?? []
    }

    private func currentSourceLanguages() -> [String] {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return []
        }
        return sourceLanguages(of: source)
    }

    private func currentIsASCIICapable() -> Bool {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let ascii = findASCIICapableInputSource() else {
            return false
        }
        return current == ascii
    }

    // MARK: - Workaround window

    /// 워크어라운드 윈도우를 잠시 활성화한 뒤 원래 앱으로 포커스를 복귀시킨다.
    /// TISSelectInputSource() 가 비활성 앱에서 조용히 실패하는 문제를 우회하기 위함.
    /// 복귀에는 AXUIElement(kAXFrontmostAttribute) 를 사용한다. NSWorkspace 경로보다
    /// 동기적이라 알림 대기/타임아웃 폴백이 불필요하다. (Accessibility 권한 필요)
    private func activateWorkaroundWindowAndRestore() async {
        let previousApp = NSWorkspace.shared.frontmostApplication
        ensureWorkaroundWindow().setIsVisible(true)

        let ourPid = NSRunningApplication.current.processIdentifier
        let axSelf = AXUIElementCreateApplication(ourPid)
        AXUIElementSetAttributeValue(
            axSelf,
            kAXFrontmostAttribute as CFString,
            true as CFTypeRef
        )

        try? await Task.sleep(for: .milliseconds(32))

        if let pid = previousApp?.processIdentifier {
            let axApp = AXUIElementCreateApplication(pid)
            AXUIElementSetAttributeValue(
                axApp,
                kAXFrontmostAttribute as CFString,
                true as CFTypeRef
            )
        }
    }

    private func ensureWorkaroundWindow() -> NSWindow {
        if let existing = workaroundWindow {
            return existing
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.title = "CJKInputMethodManager Workaround Window"
        window.animationBehavior = .none
        window.alphaValue = 0
        window.isOpaque = false
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.setFrame(NSRect(x: -100, y: -100, width: 1, height: 1), display: false)
        workaroundWindow = window
        return window
    }
}
