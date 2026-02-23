//
//  AppStreamAllowedAppListEntry.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 2/23/26.
//

import Foundation
import SwiftUI
import AppKit

struct AppStreamAllowedAppListEntry: View {
    let app: AppSettings.AppStream.AllowedApp

    private var isValidBundle: Bool {
        FileManager.default.fileExists(atPath: app.path)
    }

    private var appIcon: NSImage {
        if isValidBundle {
            return NSWorkspace.shared.icon(forFile: app.path)
        } else {
            return NSImage(systemSymbolName: "questionmark.app", accessibilityDescription: nil)
                ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)
                ?? NSImage()
        }
    }

    var body: some View {
        HStack(alignment: .center) {
            Image(nsImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading) {
                HStack {
                    Text(app.appName)
                        .font(.headline)
                    if !isValidBundle {
                        Text(String(localized: "settings.app_stream.allowed_apps.invalid_bundle", defaultValue: "(유효하지 않은 번들)"))
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }
                .lineLimit(1)
                Text(app.bundleIdentifier)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
