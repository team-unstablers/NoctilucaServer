//
//  PerformanceOverlay.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/19/25.
//

import SwiftUI

import SiriusKitClient

struct PerformanceOverlay: View {
    var codec: Codec
    
    var rtt: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("**[Performance]**")
            Text("average ping: \(String(format: "%.1f", rtt * 1000)) ms")
            Text("")
            
            
            Text("**[Negotiated Codec]**")
            Text("fourCC: \(codec.fourCC.stringRepresentation)")
            Text("Frame rate: \(String(format: "%.2f", codec.frameRate ?? 0.0)) fps")
            Text("Resolution: \(Int(codec.size?.width ?? -1)) x \(Int(codec.size?.height ?? -1))")
            Text("Options: \(codec.options ?? "(none)"))")
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .clipped()
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
    }
}

#Preview {
    ZStack {
        Color.red.opacity(0.9)
        PerformanceOverlay(
            codec: .init(
                fourCC: .avc1,
                frameRate: 60.0,
                size: CGSize(width: 1920, height: 1080),
                options: "hardware-acceleration: 'true'",
                quality: .auto(mode: .balancedPriority)
            ),
            rtt: 0.1231,
        )
    }
    
}
