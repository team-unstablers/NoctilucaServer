//
//  View+with.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 1/1/26.
//

import SwiftUI

extension View {
    @ViewBuilder
    func with(@ViewBuilder _ modifier: (Self) -> some View) -> some View {
        modifier(self)
    }
}
