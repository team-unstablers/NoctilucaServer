//
//  CJKInputMethodManager.swift
//  CJKKeyboardHacks
//
//  Created by Gyuhwan Park on 5/18/26.
//

@preconcurrency import AppKit

import os

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
final class CJKInputMethodManager: NSObject {
    static let shared = CJKInputMethodManager()

    /// 퍼스트 파티(Apple 기본 제공) 입력 소스의 ID 접두.
    private static let firstPartyIDPrefix = "com.apple."

    /// TISSelectInputSource() 가 비활성 앱에서 조용히 실패하는 문제를 우회하기 위한
    /// 1x1 투명 윈도우. lazy 로 생성되며 앱 생명주기 동안 재사용된다.
    private var workaroundWindow: NSWindow?

    override private init() {
        super.init()
    }

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
    var axSelf: AXUIElement?
    
    var becomeKeyWindowContinuation: CheckedContinuation<Void, Never>?

    /// 워크어라운드 윈도우를 잠시 활성화한 뒤 원래 앱으로 포커스를 복귀시킨다.
    /// TISSelectInputSource() 가 비활성 앱에서 조용히 실패하는 문제를 우회하기 위함.
    /// 활성화 / 복귀 모두 AXUIElement(kAXFrontmostAttribute) 를 사용하며, 폴링 대신
    /// windowDidBecomeKey 와 kAXApplicationActivatedNotification 알림을 기다린다.
    /// 알림이 어떤 이유로 누락되어도 hang 되지 않도록 복귀 단계에 200ms 폴백 타임아웃을 둔다.
    /// (Accessibility 권한 필요.)
    private func activateWorkaroundWindowAndRestore() async {
        let previousApp = NSWorkspace.shared.frontmostApplication

        func activateWorkaroundWindow() async {
            await withCheckedContinuation { continuation in
                ensureWorkaroundWindow().setIsVisible(true)
                let axSelf = ensureAXHandle()

                becomeKeyWindowContinuation = continuation

                AXUIElementSetAttributeValue(
                    axSelf,
                    kAXFrontmostAttribute as CFString,
                    true as CFTypeRef
                )
            }
        }

        func restoreWindowFocus() async {
            guard let pid = previousApp?.processIdentifier else { return }

            let observation = RestoreFocusObservation(pid: pid)

            let timeoutTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                observation.resumeOnce()
            }

            await observation.waitForActivation()
            timeoutTask.cancel()
        }

        await activateWorkaroundWindow()
        await restoreWindowFocus()
    }

    /// 외부 앱이 activate 될 때까지 한 번만 알림을 기다리고 자기 자신을 정리하는 헬퍼.
    /// `kAXApplicationActivatedNotification` 알림과 외부 타임아웃 호출 중 먼저 도착한
    /// 쪽이 continuation 을 resume 하고 옵저버 / RunLoop source / refCon 을 모두 해제한다.
    @MainActor
    private final class RestoreFocusObservation {
        private let pid: pid_t
        private let axApp: AXUIElement
        private var observer: AXObserver?
        private var continuation: CheckedContinuation<Void, Never>?
        private var retainedRefCon: UnsafeMutableRawPointer?

        init(pid: pid_t) {
            self.pid = pid
            self.axApp = AXUIElementCreateApplication(pid)
        }

        func waitForActivation() async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                self.continuation = continuation
                start()
            }
        }

        private func start() {
            var observer: AXObserver?
            let createResult = AXObserverCreate(pid, { _, _, _, refCon in
                guard let refCon else { return }
                MainActor.assumeIsolated {
                    let observation = Unmanaged<RestoreFocusObservation>
                        .fromOpaque(refCon)
                        .takeUnretainedValue()
                    observation.resumeOnce()
                }
            }, &observer)

            guard createResult == .success, let observer else {
                resumeOnce()
                return
            }
            self.observer = observer

            let refCon = Unmanaged.passRetained(self).toOpaque()
            retainedRefCon = refCon

            let addResult = AXObserverAddNotification(
                observer,
                axApp,
                kAXApplicationActivatedNotification as CFString,
                refCon
            )
            guard addResult == .success || addResult == .notificationAlreadyRegistered else {
                resumeOnce()
                return
            }

            CFRunLoopAddSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )

            AXUIElementSetAttributeValue(
                axApp,
                kAXFrontmostAttribute as CFString,
                true as CFTypeRef
            )
        }

        /// 알림 경로와 타임아웃 경로 모두에서 호출된다. 먼저 도착한 쪽이 정리·resume 을 수행하고
        /// 두 번째 호출은 no-op.
        func resumeOnce() {
            guard let continuation else { return }
            self.continuation = nil

            if let observer {
                AXObserverRemoveNotification(
                    observer,
                    axApp,
                    kAXApplicationActivatedNotification as CFString
                )
                CFRunLoopRemoveSource(
                    CFRunLoopGetMain(),
                    AXObserverGetRunLoopSource(observer),
                    .defaultMode
                )
                self.observer = nil
            }

            if let retainedRefCon {
                self.retainedRefCon = nil
                Unmanaged<RestoreFocusObservation>.fromOpaque(retainedRefCon).release()
            }

            continuation.resume()
        }
    }
    
    private func ensureAXHandle() -> AXUIElement {
        if let axSelf = axSelf {
            return axSelf
        }
        
        let ourPid = NSRunningApplication.current.processIdentifier
        let axSelf = AXUIElementCreateApplication(ourPid)
        
        self.axSelf = axSelf
        
        return axSelf
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
        
        window.delegate = self
        
        workaroundWindow = window
        return window
    }
}

extension CJKInputMethodManager: NSWindowDelegate {
    func windowDidBecomeKey(_ notification: Notification) {
        becomeKeyWindowContinuation?.resume()
        becomeKeyWindowContinuation = nil
    }
}
