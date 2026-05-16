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
import UniformTypeIdentifiers

import NoctilucaPluginKit


struct PluginBundleDetailSheet: View {
    enum DetailTab: Hashable {
        case general
        case exportCategory(NoctilucaPluginType)
        case codeSigning
    }

    let manifest: any PluginBundleManifest
    let signingResult: CodeSigningVerificationResult?

    @Environment(\.dismiss)
    private var dismiss

    @State
    private var selectedTab: DetailTab = .general

    // MARK: - Computed Properties

    private var exportsByCategory: [NoctilucaPluginType: [any PluginManifest]] {
        Dictionary(grouping: manifest.exports.map(\.manifest), by: { $0.type })
    }

    private var sortedExportCategories: [NoctilucaPluginType] {
        exportsByCategory.keys.sorted(by: { $0.rawValue < $1.rawValue })
    }

    // MARK: - Detail Views

    @ViewBuilder
    private var generalDetail: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(nsImage: NSWorkspace.shared.icon(for: .applicationExtension))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(manifest.name.getString())
                            .font(.title2.bold())
                        Text(manifest.id)
                            .font(.subheadline.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            Section {
                Text(manifest.bundleDescription.getString())
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                SettingsEntry(title: String(localized: "settings.plugins.detail_sheet.general.developer", defaultValue: "개발자")) {
                    VStack(alignment: .trailing) {
                        ForEach(manifest.authors, id: \.self) { author in
                            Text(verbatim: author)
                        }
                    }
                }

                SettingsEntry(title: String(localized: "settings.plugins.detail_sheet.general.license", defaultValue: "라이선스")) {
                    SoftwareLicenseText(license: manifest.license)
                }

                SettingsEntry(title: String(localized: "settings.plugins.detail_sheet.general.pluginkit_version", defaultValue: "PluginKit 버전")) {
                    Text(String(format: "0x%08X", manifest.pluginKitVersion.rawValue))
                        .font(.body.monospaced())
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func exportCategoryDetail(type: NoctilucaPluginType, exports: [any PluginManifest]) -> some View {
        Form {
            ForEach(exports, id: \.id) { export in
                let displayName = export.name.getString()
                let pluginDescription = export.pluginDescription.getString()

                Section {
                    SettingsEntry(title: String(localized: "settings.plugins.detail_sheet.export.name", defaultValue: "이름")) {
                        Text(displayName)
                    }

                    SettingsEntry(title: String(localized: "settings.plugins.detail_sheet.export.id", defaultValue: "ID")) {
                        Text(export.id)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }

                    SettingsEntry(title: String(localized: "settings.plugins.detail_sheet.export.version", defaultValue: "버전")) {
                        Text("\(export.displayVersion) (\(export.version))")
                    }

                    if !pluginDescription.isEmpty {
                        Text(pluginDescription)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(displayName)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var codeSigningDetail: some View {
        Form {
            Section {
                codeSigningContent
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Body

    var body: some View {
        VStack {
            NavigationSplitView {
                List(selection: $selectedTab) {
                    Label(String(localized: "settings.plugins.detail_sheet.tab.general", defaultValue: "기본"), systemImage: "info.circle.fill")
                        .tag(DetailTab.general)

                    ForEach(sortedExportCategories, id: \.self) { type in
                        Label(exportCategoryDisplayName(for: type), systemImage: exportCategoryIcon(for: type))
                            .tag(DetailTab.exportCategory(type))
                    }

                    Label(String(localized: "settings.plugins.detail_sheet.tab.signature", defaultValue: "서명"), systemImage: "signature")
                        .tag(DetailTab.codeSigning)
                }
            } detail: {
                switch selectedTab {
                case .general:
                    generalDetail
                case .exportCategory(let type):
                    if let exports = exportsByCategory[type] {
                        exportCategoryDetail(type: type, exports: exports)
                    }
                case .codeSigning:
                    codeSigningDetail
                }
            }
            .navigationSplitViewStyle(.balanced)
            .toolbar(removing: .sidebarToggle)

            HStack {
                Spacer()
                Button(String(localized: "common.close", defaultValue: "닫기")) {
                    dismiss()
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(minWidth: 560, minHeight: 360)
    }
}

// MARK: - Code Signing Content

private extension PluginBundleDetailSheet {
    @ViewBuilder
    var codeSigningContent: some View {
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
                    }
                }

                SettingsEntry(title: "Team ID") {
                    Text(teamID)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }

                if let leafCert = certificates.first {
                    Divider()

                    Text(String(localized: "settings.plugins.detail_sheet.signature.certificate", defaultValue: "인증서 정보"))
                        .font(.headline)

                    PluginBundleCertificateView(certificate: leafCert)
                        .frame(minHeight: 200)
                }
            }

        case .adHocSignature:
            VStack(spacing: 12) {
                codeSigningStatusBadge(
                    title: String(localized: "settings.plugins.detail_sheet.signature.adhoc", defaultValue: "Ad-hoc 서명"),
                    systemImage: "exclamationmark.triangle.fill",
                    color: .orange
                )
                Text(String(localized: "settings.plugins.detail_sheet.signature.adhoc.description",
                            defaultValue: "이 플러그인 번들은 Ad-hoc으로 서명되어 있으며, 개발자 신원을 확인할 수 없습니다."))
                    .foregroundStyle(.secondary)
            }

        case .unsigned:
            VStack(spacing: 12) {
                codeSigningStatusBadge(
                    title: String(localized: "settings.plugins.detail_sheet.signature.unsigned", defaultValue: "서명 없음"),
                    systemImage: "xmark.seal.fill",
                    color: .red
                )
                Text(String(localized: "settings.plugins.detail_sheet.signature.unsigned.description",
                            defaultValue: "이 플러그인 번들은 서명되어 있지 않습니다. 신뢰할 수 없는 출처의 플러그인일 수 있습니다."))
                    .foregroundStyle(.secondary)
            }

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

        case nil:
            VStack(spacing: 12) {
                codeSigningStatusBadge(
                    title: String(localized: "settings.plugins.detail_sheet.signature.builtin", defaultValue: "내장 플러그인"),
                    systemImage: "checkmark.seal.fill",
                    color: .blue
                )
                Text(String(localized: "settings.plugins.detail_sheet.signature.builtin.description",
                            defaultValue: "이 플러그인 번들은 애플리케이션에 내장되어 있습니다."))
                    .foregroundStyle(.secondary)
            }
        }
    }

    func codeSigningStatusBadge(title: String, systemImage: String, color: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.title3)
            .foregroundStyle(color)
    }
}

// MARK: - Export Category Helpers

private extension PluginBundleDetailSheet {
    func exportCategoryIcon(for type: NoctilucaPluginType) -> String {
        switch type {
        case .auth:
            return "person.badge.key.fill"
        case .keyboardHack:
            return "keyboard.fill"
        case .feature:
            return "puzzlepiece.fill"
        case .extension:
            return "gearshape.2.fill"
        @unknown default:
            return "questionmark.circle.fill"
        }
    }

    func exportCategoryDisplayName(for type: NoctilucaPluginType) -> String {
        switch type {
        case .auth:
            return String(localized: "settings.plugins.detail_sheet.tab.auth", defaultValue: "인증")
        case .keyboardHack:
            return String(localized: "settings.plugins.detail_sheet.tab.keyboard_hack", defaultValue: "키보드 핵")
        case .feature:
            return String(localized: "settings.plugins.detail_sheet.tab.feature", defaultValue: "기능")
        case .extension:
            return String(localized: "settings.plugins.detail_sheet.tab.extension", defaultValue: "익스텐션")
        @unknown default:
            return String(localized: "settings.plugins.detail_sheet.tab.unknown", defaultValue: "기타")
        }
    }
}


// MARK: - SFCertificateView Wrapper

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
