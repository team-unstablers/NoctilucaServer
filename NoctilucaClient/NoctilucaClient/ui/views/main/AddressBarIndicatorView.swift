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
    var shouldDisplayTooltip = false
    
    
    var body: some View {
        VStack {
            content()
        }
            .frame(width: 24, height: 24)
            .detachedOverlay(role: .tooltip) {
                if shouldDisplayTooltip {
                    VStack(alignment: .leading, spacing: 0) {
                        tooltip()
                    }
                    .fixedSize()
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .clipped()
                }
            }
#if os(macOS)
            .onHover { hoverState in
                shouldDisplayTooltip = hoverState
            }
#endif

    }
}
