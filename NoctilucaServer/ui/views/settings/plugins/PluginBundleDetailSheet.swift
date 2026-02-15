//
//  PluginBundleDetailSheet.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/7/25.
//

import Foundation

import SwiftUI
import Security
import SecurityInterface

import NoctilucaPluginKit


struct PluginBundleDetailSheet: View {
    let metadata: any PluginBundleMetadata
    let signingResult: CodeSigningVerificationResult?

    let dismissAction: () -> Void

    var body: some View {
        TabView() {
            Text("test")
                .tabItem {
                    Text(markdown: String(localized: "settings.plugins.detail_sheet.tab.general", defaultValue: "기본"))
                }
            codeSigningTabContent
                .tabItem {
                    Text(markdown: String(localized: "settings.plugins.detail_sheet.tab.signature", defaultValue: "서명"))
                }
        }
        .with {
            if #available(macOS 15.0, *) {
                $0.tabViewStyle(.grouped)
            } else {
                #warning("macOS 15.0 아래 버전에서 탭 표시 동작을 확인해야 합니다")
                $0
            }
        }
    }

    @ViewBuilder
    private var codeSigningTabContent: some View {
        switch signingResult {
        case .validSignature(let teamID, let identity, let certificates):
            VStack(alignment: .leading, spacing: 12) {
                codeSigningStatusBadge(
                    title: String(localized: "settings.plugins.detail_sheet.signature.valid", defaultValue: "유효한 서명"),
                    systemImage: "checkmark.seal.fill",
                    color: .green
                )

                if let identity {
                    SettingsEntry(title: String(localized: "settings.plugins.detail_sheet.signature.identity", defaultValue: "서명 ID")) {
                        Text(identity)
                            .foregroundStyle(.secondary)
                    }
                }

                SettingsEntry(title: "Team ID") {
                    Text(teamID)
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if let leafCert = certificates.first {
                    Divider()

                    Text(markdown: String(localized: "settings.plugins.detail_sheet.signature.certificate", defaultValue: "인증서 정보"))
                        .font(.headline)

                    PluginBundleCertificateView(certificate: leafCert)
                        .frame(minHeight: 200)
                }
            }
            .padding()

        case .adHocSignature:
            VStack(spacing: 12) {
                codeSigningStatusBadge(
                    title: String(localized: "settings.plugins.detail_sheet.signature.adhoc", defaultValue: "Ad-hoc 서명"),
                    systemImage: "exclamationmark.triangle.fill",
                    color: .orange
                )
                Text(markdown: String(localized: "settings.plugins.detail_sheet.signature.adhoc.description",
                            defaultValue: "이 플러그인 번들은 Ad-hoc으로 서명되어 있으며, 개발자 신원을 확인할 수 없습니다."))
                    .foregroundStyle(.secondary)
            }
            .padding()

        case .unsigned:
            VStack(spacing: 12) {
                codeSigningStatusBadge(
                    title: String(localized: "settings.plugins.detail_sheet.signature.unsigned", defaultValue: "서명 없음"),
                    systemImage: "xmark.seal.fill",
                    color: .red
                )
                Text(markdown: String(localized: "settings.plugins.detail_sheet.signature.unsigned.description",
                            defaultValue: "이 플러그인 번들은 서명되어 있지 않습니다. 신뢰할 수 없는 출처의 플러그인일 수 있습니다."))
                    .foregroundStyle(.secondary)
            }
            .padding()

        case .invalid(let error):
            VStack(spacing: 12) {
                codeSigningStatusBadge(
                    title: String(localized: "settings.plugins.detail_sheet.signature.invalid", defaultValue: "서명 검증 실패"),
                    systemImage: "xmark.seal.fill",
                    color: .red
                )
                Text("OSStatus: \(error)")
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding()

        case nil:
            VStack(spacing: 12) {
                codeSigningStatusBadge(
                    title: String(localized: "settings.plugins.detail_sheet.signature.builtin", defaultValue: "내장 플러그인"),
                    systemImage: "checkmark.seal.fill",
                    color: .blue
                )
                Text(markdown: String(localized: "settings.plugins.detail_sheet.signature.builtin.description",
                            defaultValue: "이 플러그인 번들은 애플리케이션에 내장되어 있습니다."))
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    private func codeSigningStatusBadge(title: String, systemImage: String, color: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.title3)
            .foregroundStyle(color)
    }
}


// MARK: - SFCertificateView 래퍼

struct PluginBundleCertificateView: NSViewRepresentable {
    let certificate: SecCertificate

    func makeNSView(context: Context) -> SFCertificateView {
        let certView = SFCertificateView()
        certView.setCertificate(certificate)
        certView.setDetailsDisclosed(true)
        return certView
    }

    func updateNSView(_ nsView: SFCertificateView, context: Context) {
        nsView.setCertificate(certificate)
    }
}
