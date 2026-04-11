//
//  SamplePluginBundle.swift
//  SamplePluginBundle
//
//  Created by Gyuhwan Park on 12/5/25.
//

import Foundation

@preconcurrency import NoctilucaPluginKit

@MainActor
public final class CJKKeyboardHacksBundle: @preconcurrency NoctilucaPluginBundle {
    public static let id = "app.noctiluca.server.bundles.CJKKeyboardHacks"
    public static let pluginKitVersion: NoctilucaPluginKitVersion = .v1
    
    public static let name = String(localized: "plugin.name", defaultValue: "CJK Keyboard Hack Bundle")
    public static let description = String(localized: "plugin.description", defaultValue: "CJK 입력이 필요한 환경에서 사용성 개선을 위한 키보드 핵(Hack)을 클라이언트에게 제공합니다.")
    
    public static let authors: [String] = [
        "Gyuhwan Park <unstabler@unstabler.pl>"
    ]
    
    public static let license: NoctilucaPluginKit.SoftwareLicense = .custom(
        name: "Noctiluca Server EULA",
        url: URL(string: "https://eula.noctiluca.app")!,
        isOpenSource: false
    )
    public static let version: UInt32 = 1
    public static let displayVersion: String = "1.0.0"
    
    public static func initialize() async throws {
    }
    
    public static func deinitialize() throws {
    }
    
    public static let exports: [NoctilucaPluginKit.NoctilucaPluginExport] = [
        .keyboardHack(CJKEmulateWin32HangulToggleHack())
    ]
}
