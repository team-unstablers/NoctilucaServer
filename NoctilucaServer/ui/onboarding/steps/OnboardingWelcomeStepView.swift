//
//  OnboardingWelcomeStepView.swift
//  NoctilucaServer
//

import SwiftUI

struct OnboardingWelcomeStepView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)

            Text(markdown: String(localized: "onboarding.welcome.title", defaultValue: "Noctiluca Server를 선택해 주셔서 감사합니다!"))
                .font(.largeTitle)
                .fontWeight(.bold)

            Text(markdown: String(localized: "onboarding.welcome.description", defaultValue: "Noctiluca Server는 Sirius 프로토콜을 기반으로 한 원격 제어 소프트웨어입니다.\n몇 가지 설정을 완료하면 바로 시작할 수 있습니다."))
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    OnboardingWelcomeStepView()
        .frame(width: 780, height: 460)
}
