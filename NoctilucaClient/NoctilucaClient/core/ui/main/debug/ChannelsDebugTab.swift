//
//  ChannelsDebugTab.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 4/3/26.
//

import SwiftUI

import SiriusKitCore

struct ChannelsDebugTab: View {
    @ObservedObject var viewModel: RemoteSessionDebugViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            channelList
            Divider()
            channelDetail
        }
    }

    private var channelList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Channels (\(viewModel.channels.count))")
                .font(.headline)
                .padding(.horizontal, 8)
                .padding(.top, 8)

            List(viewModel.channels, selection: $viewModel.selectedChannelID) { channel in
                HStack {
                    Text("[\(channel.featureName)]")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text(channel.id.uuidString.prefix(18) + "...")
                        .font(.caption.monospaced())
                        .lineLimit(1)
                    Spacer()
                    Text("\(formatRate(channel.uplinkDataRate)) ↑ \(formatRate(channel.downlinkDataRate)) ↓")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.plain)
            .frame(minHeight: 120)
        }
    }

    @ViewBuilder
    private var channelDetail: some View {
        if let channel = viewModel.selectedChannel {
            VStack(alignment: .leading, spacing: 4) {
                Text("Selected Channel")
                    .font(.headline)

                debugRow("ID", channel.id.uuidString)
                debugRow("Feature", channel.featureName)
                if let featureID = channel.featureID {
                    debugRow("Feature ID", featureID.uuidString)
                }
                debugRow("Service Class", "\(channel.serviceClass)")
                debugRow("Direction", channel.direction == .local ? "local" : "remote")
                debugRow("Uplink", formatRate(channel.uplinkDataRate))
                debugRow("Downlink", formatRate(channel.downlinkDataRate))

                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        viewModel.killChannel(channel.id)
                    } label: {
                        Label("Kill", systemImage: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            .padding(8)
        } else {
            Text("채널을 선택하세요")
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

    private func formatRate(_ bytesPerSec: Double) -> String {
        let kbps = bytesPerSec * 8.0 / 1000.0
        if kbps >= 1000 {
            return String(format: "%.1f Mbps", kbps / 1000.0)
        } else if kbps >= 1 {
            return String(format: "%.0f Kbps", kbps)
        } else {
            return "0 Kbps"
        }
    }
}
