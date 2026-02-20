//
//  OnboardingWindow.swift
//  NoctilucaServer
//

import SwiftUI

struct OnboardingWindow: View {
    @State
    private var navigation = OnboardingNavigationModel()

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Content Area
            ZStack {
                stepView(for: navigation.currentStep)
                    .id(navigation.currentStep)
                    .transition(slideTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .animation(.easeInOut(duration: 0.35), value: navigation.currentStep)

            Divider()

            // MARK: - Navigation Bar
            OnboardingNavigationBar(navigation: navigation)
        }
    }

    @ViewBuilder
    private func stepView(for step: OnboardingStep) -> some View {
        switch step {
        case .welcome:
            OnboardingWelcomeStepView()
        case .permissions:
            OnboardingPermissionsStepView(navigation: navigation)
        case .configuration:
            OnboardingConfigurationStepView()
                .environmentObject(SettingsStore.shared)
        case .completion:
            OnboardingCompletionStepView()
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

// MARK: - Navigation Bar

private struct OnboardingNavigationBar: View {
    @Bindable
    var navigation: OnboardingNavigationModel

    var body: some View {
        ZStack {
            HStack {
                Spacer()
                
                // Progress dots
                HStack(spacing: 8) {
                    ForEach(OnboardingStep.allCases) { step in
                        Circle()
                            .fill(step == navigation.currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                
                Spacer()
            }
            HStack {
                // Back button
                Button(String(localized: "onboarding.navigation.back", defaultValue: "뒤로")) {
                    navigation.goBack()
                }
                .opacity(navigation.canGoBack ? 1 : 0)
                .disabled(!navigation.canGoBack)
                
                Spacer()

                // Forward / Finish button
                if navigation.currentStep != .completion {
                    if navigation.currentStep.isSkippable {
                        Button(String(localized: "onboarding.navigation.skip", defaultValue: "건너뛰기")) {
                            guard let dialog = navigation.currentStep.skipConfirmationDialog() else {
                                return
                            }
                            
                            dialog.addButton(title: String(localized: "onboarding.permissions.skip_alert.confirm", defaultValue: "건너뛰기")) {
                                navigation.forwardMask = false
                                navigation.goForward()
                            }
                            
                            dialog.addButton(title: String(localized: "onboarding.permissions.skip_alert.cancel", defaultValue: "취소")) {
                                // do nothing
                            }
                            
                            Task {
                                await dialog.present(to: NSApp.keyWindow!)
                            }
                        }
                        .buttonStyle(.borderless)
                        .padding(.trailing, 8)
                    }
                    
                    Button(String(localized: "onboarding.navigation.next", defaultValue: "다음")) {
                        navigation.goForward()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!navigation.canGoForward)
                } else {
                    Button(String(localized: "onboarding.navigation.finish", defaultValue: "시작하기")) {
                        finishOnboarding()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func finishOnboarding() {
        Task { @MainActor in
            SettingsStore.shared.save()
            try? await NoctilucaServer.shared.startup()
            
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            NSApp.keyWindow?.close()
        }
    }
}

#Preview {
    OnboardingWindow()
        .frame(width: 780, height: 540)
}
