//
//  GeneralSessionSettingsTab.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/21/25.
//

import SwiftUI

struct GeneralSessionSettingsTab: View {
    @Binding
    var sessionSettings: SessionSettings

    private var displayName: Binding<String> {
        Binding(
            get: { sessionSettings.general?.displayName ?? "" },
            set: { newValue in
                var general = sessionSettings.general ?? SessionSettings.General()
                general.displayName = newValue
                sessionSettings.general = general
            }
        )
    }

    private var endpointURL: Binding<String> {
        Binding(
            get: { sessionSettings.general?.endpoint.urlString ?? "" },
            set: { newValue in
                var general = sessionSettings.general ?? SessionSettings.General()
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                general.endpoint = SessionSettings.Endpoint.parse(trimmed)
                sessionSettings.general = general
            }
        )
    }

    var body: some View {
        Form {
            Section {
                TextField("연락처 이름", text: displayName)
            } header: {
                Text("이름")
            }

            Section {
                TextField("호스트 주소 (host:port)", text: endpointURL)
#if os(iOS)
                    .textInputAutocapitalization(.never)
#endif
                    .autocorrectionDisabled(true)
            } header: {
                Text("호스트 주소")
                Text("예: office.example.com:8282")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    GeneralSessionSettingsTab(sessionSettings: .constant(SessionSettings(scope: .session)))
}
