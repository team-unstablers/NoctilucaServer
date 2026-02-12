//
//  ModifierKeyRebindingConfigurator.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/12/26.
//

import Foundation

import SiriusKitClient

enum ModifierKeyRebindingConfigurator {
    private struct SourceGroup {
        let left: LinuxKeycode
        let right: LinuxKeycode?
    }

    private struct TargetGroup {
        let left: LinuxKeycode?
        let right: LinuxKeycode?
    }

    private static let sourceGroups: [AppSettings.ModifierKeyOverride: SourceGroup] = [
        .capsLock: SourceGroup(left: .KEY_CAPSLOCK, right: nil),
        .control:  SourceGroup(left: .KEY_LEFTCTRL, right: .KEY_RIGHTCTRL),
        .option:   SourceGroup(left: .KEY_LEFTALT, right: .KEY_RIGHTALT),
        .command:  SourceGroup(left: .KEY_LEFTMETA, right: .KEY_RIGHTMETA),
    ]

    private static func targetGroup(for override: AppSettings.ModifierKeyOverride) -> TargetGroup {
        switch override {
        case .capsLock: return TargetGroup(left: .KEY_CAPSLOCK, right: .KEY_CAPSLOCK)
        case .control:  return TargetGroup(left: .KEY_LEFTCTRL, right: .KEY_RIGHTCTRL)
        case .option:   return TargetGroup(left: .KEY_LEFTALT, right: .KEY_RIGHTALT)
        case .command:  return TargetGroup(left: .KEY_LEFTMETA, right: .KEY_RIGHTMETA)
        case .escape:   return TargetGroup(left: .KEY_ESC, right: .KEY_ESC)
        case .disabled: return TargetGroup(left: nil, right: nil)
        }
    }

    static func apply(_ overrides: AppSettings.ModifierKeyOverrides, to rebinder: KeyEventRebinder) {
        rebinder.unregisterAll()

        let entries: [(AppSettings.ModifierKeyOverride, AppSettings.ModifierKeyOverride)] = [
            (.capsLock, overrides.capsLock),
            (.control,  overrides.control),
            (.option,   overrides.option),
            (.command,  overrides.command),
        ]

        for (sourceKey, targetKey) in entries {
            // identity mapping은 등록하지 않음
            if sourceKey == targetKey {
                continue
            }

            guard let source = sourceGroups[sourceKey] else { continue }
            let target = targetGroup(for: targetKey)

            // 좌측 키 등록
            rebinder.register(from: source.left, to: target.left)

            // 우측 키 등록 (존재하는 경우)
            if let sourceRight = source.right {
                rebinder.register(from: sourceRight, to: target.right)
            }
        }
    }
}
