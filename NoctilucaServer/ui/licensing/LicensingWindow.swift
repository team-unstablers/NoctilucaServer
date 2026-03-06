//
//  LicensingWindow.swift
//  NoctilucaServer
//

import SwiftUI

struct LicensingWindow: View {
    @State
    private var navigation = LicensingNavigationModel()

    var body: some View {
        ZStack {
            pageView(for: navigation.currentPage)
                .id(navigation.currentPage)
                .transition(slideTransition)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .animation(.easeInOut(duration: 0.35), value: navigation.currentPage)
        .onAppear {
            navigation.onLicenseInstalled = {
                NSApp.keyWindow?.close()
            }
        }
    }

    @ViewBuilder
    private func pageView(for page: LicensingPage) -> some View {
        switch page {
        case .prompt:
            LicensePromptPage(navigation: navigation)
        case .licenseKeyInstall:
            LicenseKeyInstallPage(navigation: navigation)
        case .trialRequest:
            TrialRequestPage(navigation: navigation)
        case .seatManagement:
            SeatManagementPage(navigation: navigation)
        }
    }

    private var slideTransition: AnyTransition {
        switch navigation.direction {
        case .forward:
            return .asymmetric(
                insertion: .move(edge: .trailing),
                removal: .move(edge: .leading)
            )
        case .backward:
            return .asymmetric(
                insertion: .move(edge: .leading),
                removal: .move(edge: .trailing)
            )
        }
    }
}

#Preview {
    LicensingWindow()
        .frame(width: 520, height: 420)
}
