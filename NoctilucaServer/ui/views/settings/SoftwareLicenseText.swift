//
//  LicenseText.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/5/25.
//

import Foundation
import SwiftUI

import NoctilucaPluginKit

struct SoftwareLicenseText: View {
    let license: SoftwareLicense
    
    
    var body: some View {
        license.textView
    }
}

fileprivate extension SoftwareLicense {
    @ViewBuilder
    var textView: some View {
        switch self {
        case .custom(let name, let url, let isOpenSource):
            /// FIXME: markdown injection 막아야 함
            Text(String(localized: "software_license.custom", defaultValue: "커스텀 라이선스: [\(name)](\(url))"))
        case .dual(let a, let b):
            VStack(alignment: .leading) {
                Text(String(localized: "software_license.dual", defaultValue: "다중 라이선스"))
                // 여기서 무한 재귀가 발생하는데 어쩌죠...
                /*
                a.textView
                b.textView
                 */
            }
        case .proprietary(let name, let url):
            Text(String(localized: "software_license.proprietary", defaultValue: "[\(name)](\(url))"))
        case .mit:
            Text("MIT License")
        case .apache2_0:
            Text("Apache License 2.0")
        case .bsd3:
            Text("BSD 3-Clause License")
        case .gplv3:
            Text("GNU General Public License v3.0")
        case .lgplv3:
            Text("GNU Lesser General Public License v3.0")
        case .cc0:
            Text("Creative Commons Zero v1.0 Universal")
        @unknown default:
            Text(String(localized: "software_license.unknown", defaultValue: "알 수 없는 라이선스"))
        }
    }
}
