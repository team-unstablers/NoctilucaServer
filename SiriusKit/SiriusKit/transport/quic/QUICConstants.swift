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


/// Sirius-over-QUIC의 기본값 포트
/// 8282는 한국어로 '빨리빨리'를 연상시키는 숫자입니다.
public let SiriusQUICDefaultPort: UInt16 = 8282
