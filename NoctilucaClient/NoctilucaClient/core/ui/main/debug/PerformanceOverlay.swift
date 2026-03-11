//
//  PerformanceOverlay.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/19/25.
//

import SwiftUI

import SiriusKitClient

struct PerformanceOverlay: View {
    var codec: Codec?
    var rtt: Double

    var receivedFps: UInt32 = 0
    var droppedFrames: UInt32 = 0
    var avgDecodeMs: UInt32 = 0
    var dataRateKbps: Double = 0
    var decoderType: String = "N/A"

    @State private var isExpanded = false
    @State private var position: CGSize = .zero
    @State private var dragTranslation: CGSize = .zero
    @State private var isDragging = false

    private var currentOffset: CGSize {
        CGSize(
            width: position.width + dragTranslation.width,
            height: position.height + dragTranslation.height
        )
    }

    private var formattedDataRate: String {
        if dataRateKbps >= 1000 {
            return String(format: "%.1f Mbps", dataRateKbps / 1000.0)
        } else {
            return String(format: "%.0f Kbps", dataRateKbps)
        }
    }

    var body: some View {
        Group {
            if isExpanded {
                expandedView
            } else {
                compactView
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isDragging && hypot(value.translation.width, value.translation.height) >= 5 {
                        isDragging = true
                    }
                    if isDragging {
                        dragTranslation = value.translation
                    }
                }
                .onEnded { value in
                    if isDragging {
                        position.width += value.translation.width
                        position.height += value.translation.height
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    }
                    dragTranslation = .zero
                    isDragging = false
                }
        )
        .offset(currentOffset)
    }

    private var compactView: some View {
        HStack(spacing: 6) {
            Text("\(receivedFps)fps")
            Text("|").foregroundStyle(.secondary)
            Text(formattedDataRate)
            Text("|").foregroundStyle(.secondary)
            Text(String(format: "%.1fms", rtt * 1000))
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
    }

    private var expandedView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("**[Performance]**")
            Text("Ping: \(String(format: "%.1f", rtt * 1000)) ms")
            Text("Data rate: \(formattedDataRate)")
            Text("FPS: \(receivedFps) (dropped: \(droppedFrames))")
            Text("Decode: \(avgDecodeMs) ms (avg)")
            Text("Decoder: \(decoderType)")
            Text("")

            if let codec {
                Text("**[Codec]**")
                Text("fourCC: \(codec.fourCC.stringRepresentation)")
                Text("Frame rate: \(String(format: "%.2f", codec.frameRate ?? 0.0)) fps")
                Text("Resolution: \(Int(codec.size?.width ?? -1)) x \(Int(codec.size?.height ?? -1))")

                let optionsString = CodecOptionsParser.serialize(options: codec.options)
                Text("Options:")
                Text(optionsString.split(separator: "; ").joined(separator: ";\n"))
                    .padding(4)
                    .background(Color.black.opacity(0.65))
                    .padding(4)
                    .font(.system(size: 12).monospaced())
                    .foregroundStyle(.white)
                
            }
        }
        .font(.caption.monospacedDigit())
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
    }
}

#Preview("Compact") {
    ZStack(alignment: .topLeading) {
        Color.red.opacity(0.9)
        PerformanceOverlay(
            codec: .init(
                fourCC: .avc1,
                frameRate: 60.0,
                size: SRSize(width: 1920, height: 1080),
                options: CodecOptions(
                    mandatory: [:],
                    optional: [
                        .hardwareAcceleration: .kHardwareAccelerationAuto
                    ]
                ),
                quality: .auto(mode: .balancedPriority)
            ),
            rtt: 0.0123,
            receivedFps: 58,
            droppedFrames: 2,
            avgDecodeMs: 3,
            dataRateKbps: 8500,
            decoderType: "VT (HW)"
        )
        .padding(8)
    }
}

#Preview("Expanded") {
    ZStack(alignment: .topLeading) {
        Color.red.opacity(0.9)
        PerformanceOverlay(
            codec: .init(
                fourCC: .hvc1,
                frameRate: 60.0,
                size: SRSize(width: 2560, height: 1440),
                options: CodecOptions(
                    mandatory: [:],
                    optional: [
                        .hardwareAcceleration: .kHardwareAccelerationAuto
                    ]
                ),
                quality: .auto(mode: .balancedPriority)
            ),
            rtt: 0.0082,
            receivedFps: 60,
            droppedFrames: 0,
            avgDecodeMs: 2,
            dataRateKbps: 15200,
            decoderType: "VT (HW)",
        )
        .padding(8)
    }
}
