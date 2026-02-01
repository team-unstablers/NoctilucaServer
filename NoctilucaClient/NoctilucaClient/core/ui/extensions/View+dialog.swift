//
//  View+dialog.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/27/25.
//

import SwiftUI

import SiriusKitClient

extension View {
    @ViewBuilder
    func dialog(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> some View) -> some View {
        self.modifier(DialogModifier(isPresented: isPresented, content: content))
    }
}

#if os(macOS)
struct DialogModifierMacOS<DialogContent: View>: ViewModifier {
    @Binding
    var isPresented: Bool
    
    let content: () -> DialogContent
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                self.content()
            }
    }
}

typealias DialogModifier = DialogModifierMacOS
#else
struct DialogModifierIOS<DialogContent: View>: ViewModifier {
    @Binding
    var isPresented: Bool
    
    let content: () -> DialogContent
    
    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $isPresented) {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    
                    self.content()
                        .background(.background)
                        .cornerRadius(12)
                        .padding(24)
                        .frame(maxWidth: 640)
                        .if(DeviceKind.current == .iPhone) {
                            $0
                        }
                }
                .presentationBackground(.clear)
            }
    }
}

typealias DialogModifier = DialogModifierIOS
#endif

#Preview {
    VStack {
        Text("Hello, World!")
    }
    .dialog(isPresented: .constant(true)) {
        AuthChallengeSheetView(
            authChallenge: AuthChallenge(
                acceptedMethods: ["password"],
                nonce: Data(),
                message: "Hello, World!"
            ),
            availableMethods: [.simplePassword]
        ) { _ in }
    }
}
