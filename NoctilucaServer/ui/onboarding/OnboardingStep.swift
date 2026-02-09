//
//  OnboardingStep.swift
//  NoctilucaServer
//

import SwiftUI

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome        // Phase 1: 환영
    case permissions    // Phase 2: 권한 설정
    case configuration  // Phase 3: 기본 설정
    case completion     // Phase 4: 완료

    var id: Int { rawValue }

    var isSkippable: Bool {
        switch self {
        case .permissions:
            return true
        default:
            return false
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

    var canGoBack: Bool {
        currentStep != .welcome
    }

    var canGoForward: Bool {
        currentStep != .completion
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

        direction = .backward
        currentStep = OnboardingStep.allCases[OnboardingStep.allCases.index(before: currentIndex)]
    }
}
