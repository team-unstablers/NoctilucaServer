//
//  LicensingPage.swift
//  NoctilucaServer
//

import SwiftUI

enum LicensingPage: Equatable {
    case prompt
    case licenseKeyInstall
    case trialRequest
    case seatManagement
}

@Observable
final class LicensingNavigationModel {
    enum NavigationDirection {
        case forward
        case backward
    }

    private(set) var currentPage: LicensingPage = .prompt
    private(set) var direction: NavigationDirection = .forward

    /// 시트 관리 → 라이선스 설치로 돌아갈 때 사용할 정보
    var licenseInfoForRetry: LicenseInfo?

    /// 라이선스 설치 성공 콜백
    var onLicenseInstalled: (() -> Void)?

    func navigateTo(_ page: LicensingPage) {
        direction = .forward
        currentPage = page
    }

    func goBack() {
        direction = .backward
        switch currentPage {
        case .prompt:
            break
        case .licenseKeyInstall, .trialRequest:
            currentPage = .prompt
        case .seatManagement:
            currentPage = .licenseKeyInstall
        }
    }
}
