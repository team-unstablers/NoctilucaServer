//
//  PluginBundleDetailView.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/7/25.
//

import Foundation

import SwiftUI
import UniformTypeIdentifiers // UTType을 쓰기 위해 필요

import NoctilucaPluginKit


struct PluginBundleDetailView: View {
    let metadata: any PluginBundleMetadata
    let signingResult: CodeSigningVerificationResult?

    @State
    var showingInfoSheet = false

    var body: some View {
        HStack(alignment: .center) {
            Image(nsImage: NSWorkspace.shared.icon(for: .applicationExtension))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(metadata.displayName)
                        .font(.headline)

                    Text("(\(metadata.id))")
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)

                Text(metadata.description)
                    .font(.subheadline)
                    .lineLimit(1)
            }
            Spacer()
            Button(String(localized: "settings.plugins.detail.show_info", defaultValue: "정보 보기…")) {
                showingInfoSheet = true
            }
        }
        .sheet(isPresented: $showingInfoSheet) {
            PluginBundleDetailSheet(metadata: metadata, signingResult: signingResult) {
                showingInfoSheet = false
            }
        }

        SettingsEntry(title: String(localized: "settings.plugins.detail.developer", defaultValue: "개발자")) {
            VStack(alignment: .trailing) {
                ForEach(metadata.authors, id: \.self) { author in
                    Text(verbatim: author)
                }
            }
            .foregroundStyle(.secondary)
        }

        SettingsEntry(title: String(localized: "settings.plugins.detail.license", defaultValue: "라이선스")) {
            SoftwareLicenseText(license: metadata.license)
                .foregroundStyle(.secondary)
        }

        SettingsEntry(title: String(localized: "settings.plugins.detail.signature", defaultValue: "서명 정보")) {
            signingResultSummaryText
                .foregroundStyle(.secondary)
        }

        SettingsEntry(title: String(localized: "settings.plugins.detail.version", defaultValue: "버전")) {
            Text("\(metadata.displayVersion) (\(metadata.version))")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var signingResultSummaryText: some View {
        switch signingResult {
        case .validSignature(let teamID, let identity, _):
            if let identity {
                Text("\(identity)\n(Team ID: \(teamID))")
                    .multilineTextAlignment(.trailing)
            } else {
                Text(teamID)
                    .multilineTextAlignment(.trailing)
            }
        case .adHocSignature:
            Text(markdown: String(localized: "settings.plugins.detail.signature.adhoc", defaultValue: "Ad-hoc 서명"))
        case .unsigned:
            Text(markdown: String(localized: "settings.plugins.detail.signature.unsigned", defaultValue: "서명 없음"))
        case .invalid(let error):
            Text(markdown: String(localized: "settings.plugins.detail.signature.invalid", defaultValue: "서명 검증 실패 (OSStatus: \(error))"))
        case nil:
            Text(markdown: String(localized: "settings.plugins.detail.signature.builtin", defaultValue: "내장 플러그인"))
        }
    }
}
