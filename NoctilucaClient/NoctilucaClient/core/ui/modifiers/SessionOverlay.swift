//
//  SessionOverlay.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/2/26.
//

import Foundation
import SwiftUI

extension View {
    @ViewBuilder
    func sessionOverlay<Content: View, SubContent: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder subcontent: @escaping () -> SubContent
    ) -> some View {
        self
            .modifier(SessionOverlayModifier(isPresented: isPresented, overlayContent: content, overlaySubcontent: subcontent))
    }
}

struct SessionOverlayModifier<OverlayContent: View, OverlaySubContent: View>: ViewModifier {
    @Binding
    var isPresented: Bool

    @ViewBuilder
    var overlayContent: () -> OverlayContent

    var overlaySubcontent: (() -> OverlaySubContent)? = nil

    init(
        isPresented: Binding<Bool>,
        overlayContent: @escaping () -> OverlayContent,
        overlaySubcontent: (() -> OverlaySubContent)? = nil
    ) {
        self._isPresented = isPresented
        self.overlayContent = overlayContent
        self.overlaySubcontent = overlaySubcontent
    }

    func body(content: Content) -> some View {
        ZStack {
            content
                .allowsHitTesting(!isPresented)

            if isPresented {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea(.all)
                    .onTapGesture {
                        withAnimation {
                            isPresented = false
                        }
                    }
                    .transition(.opacity)

                ZStack(alignment: .bottom) {
                    VStack {
                        if let overlaySubcontent {
                            Spacer()
                            overlaySubcontent()
                            Spacer()
                        }

                        ZStack {
                            LinearGradient(stops: [
                                .init(color: .black, location: 0.0),
                                .init(color: .black, location: 0.3),
                                .init(color: .black.opacity(0.0), location: 1.0),
                            ], startPoint: .bottom, endPoint: .top)
                            overlayContent()
                                .environment(\.colorScheme, .dark)
                                .safeAreaPadding(.bottom)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .ignoresSafeArea(.all, edges: [.bottom])
                .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: isPresented)
    }
}
