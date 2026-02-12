//
//  RecentConnectionItemView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/12/26.
//

import SwiftUI

struct RecentConnectionItemView: View {
    let record: RecentConnectionRecord
    let onTap: () -> Void

    @State
    private var isHovering: Bool = false

    private var icon: SessionSettings.ContactIcon {
        let symbol = SessionSettings.ContactIconSymbol(rawValue: record.iconSymbol) ?? .monitor
        let background = SessionSettings.ContactIconBackground(rawValue: record.iconBackground) ?? .blue
        return SessionSettings.ContactIcon(symbol: symbol, background: background)
    }

    var body: some View {
        Button {
            onTap()
        } label: {
            VStack(spacing: 6) {
                ContactIconView(icon: icon, size: 40)

                Text(record.displayName)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .frame(width: 80, height: 80)
            .padding(8)
            .contentShape(.rect(cornerRadius: 10))
            .with {
                if #available(macOS 26.0, iOS 26.0, *) {
                    $0.glassEffect(
                        .regular.tint(.gray.opacity(0.05)).interactive(true),
                        in: .rect(cornerRadius: 10)
                    )
                } else {
                    $0.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .scaleEffect(isHovering ? 1.05 : 1.0)
            .brightness(isHovering ? 0.1 : 0.0)
            .animation(.easeInOut(duration: 0.15), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

#Preview {
    let record = RecentConnectionRecord(
        id: UUID(),
        endpointURL: "192.168.0.10:8282",
        displayName: "내 Mac",
        timestamp: Date(),
        iconSymbol: "monitor",
        iconBackground: "blue",
        contactId: nil
    )

    HStack(spacing: 12) {
        RecentConnectionItemView(record: record) {}
        RecentConnectionItemView(record: record) {}
    }
    .padding()
}
