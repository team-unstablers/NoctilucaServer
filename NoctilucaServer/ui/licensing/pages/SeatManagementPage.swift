//
//  SeatManagementPage.swift
//  NoctilucaServer
//

import SwiftUI

struct SeatManagementPage: View {
    var navigation: LicensingNavigationModel

    @State private var seats: [SeatInfo] = []
    @State private var selectedSeatIds: Set<String> = []
    @State private var isLoading: Bool = true
    @State private var isRevoking: Bool = false
    @State private var errorMessage: String?
    @State private var showError: Bool = false

    private let apiClient = LicenseAPIClient()

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Form {
                    Section {
                        if isLoading {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        } else if seats.isEmpty {
                            Text(String(localized: "licensing.seats.empty", defaultValue: "할당된 시트가 없습니다."))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(seats, id: \.seatId) { seat in
                                Toggle(isOn: Binding(
                                    get: { selectedSeatIds.contains(seat.seatId) },
                                    set: { isSelected in
                                        if isSelected {
                                            selectedSeatIds.insert(seat.seatId)
                                        } else {
                                            selectedSeatIds.remove(seat.seatId)
                                        }
                                    }
                                )) {
                                    Text(seat.label)
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                    } header: {
                        Text(String(localized: "licensing.seats.header", defaultValue: "시트 관리"))
                        Text("")
                    } footer: {
                        Text(String(localized: "licensing.seats.footer", defaultValue: "시트가 가득 찼습니다. 할당을 해제할 시트를 선택하세요."))
                    }
                }
                .formStyle(.grouped)

                Divider()

                HStack {
                    Button(String(localized: "licensing.seats.cancel", defaultValue: "취소")) {
                        navigation.goBack()
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button(String(localized: "licensing.seats.revoke", defaultValue: "할당 해제")) {
                        revokeSelectedSeats()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedSeatIds.isEmpty)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .disabled(isRevoking)

            if isRevoking {
                ZStack {
                    Color.black.opacity(0.15)
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text(String(localized: "licensing.seats.revoking", defaultValue: "시트 할당을 해제하고 있습니다…"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .task {
            await loadSeats()
        }
        .alert(
            String(localized: "licensing.seats.error_title", defaultValue: "오류"),
            isPresented: $showError,
            presenting: errorMessage
        ) { _ in
            Button(String(localized: "licensing.seats.error_ok", defaultValue: "확인")) { }
        } message: { message in
            Text(message)
        }
    }

    private func loadSeats() async {
        guard let licenseInfo = navigation.licenseInfoForRetry else {
            isLoading = false
            return
        }

        do {
            let result = try await apiClient.listSeats(licenseInfo: licenseInfo)
            await MainActor.run {
                seats = result
                isLoading = false
            }
        } catch {
            await MainActor.run {
                isLoading = false
                handleError(error)
            }
        }
    }

    private func revokeSelectedSeats() {
        guard let licenseInfo = navigation.licenseInfoForRetry else { return }

        isRevoking = true

        Task {
            var failedCount = 0

            for seatId in selectedSeatIds {
                do {
                    try await apiClient.revokeSeat(licenseInfo: licenseInfo, seatId: seatId)
                } catch {
                    failedCount += 1
                }
            }

            await MainActor.run {
                isRevoking = false

                if failedCount > 0 {
                    errorMessage = String(localized: "licensing.seats.error_revoke_partial", defaultValue: "\(failedCount)개의 시트 할당 해제에 실패했습니다.")
                    showError = true
                } else {
                    // 성공 → 라이선스 설치 페이지로 복귀
                    navigation.navigateTo(.licenseKeyInstall)
                }
            }
        }
    }

    private func handleError(_ error: Error) {
        if let apiError = error as? LicenseAPIClientError {
            switch apiError {
            case .serverError(_, let detail):
                errorMessage = detail ?? String(localized: "licensing.seats.error_server", defaultValue: "서버 오류가 발생했습니다.")
            case .networkError:
                errorMessage = String(localized: "licensing.seats.error_network", defaultValue: "네트워크에 연결할 수 없습니다.")
            }
        } else {
            errorMessage = error.localizedDescription
        }
        showError = true
    }
}
