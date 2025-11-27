//
//  QUICConstants.swift
//  SiriusKit
//
//  Created by Coding Assistant on 03/01/25.
//

import Foundation

struct SiriusQUICAlpn: RawRepresentable, Equatable, Hashable {
    typealias RawValue = String
    var rawValue: String
    
    init(rawValue: String) {
        self.rawValue = rawValue
    }
    
    static let siriusV1 = SiriusQUICAlpn(rawValue: "pl.unstabler.sirius")
}
