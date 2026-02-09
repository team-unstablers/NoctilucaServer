//
//  OnboardingPermissionsStepView.swift
//  NoctilucaServer
//

import SwiftUI

struct OnboardingPermissionsStepView: View {
    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Text(String(localized: "onboarding.permissions.title", defaultValue: "권한 설정"))
                .font(.largeTitle)
                .fontWeight(.bold)

            Text(String(localized: "onboarding.permissions.description", defaultValue: "Noctiluca가 정상적으로 작동하려면 다음 권한이 필요합니다."))
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(spacing: 16) {
                PermissionRow(
                    icon: "rectangle.inset.filled.and.person.filled",
                    title: String(localized: "onboarding.permissions.screen_recording.title", defaultValue: "화면 기록"),
                    description: String(localized: "onboarding.permissions.screen_recording.description", defaultValue: "원격지로 화면을 스트리밍하기 위해 필요합니다."),
                    isGranted: false // TODO: TCCUtil 연동
                )

                PermissionRow(
                    icon: "accessibility",
                    title: String(localized: "onboarding.permissions.accessibility.title", defaultValue: "손쉬운 사용"),
                    description: String(localized: "onboarding.permissions.accessibility.description", defaultValue: "클라이언트의 입력을 시스템에 전달하기 위해 필요합니다."),
                    isGranted: false // TODO: TCCUtil 연동
                )
            }
            .frame(maxWidth: 520)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(.tint)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle")
                .font(.title2)
                .foregroundStyle(isGranted ? .green : .secondary)
        }
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    OnboardingPermissionsStepView()
        .frame(width: 780, height: 460)
}
