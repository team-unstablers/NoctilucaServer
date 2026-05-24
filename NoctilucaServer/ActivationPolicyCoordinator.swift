//
//  ActivationPolicyCoordinator.swift
//  NoctilucaServer
//

import AppKit

/// `LSUIElement=true` 로 시작하는 메뉴바 전용 앱에서, 사용자가 보조 윈도우
/// (설정 / 라이선스 / 온보딩 / About 등) 를 다루는 동안에만 일시적으로
/// `.regular` 정책으로 승격시키고, 추적 중인 윈도우가 모두 close 되면 다시
/// `.accessory` 로 되돌린다.
///
/// 이렇게 함으로써 사용자는 다른 앱으로 포커스를 넘긴 뒤에도 ⌘-Tab 이나
/// Dock 아이콘으로 NoctilucaServer 의 보조 윈도우로 돌아올 수 있다.
/// 윈도우가 minimize 된 것은 "아직 살아 있음" 으로 간주하며,
/// `willClose` 가 발생할 때만 해당 윈도우를 추적 대상에서 해제한다.
@MainActor
final class ActivationPolicyCoordinator {
    private var observers: [ObjectIdentifier: NSObjectProtocol] = [:]

    /// 추적 대상 윈도우를 등록한다. `willCloseNotification` 옵저버를 부착하고,
    /// 윈도우가 close 되면 자동으로 추적 대상에서 해제된다. 동일 윈도우를
    /// 중복 등록해도 무해하다 (옵저버는 1 개만 유지).
    func track(_ window: NSWindow) {
        let key = ObjectIdentifier(window)
        if observers[key] != nil { return }

        let token = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleWindowClosed(key: key)
            }
        }
        observers[key] = token
        updateActivationPolicy()
    }

    private func handleWindowClosed(key: ObjectIdentifier) {
        guard let token = observers.removeValue(forKey: key) else { return }
        NotificationCenter.default.removeObserver(token)
        updateActivationPolicy()
    }

    private func updateActivationPolicy() {
        let target: NSApplication.ActivationPolicy = observers.isEmpty ? .accessory : .regular
        guard NSApp.activationPolicy() != target else { return }
        NSApp.setActivationPolicy(target)
    }
}
