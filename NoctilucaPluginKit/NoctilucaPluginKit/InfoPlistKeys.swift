//
//  InfoPlistKeys.swift
//  NoctilucaPluginKit
//
//  Created by Gyuhwan Park on 12/7/25.
//

import Foundation

public struct NoctilucaPluginInfoPlistKey: RawRepresentable, Hashable, Sendable, Codable {
    public typealias RawValue = String
    
    public let rawValue: String
    
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self.init(rawValue: rawValue)
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
    
    /// Plugin Identifier
    public static let id = Self(rawValue: "NOCPluginID")
    
    /// Plugin Display Name
    public static let displayName = Self(rawValue: "NOCPluginDisplayName")

    /// Plugin Type
    /// @expects String    e.g., "auth", "featureProvider", etc.
    public static let type = Self(rawValue: "NOCPluginType")
    
    /// Plugin Description
    public static let description = Self(rawValue: "NOCPluginDescription")
}


public struct NoctilucaPluginBundleInfoPlistKey: RawRepresentable, Hashable, Sendable, Codable {
    public typealias RawValue = String
    
    public let rawValue: String
    
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self.init(rawValue: rawValue)
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
    
    // - MARK: Core Foundation Info.plist Keys
    
    /// Bundle ID
    public static let id = Self(rawValue: "CFBundleIdentifier")
    
    /// Bundle Display Name
    public static let displayName = Self(rawValue: "CFBundleDisplayName")
    
    /// Bundle Version
    public static let version = Self(rawValue: "CFBundleVersion")
    
    /// Bundle Display Versioon
    public static let displayVersion = Self(rawValue: "CFBundleShortVersionString")
    
    
    // - MARK: Noctiluca Extension Info.plist Keys
    
    /// NoctilucaPluginKit Version
    /// 이 플러그인 번들이 대상으로 하는 NoctilucaPluginKit의 버전을 명시합니다.
    /// @expects UInt32    see NoctilucaPluginKitVersion
    public static let pluginKitVersion = Self(rawValue: "NOCPluginKitVersion")

    /// Plugin Bundle Description
    /// @expects String
    public static let bundleDescription = Self(rawValue: "NOCBundleDescription")
    
    /// Plugin Bundle Authors
    /// @expects Array<String>
    public static let bundleAuthors = Self(rawValue: "NOCBundleAuthors")
    
    /// Plugin Bundle License
    /// @expects String    SPDX License Identifier (or "CUSTOM:{CUSTOM_LICENSE_NAME}" for custom license, "PROPRIETARY:{LICENSE_NAME}" for proprietary license)
    public static let bundleLicense = Self(rawValue: "NOCBundleLicense")
    
    /// Plugin Bundle License URL
    /// @expects String    URL to the license text (only required if pluginLicense is "Custom" / "Proprietary")
    public static let bundleLicenseURL = Self(rawValue: "NOCBundleLicenseURL")
    
    /// Plugin Bundle Exports
    /// @expects Array<Dictionary<NoctilucaPluginInfoPlistKey, Any>>   Array of exported plugin class names
    public static let bundleExports = Self(rawValue: "NOCBundleExports")
}
