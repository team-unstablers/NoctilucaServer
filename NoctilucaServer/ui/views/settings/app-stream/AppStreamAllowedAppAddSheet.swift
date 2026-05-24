//
//  AppStreamAllowedAppAddSheet.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 2/23/26.
//

import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AppStreamAllowedAppAddSheet: View {
    static let blockedBundleIdentifiers: Set<String> = [
        "com.apple.finder"
    ]

    let existingBundleIdentifiers: Set<String>
    let onComplete: (AppSettings.AppStream.AllowedApp) -> Void

    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        ProgressView()
            .task {
                await openFileDialog()
            }
    }

    private func openFileDialog() async {
        let panel = NSOpenPanel()
        panel.title = String(localized: "settings.app_stream.allowed_apps.add.panel_title", defaultValue: "앱 선택")
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        let response = await panel.beginSheetModal(for: NSApp.keyWindow!)

        guard response == .OK, let url = panel.url else {
            dismiss()
            return
        }

        guard let bundle = Bundle(url: url),
              let bundleIdentifier = bundle.bundleIdentifier else {
            await showAlert(
                title: String(localized: "settings.app_stream.allowed_apps.add.error.invalid_app.title", defaultValue: "유효하지 않은 앱"),
                message: String(localized: "settings.app_stream.allowed_apps.add.error.invalid_app.message", defaultValue: "선택한 파일은 유효한 앱 번들이 아닙니다.")
            )
            dismiss()
            return
        }

        // 차단 목록 검사
        if Self.blockedBundleIdentifiers.contains(bundleIdentifier) {
            await showAlert(
                title: String(localized: "settings.app_stream.allowed_apps.add.error.blocked.title", defaultValue: "차단된 앱"),
                message: String(localized: "settings.app_stream.allowed_apps.add.error.blocked.message", defaultValue: "이 앱은 AppStream을 통한 프로젝션이 허용되지 않습니다.")
            )
            dismiss()
            return
        }

        // 중복 검사
        if existingBundleIdentifiers.contains(bundleIdentifier) {
            await showAlert(
                title: String(localized: "settings.app_stream.allowed_apps.add.error.duplicate.title", defaultValue: "이미 추가된 앱"),
                message: String(localized: "settings.app_stream.allowed_apps.add.error.duplicate.message", defaultValue: "이 앱은 이미 허용된 앱 목록에 추가되어 있습니다.")
            )
            dismiss()
            return
        }

        let appName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent

        let allowedApp = AppSettings.AppStream.AllowedApp(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            path: url.path
        )

        onComplete(allowedApp)
    }

    private func showAlert(title: String, message: String) async {
        let alert = NOCAlert()
        alert.title = title
        alert.message = message
        
        alert.alert.alertStyle = .warning
        
        alert.addButton(title: String(localized: "common.ok", defaultValue: "확인")) {
        }
        
        await alert.present(to: NSApp.keyWindow!)
    }
}
