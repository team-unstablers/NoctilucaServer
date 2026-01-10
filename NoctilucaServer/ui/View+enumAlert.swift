//
//  View+enumAlert.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 1/10/26.
//

import Foundation

import SwiftUI

protocol AlertCase: Equatable, Hashable, Identifiable {
    var title: String { get }
    var message: String { get }
}

extension View {
    func enumAlert<T: AlertCase>(alertCase: Binding<T?>) -> some View {
        self.modifier(EnumAlert(alertCase: alertCase))
    }
}

struct EnumAlert<T: AlertCase>: ViewModifier {
    @Binding var alertCase: T?
    
    func body(content: Content) -> some View {
        content
            .alert(item: $alertCase) { alertCase in
                Alert(title: Text(alertCase.title),
                      message: Text(alertCase.message),
                      dismissButton: .default(Text("OK")))
            }
    }
}
