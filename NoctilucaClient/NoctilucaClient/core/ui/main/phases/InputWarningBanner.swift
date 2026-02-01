//
//  InputWarningBanner.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/10/25.
//

#if os(macOS)
import SwiftUI
import AppKit

struct InputWarningBanner: View {
    let warning: InputWarning
    let openSettings: () -> Void
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(warning.title)
                .font(.headline)
            Text(warning.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("설정 열기") {
                    openSettings()
                }
                Button("다시 시도") {
                    retry()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.95))
                .shadow(radius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}
#endif
