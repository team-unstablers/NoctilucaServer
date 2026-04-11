//
//  ProjectionDebugTab.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 4/3/26.
//

import SwiftUI

import SiriusKitClient

struct ProjectionDebugTab: View {
    @ObservedObject var viewModel: RemoteSessionDebugViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sessionList
            Divider()
            sessionDetail
        }
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Video Sessions (\(viewModel.videoSessions.count))")
                .font(.headline)
                .padding(.horizontal, 8)
                .padding(.top, 8)

            List(selection: $viewModel.selectedProjectionSessionID) {
                Section("Video") {
                    ForEach(viewModel.videoSessions) { session in
                        HStack {
                            Image(systemName: "play.rectangle")
                                .foregroundStyle(.blue)
                            Text("Display \(session.displayID)")
                                .font(.caption.monospaced())
                            Spacer()
                            Text(session.decoderTypeName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(session.id)
                    }
                }

                if !viewModel.audioSessions.isEmpty {
                    Section("Audio") {
                        ForEach(viewModel.audioSessions) { session in
                            HStack {
                                Image(systemName: "speaker.wave.2")
                                    .foregroundStyle(.green)
                                Text(session.codec?.fourCC.stringRepresentation ?? "unknown")
                                    .font(.caption.monospaced())
                            }
                            .tag(session.id)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .frame(minHeight: 120)
        }
    }

    @ViewBuilder
    private var sessionDetail: some View {
        if let session = viewModel.selectedVideoSession {
            VStack(alignment: .leading, spacing: 4) {
                Text("Selected Session")
                    .font(.headline)

                debugRow("ID", session.id.uuidString)
                debugRow("Display", "\(session.displayID)")
                if let codec = session.codec {
                    debugRow("FourCC", codec.fourCC.stringRepresentation)
                    if let frameRate = codec.frameRate {
                        debugRow("Frame Rate", String(format: "%.1f fps", frameRate))
                    }
                }
                debugRow("Size", "\(Int(session.size.width)) x \(Int(session.size.height))")
                debugRow("Decoder", session.decoderTypeName)
                debugRow("Data Rate", formatDataRate(session.dataRateKbps))
                debugRow("Subscribers", "\(session.referenceCount)")

                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        Task {
                            await viewModel.killProjectionSession(session.id)
                        }
                    } label: {
                        Label("Kill", systemImage: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            .padding(8)
        } else {
            Text("세션을 선택하세요")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80)
        }
    }

    private func debugRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .font(.caption.monospaced().bold())
                .frame(width: 100, alignment: .trailing)
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
    }

    private func formatDataRate(_ kbps: Double) -> String {
        if kbps >= 1000 {
            return String(format: "%.1f Mbps", kbps / 1000.0)
        } else {
            return String(format: "%.0f Kbps", kbps)
        }
    }
}
