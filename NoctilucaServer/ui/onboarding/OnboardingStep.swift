//
//  OnboardingStep.swift
//  NoctilucaServer
//

import SwiftUI

@MainActor
enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome        // Phase 1: 환영
    case permissions    // Phase 2: 권한 설정
    case configuration  // Phase 3: 기본 설정
    case preferences    // Phase 4: 환경 설정 (자동 시작/업데이트)
    case completion     // Phase 5: 완료

    var id: Int { rawValue }

    var isSkippable: Bool {
        switch self {
        case .permissions:
            return true
        default:
            return false
        }
    }
    
    func skipConfirmationDialog() -> NOCAlert? {
        if self == .permissions {
            let alert = NOCAlert()
            alert.title = String(localized: "onboarding.permissions.skip_alert.title", defaultValue: "권한 설정 건너뛰기")
            alert.message = String(localized: "onboarding.permissions.skip_alert.message", defaultValue: "권한 설정을 건너뛰면 Noctiluca Server가 제대로 작동하지 않을 수 있습니다. 그래도 건너뛰시겠습니까?")
            
            return alert
        } else {
            return nil
        }
    }
}

@Observable
final class OnboardingNavigationModel {
    enum NavigationDirection {
        case forward
        case backward
    }

    private(set) var currentStep: OnboardingStep = .welcome
    private(set) var direction: NavigationDirection = .forward
    
    var forwardMask: Bool = false

    var canGoBack: Bool {
        currentStep != .welcome
    }

    var canGoForward: Bool {
        !forwardMask && (currentStep != .completion)
    }

    func goForward() {
        guard canGoForward,
              let nextIndex = OnboardingStep.allCases.firstIndex(of: currentStep)
                .map({ OnboardingStep.allCases.index(after: $0) }),
              nextIndex < OnboardingStep.allCases.endIndex
        else { return }

        direction = .forward
        currentStep = OnboardingStep.allCases[nextIndex]
    }

    func goBack() {
        guard canGoBack,
              let currentIndex = OnboardingStep.allCases.firstIndex(of: currentStep),
              currentIndex > OnboardingStep.allCases.startIndex
        else { return }

        forwardMask = false
        direction = .backward
        currentStep = OnboardingStep.allCases[OnboardingStep.allCases.index(before: currentIndex)]
    }
}
