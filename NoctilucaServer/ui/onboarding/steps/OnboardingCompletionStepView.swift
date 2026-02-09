//
//  OnboardingCompletionStepView.swift
//  NoctilucaServer
//

import SwiftUI

struct OnboardingCompletionStepView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)

            Text(String(localized: "onboarding.completion.title", defaultValue: "준비 완료!"))
                .font(.largeTitle)
                .fontWeight(.bold)

            Text(String(localized: "onboarding.completion.description", defaultValue: "모든 설정이 완료되었습니다.\n이제 클라이언트에서 이 서버에 접속할 수 있습니다."))
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    OnboardingCompletionStepView()
        .frame(width: 780, height: 460)
}
