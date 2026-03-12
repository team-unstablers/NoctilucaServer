//
//  View+requiresABC.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 3/12/26.
//

import SwiftUI

#if os(macOS)
import Carbon

private struct RequiresABCModifier: ViewModifier {
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .onChange(of: isFocused) { _, newValue in
                if newValue {
                    selectASCIICapableInputSource()
                }
            }
    }

    private func selectASCIICapableInputSource() {
        guard let list = TISCreateASCIICapableInputSourceList()?.takeRetainedValue() as? [TISInputSource],
              let ascii = list.first else {
            return
        }
        TISSelectInputSource(ascii)
    }
}
#endif

extension View {
    func requiresABC() -> some View {
#if os(macOS)
        self.modifier(RequiresABCModifier())
#else
        self
#endif
    }
}
