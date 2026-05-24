//
//  AppStreamAllowedAppListContainer.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/4/25.
//

import Foundation
import AppKit
import SwiftUI

struct AppStreamAllowedAppListContainer: View {
    @Binding
    var allowedApps: [AppSettings.AppStream.AllowedApp]

    @State
    private var selection = Set<String>()

    var body: some View {
        EditableList(
            items: $allowedApps,
            id: \.id,
            selection: $selection,
            title: String(localized: "settings.app_stream.allowed_apps.title", defaultValue: "허용된 앱 목록"),
            description: String(localized: "settings.app_stream.allowed_apps.description", defaultValue: "AppStream을 통한 앱 단위 프로젝션을 허용할 앱 목록을 관리합니다."),
            canReorder: false,
            rowContent: { app in
                AppStreamAllowedAppListEntry(app: app)
            },
            addSheet: { onComplete in
                AppStreamAllowedAppAddSheet(
                    existingBundleIdentifiers: Set(allowedApps.map(\.bundleIdentifier)),
                    onComplete: onComplete
                )
            }
        )
    }
}
