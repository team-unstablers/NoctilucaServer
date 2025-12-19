//
//  AddressBarIndicatorView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/17/25.
//

import SwiftUI

struct AddressBarIndicatorView<Content: View, Tooltip: View>: View {
    @ViewBuilder
    let content: () -> Content
    
    @ViewBuilder
    let tooltip: () -> Tooltip
    
    @State
    var shouldDisplayTooltip = true
    
    @State
    var tooltipSize: CGSize = .zero
    
    
    var body: some View {
        VStack {
            content()
        }
            .frame(width: 24, height: 24)
            .overlay(alignment: .bottom) {
                GeometryReader { proxy in
                    let offsetX = -(tooltipSize.width) + (proxy.size.width)
                    if shouldDisplayTooltip {
                        VStack(alignment: .leading, spacing: 0) {
                            tooltip()
                        }
                        .fixedSize()
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .clipped()
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                        .offset(x: offsetX, y: 26)
                        .onGeometryChange(for: CGSize.self) { proxy in
                            proxy.size
                        } action: { geom in
                            self.tooltipSize = geom
                        }
                    }
                }
            }
#if os(macOS)
            .onHover { hoverState in
                shouldDisplayTooltip = hoverState
            }
#endif

    }
}
