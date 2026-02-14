//
//  NoctilucaMeta.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 11/24/25.
//

import Foundation

#if os(iOS)
import UIKit
#endif

struct NoctilucaMeta {
    static var productName: String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Noctiluca Navigator"
    }
    
    static var bundleIdentifier: String {
        return Bundle.main.bundleIdentifier ?? "app.noctiluca.client"
    }
    
    static var version: String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }
    
    static var buildVersion: String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    static var license: SoftwareLicense = .proprietary(name: "Noctiluca Client EULA",
                                                       url: URL(string: "https://unstabler.pl")!)
    
    
#if os(iOS)
    static func applicationIcon() -> UIImage? {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String] else {
            return nil
        }
        
        // Use the last file name in the array, which is often a good size to use
        if let lastIconName = iconFiles.last {
            return UIImage(named: lastIconName)
        }
        return nil
    }
#endif
}

extension NoctilucaMeta {
    static func scopedIdentifier(_ component: String) -> String {
        return "\(NoctilucaMeta.bundleIdentifier).\(component)"
    }
}

#if DEBUG
extension NoctilucaMeta {
    static var isSwiftUIPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}
#endif
