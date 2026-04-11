//
//  HIDIODebugTab.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 4/3/26.
//

import SwiftUI

import SiriusKitCore

struct HIDIODebugTab: View {
    @ObservedObject var viewModel: RemoteSessionDebugViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                statusSection
                Divider()
                keyboardSection
            }
            .padding(8)
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Status")
                .font(.headline)

            debugRow("Session", viewModel.hidioSessionState == .active ? "Active" : "Inactive")
            debugRow("Mode", modeDisplayName)
        }
    }

    private var modeDisplayName: String {
        switch viewModel.hidioSessionMode {
        case .shared:
            return "Shared"
#if os(macOS)
        case .exclusive:
            return "Exclusive"
#endif
#if os(iOS)
        case .limitedExclusive:
            return "Limited Exclusive"
#endif
        }
    }

    private var keyboardSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pressed Keys (\(viewModel.pressedKeys.count))")
                .font(.headline)

            KeyboardGridView(pressedKeys: viewModel.pressedKeys)
        }
    }

    private func debugRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .font(.caption.monospaced().bold())
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.caption.monospaced())
        }
    }
}
