//
//  SoftwareLicense+SPDX.swift
//  NoctilucaPluginKitHostCore
//
//  Created by Gyuhwan Park on 12/7/25.
//

import Foundation
import NoctilucaPluginKit

extension SoftwareLicense {
    public static func from(spdxIdentifier: String, url: String?) -> SoftwareLicense {
        if spdxIdentifier.hasPrefix("CUSTOM:") {
            let customLicenseName = String(spdxIdentifier.dropFirst("CUSTOM:".count))
            let url = URL(string: url ?? "")

            return .custom(name: customLicenseName, url: url, isOpenSource: false)
        } else if spdxIdentifier.hasPrefix("PROPRIETARY:") {
            let proprietaryLicenseName = String(spdxIdentifier.dropFirst("PROPRIETARY:".count))
            let url = URL(string: url ?? "")

            return .proprietary(name: proprietaryLicenseName, url: url)
        }

        switch spdxIdentifier {
        case "MIT":
            return .mit
        case "Apache-2.0":
            return .apache2_0
        case "GPL-2.0-or-later":
            return .gplv2
        case "GPL-3.0-or-later":
            return .gplv3
        case "LGPL-3.0-or-later":
            return .lgplv3
        case "BSD-3-Clause":
            return .bsd3
        case "CC0-1.0":
            return .cc0
        default:
            return .custom(name: "Unknown License", url: nil, isOpenSource: false)
        }
    }
}
