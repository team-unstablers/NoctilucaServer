//
//  SamplePluginBundle.swift
//  SamplePluginBundle
//
//  Created by Gyuhwan Park on 12/5/25.
//

import Foundation

import NoctilucaPluginKit

public final class CJKKeyboardHacksBundle: NoctilucaPluginBundle {
    public static let id = "app.noctiluca.server.bundles.CJKKeyboardHacks"
    public static let pluginKitVersion: NoctilucaPluginKitVersion = .v1

    public static func initialize() async throws {
    }

    public static func deinitialize() throws {
    }

    public static let exports: [NoctilucaPluginKit.NoctilucaPluginExport] = [
        .keyboardHack(CJKEmulateWin32HangulToggleHack())
    ]
}
