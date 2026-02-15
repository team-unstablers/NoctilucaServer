//
//  GeneralSessionSettingsTab.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/21/25.
//

import SwiftUI
import SiriusKitClient

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
            get: {
                guard let endpoint = sessionSettings.general?.endpoint else { return "" }
                if case .hostname(let name) = endpoint.address, name.isEmpty { return "" }
                return endpoint.description
            },
            set: { newValue in
                var general = sessionSettings.general ?? SessionSettings.General()
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                general.endpoint = SREndpoint.parse(trimmed)
                sessionSettings.general = general
            }
        )
    }

    private var iconSymbol: Binding<SessionSettings.ContactIconSymbol> {
        Binding(
            get: { sessionSettings.general?.icon.symbol ?? .monitor },
            set: { newValue in
                var general = sessionSettings.general ?? SessionSettings.General()
                general.icon.symbol = newValue
                sessionSettings.general = general
            }
        )
    }

    private var iconBackground: Binding<SessionSettings.ContactIconBackground> {
        Binding(
            get: { sessionSettings.general?.icon.background ?? .blue },
            set: { newValue in
                var general = sessionSettings.general ?? SessionSettings.General()
                general.icon.background = newValue
                sessionSettings.general = general
            }
        )
    }

    private let symbolColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        Form {
            Section {
                TextField(String(localized: "session-settings.general.name.placeholder", defaultValue: "연락처 이름"), text: displayName)
            } header: {
                Text(markdown: String(localized: "session-settings.general.name", defaultValue: "이름"))
            }

            Section {
                TextField(String(localized: "session-settings.general.endpoint.placeholder", defaultValue: "호스트 주소 (host:port)"), text: endpointURL)
#if os(iOS)
                    .textInputAutocapitalization(.never)
#endif
                    .autocorrectionDisabled(true)
            } header: {
                Text(markdown: String(localized: "session-settings.general.endpoint", defaultValue: "호스트 주소"))
                Text(markdown: String(localized: "session-settings.general.endpoint.example", defaultValue: "예: office.example.com:8282"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section(String(localized: "session-settings.general.icon", defaultValue: "아이콘")) {
                // 미리보기
                HStack {
                    Spacer()
                    ContactIconView(
                        icon: .init(symbol: iconSymbol.wrappedValue, background: iconBackground.wrappedValue),
                        size: 64
                    )
                    Spacer()
                }
                .padding(.vertical, 4)

                // 심볼 선택
                VStack(alignment: .leading, spacing: 8) {
                    Text(markdown: String(localized: "session-settings.general.icon.symbol", defaultValue: "심볼"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: symbolColumns, spacing: 8) {
                        ForEach(SessionSettings.ContactIconSymbol.allCases, id: \.self) { symbol in
                            let isSelected = iconSymbol.wrappedValue == symbol
                            Button {
                                iconSymbol.wrappedValue = symbol
                            } label: {
                                Image(systemName: symbol.sfSymbolName)
                                    .font(.system(size: 20))
                                    .frame(width: 44, height: 44)
                                    .foregroundStyle(isSelected ? .white : .primary)
                                    .background(isSelected ? iconBackground.wrappedValue.color : Color.clear)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .strokeBorder(isSelected ? Color.clear : Color.secondary.opacity(0.3), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(symbol.displayName)
                        }
                    }
                }

                // 배경색 선택
                VStack(alignment: .leading, spacing: 8) {
                    Text(markdown: String(localized: "session-settings.general.icon.background", defaultValue: "배경색"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        ForEach(SessionSettings.ContactIconBackground.allCases, id: \.self) { bg in
                            let isSelected = iconBackground.wrappedValue == bg
                            Button {
                                iconBackground.wrappedValue = bg
                            } label: {
                                Circle()
                                    .fill(bg.color.gradient)
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(.white)
                                            .opacity(isSelected ? 1 : 0)
                                    )
                                    .overlay(
                                        Circle()
                                            .strokeBorder(.white.opacity(isSelected ? 0.8 : 0), lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(bg.displayName)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    GeneralSessionSettingsTab(sessionSettings: .constant(SessionSettings(scope: .session)))
}
