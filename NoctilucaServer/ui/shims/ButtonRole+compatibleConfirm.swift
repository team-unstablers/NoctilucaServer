//
//  ButtonRole+macOS26.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 1/1/26.
//

import SwiftUI

extension ButtonRole {
    static var compatibleConfirm: Optional<ButtonRole> {
        if #available(macOS 26.0, iOS 26.0, *) {
            return .confirm
        } else {
            return .none
        }
    }
}
