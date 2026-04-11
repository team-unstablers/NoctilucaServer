//
//  SiriusKit.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/20/25.
//

import Foundation

public final class SiriusKitMeta: Sendable {
    private static var frameworkBundle: Bundle {
        return Bundle(for: SiriusKitMeta.self)
    }

    public static var displayVersion: String {
        return frameworkBundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    public static var buildVersion: String {
        return frameworkBundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    public static let currentProtocolVersion: SiriusProtocolVersion = .v1_0
}
