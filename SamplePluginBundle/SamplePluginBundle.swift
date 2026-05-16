//
//  SamplePluginBundle.swift
//  SamplePluginBundle
//
//  Created by Gyuhwan Park on 12/5/25.
//

import Foundation

import NoctilucaPluginKit

public final class SamplePluginBundle: NoctilucaPluginBundle {
    public static func initialize() async throws {
        print("Hello, World!")
    }

    public static func deinitialize() throws {
        print("Goodbye, World!")
    }

    public static var exports: [NoctilucaPluginKit.NoctilucaPluginExport] = [
    ]
}
