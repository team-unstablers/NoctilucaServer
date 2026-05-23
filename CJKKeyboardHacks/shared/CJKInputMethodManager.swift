//
//  CJKInputMethodManager.swift
//  CJKKeyboardHacks
//
//  Created by Gyuhwan Park on 5/18/26.
//

@preconcurrency import AppKit

import ApplicationServices
import Carbon
import Foundation

/// CJK 입력 지원이 공통적으로 필요로 하는 두 가지 동작 — 입력 소스(IM) 전환과
/// 비활성 앱에서의 TISSelectInputSource 워크어라운드 — 을 한 곳에 모은다.
///
/// 키보드 핵(Win32-style 한/영 토글)과 RPC 핸들러(`app.noctiluca.rpc.switch-im`)
/// 양쪽에서 공유한다. `@MainActor` 격리로 TIS / NSWindow / AX API 호출 경로를
/// 단일 스레드로 직렬화한다.
///
/// IM ↔ 언어 매칭은 입력 소스의 `kTISPropertyInputSourceLanguages` (BCP-47 태그
/// 배열) 만으로 판정한다. 서드 파티 / 퍼스트 파티 구분은 입력 소스 ID 가
/// `com.apple.` 로 시작하는지로 런타임에 판단한다 — 사전적으로 후보 IM 의 ID 를
/// 알 필요가 없다.
@MainActor
final class CJKInputMethodManager {
    static let shared = CJKInputMethodManager()

    /// 퍼스트 파티(Apple 기본 제공) 입력 소스의 ID 접두.
    private static let firstPartyIDPrefix = "com.apple."

    /// TISSelectInputSource() 가 비활성 앱에서 조용히 실패하는 문제를 우회하기 위한
    /// 1x1 투명 윈도우. lazy 로 생성되며 앱 생명주기 동안 재사용된다.
    private var workaroundWindow: NSWindow?

    private init() {}

    // MARK: - Public API

    /// 현재 선택된 IM 의 source ID 를 반환한다.
    var currentInputSourceID: String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        return Self.inputSourceID(of: source)
    }

    /// 현재 IM 이 주어진 언어 명세에 매칭되는지 검사한다.
    /// 요청 언어가 영어(`.english`) 인 경우 ASCIICapable 여부로 판단한다.
    func currentInputSourceMatches(_ language: Locale.Language) -> Bool {
        if Self.isAsciiRequest(language) {
            return currentIsASCIICapable()
        }
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return false
        }
        return Self.sourceLanguages(of: source).contains { tag in
            Self.languageTag(tag, matches: language)
        }
    }

    /// 주어진 언어 명세에 해당하는 IM 으로 전환한다.
    /// - Parameters:
    ///   - language: 전환 대상 언어 (`Locale.Language`).
    ///   - preferThirdParty: 퍼스트 파티(`com.apple.*`)가 아닌 서드 파티 IM 이
    ///     같은 언어로 설치되어 있다면 우선하여 선택할지 여부.
    /// - Returns: 전환에 성공했는지 여부. 매칭되는 IM 이 없거나 TIS 가 실패하면 `false`.
    @discardableResult
    func switchInputMethod(
        matching language: Locale.Language,
        preferThirdParty: Bool = false
    ) async -> Bool {
        guard let target = resolveInputSource(
            for: language,
            preferThirdParty: preferThirdParty
        ) else {
            return false
        }

        let status = TISSelectInputSource(target)
        guard status == noErr else {
            return false
        }

        // ASCIICapable 이 아닌 IM (= IME 가 활성화되는 경우) 으로 전환했다면,
        // TIS 가 비활성 앱에서 조용히 무시되는 문제를 우회하기 위해
        // 워크어라운드 윈도우를 잠시 활성화한 뒤 원래 앱으로 포커스를 복귀시킨다.
        if !Self.isAsciiCapable(target) {
            await activateWorkaroundWindowAndRestore()
        }
        return true
    }

    /// ASCII (= US/ABC) 와 지정된 CJK 언어 사이를 토글한다. 키보드 핵에서 사용한다.
    @discardableResult
    func toggleBetweenAsciiAnd(
        _ language: Locale.Language,
        preferThirdParty: Bool = false
    ) async -> Bool {
        if currentInputSourceMatches(language) {
            return await switchInputMethod(
                matching: Locale.Language(languageCode: .english),
                preferThirdParty: preferThirdParty
            )
        }
        return await switchInputMethod(
            matching: language,
            preferThirdParty: preferThirdParty
        )
    }

    // MARK: - Input source resolution

    private func resolveInputSource(
        for language: Locale.Language,
        preferThirdParty: Bool
    ) -> TISInputSource? {
        if Self.isAsciiRequest(language) {
            return findASCIICapableInputSource()
        }

        guard let list = TISCreateInputSourceList(nil, false)?
            .takeRetainedValue() as? [TISInputSource] else {
            return nil
        }

        var firstParty: [TISInputSource] = []
        var thirdParty: [TISInputSource] = []

        for source in list {
            let matches = Self.sourceLanguages(of: source).contains { tag in
                Self.languageTag(tag, matches: language)
            }
            guard matches else { continue }

            let id = Self.inputSourceID(of: source) ?? ""
            if id.hasPrefix(Self.firstPartyIDPrefix) {
                firstParty.append(source)
            } else {
                thirdParty.append(source)
            }
        }

        let ordered: [[TISInputSource]] = preferThirdParty
            ? [thirdParty, firstParty]
            : [firstParty, thirdParty]

        return ordered.first { !$0.isEmpty }?.first
    }

    private func findASCIICapableInputSource() -> TISInputSource? {
        guard let list = TISCreateASCIICapableInputSourceList().takeRetainedValue() as? [TISInputSource] else {
            return nil
        }
        return list.first
    }

    private func currentIsASCIICapable() -> Bool {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return false
        }
        return Self.isAsciiCapable(current)
    }

    // MARK: - TIS property helpers

    private static func inputSourceID(of source: TISInputSource) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private static func sourceLanguages(of source: TISInputSource) -> [String] {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else {
            return []
        }
        let array = Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as? [String]
        return array ?? []
    }

    /// 주어진 source 가 ASCIICapable 입력 소스 리스트에 포함되는지.
    /// (= IME 가 활성화되지 않은, 직접 라틴 문자를 타이핑하는 레이아웃.)
    private static func isAsciiCapable(_ source: TISInputSource) -> Bool {
        guard let list = TISCreateASCIICapableInputSourceList().takeRetainedValue()
            as? [TISInputSource] else {
            return false
        }
        return list.contains(source)
    }

    private static func isAsciiRequest(_ language: Locale.Language) -> Bool {
        language.languageCode == .english
    }

    /// 입력 소스의 언어 태그 (`kTISPropertyInputSourceLanguages` 의 한 항목) 가
    /// 요청 언어 명세와 매칭되는지.
    ///
    /// 규칙:
    /// - 언어 코드는 반드시 일치해야 한다.
    /// - 요청에 script 가 명시되어 있으면 (`zh-Hans`, `zh-Hant` 등) 입력 소스의
    ///   script 도 같아야 한다. (단, 요청에 script 가 없으면 입력 소스의 script
    ///   는 무엇이든 허용 — `zh` 요청은 `zh-Hans` / `zh-Hant` 모두 매칭.)
    /// - region 은 무시한다 (`en-US` 와 `en-GB` 는 IM 선택 관점에서 동치).
    private static func languageTag(_ tag: String, matches request: Locale.Language) -> Bool {
        let source = Locale.Language(identifier: tag)
        guard source.languageCode == request.languageCode else {
            return false
        }
        if let requestScript = request.script {
            return source.script == requestScript
        }
        return true
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
