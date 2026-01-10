//
//  DisplayColorProfile.swift
//  SiriusKit
//
//  Created by Codex on 1/10/26.
//

import Foundation

public struct DisplayColorProfile: RawRepresentable, Hashable, Equatable {
    public let rawValue: String
    
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
    
    public static let sRGB = Self(rawValue: "sRGB")
    public static let adobeRGB = Self(rawValue: "AdobeRGB")
    public static let dciP3 = Self(rawValue: "DCI-P3")
}
