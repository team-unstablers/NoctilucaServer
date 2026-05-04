//
//  FSAccessConsentSheet.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 5/4/26.
//

import SwiftUI

import SiriusKitClient

struct FSAccessConsentSheet: View {
    let request: FSAccessConsentRequest
    let onDecision: (FSAccessConsentDecision) -> Void

    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.title2)
                        .foregroundStyle(.tint)
                    Text(markdown: String(localized: "fsaccess.consent.title", defaultValue: "파일 시스템 액세스 요청"))
                        .font(.title2.bold())
                }
                Text(markdown: String(localized: "fsaccess.consent.subtitle", defaultValue: "원격 호스트가 이 기기의 폴더에 접근하려고 합니다."))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                LabeledContent(String(localized: "fsaccess.consent.entry", defaultValue: "폴더")) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(request.entryName)
                            .font(.headline)
                        Text(request.entryPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                }

                LabeledContent(String(localized: "fsaccess.consent.requested_access", defaultValue: "요청한 권한")) {
                    Text(requestedAccessLabel)
                        .foregroundStyle(.tint)
                }

                if let reason = request.reason, !reason.isEmpty {
                    LabeledContent(String(localized: "fsaccess.consent.reason", defaultValue: "사유")) {
                        Text(reason)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .padding(12)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(markdown: String(localized: "fsaccess.consent.warning", defaultValue: "**주의**: 신뢰할 수 없는 호스트라면 거부하세요. 허용한 권한 범위 내에서 호스트는 폴더를 읽거나 수정할 수 있습니다."))
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            HStack {
                Button(String(localized: "common.deny", defaultValue: "거부"), role: .destructive) {
                    submit(.deny)
                }

                Spacer()

                if request.requestedAccess != .read {
                    Button(String(localized: "fsaccess.consent.allow_read_only", defaultValue: "읽기 전용으로 허용")) {
                        submit(.allow(grantedAccess: .read))
                    }
                }

                Button(allowAsRequestedLabel) {
                    submit(.allow(grantedAccess: request.requestedAccess))
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
#if os(macOS)
        .frame(minWidth: 480, minHeight: 320, alignment: .topLeading)
#endif
    }

    private func submit(_ decision: FSAccessConsentDecision) {
        onDecision(decision)
        dismiss()
    }

    private var requestedAccessLabel: String {
        switch request.requestedAccess {
        case .read:
            return String(localized: "fsaccess.consent.access.read", defaultValue: "읽기 전용")
        case .write:
            return String(localized: "fsaccess.consent.access.write", defaultValue: "쓰기 전용")
        case .readWrite:
            return String(localized: "fsaccess.consent.access.read_write", defaultValue: "읽기/쓰기")
        default:
            return String(localized: "fsaccess.consent.access.unknown", defaultValue: "알 수 없음")
        }
    }

    private var allowAsRequestedLabel: String {
        switch request.requestedAccess {
        case .read:
            return String(localized: "fsaccess.consent.allow_read_only", defaultValue: "읽기 전용으로 허용")
        case .write:
            return String(localized: "fsaccess.consent.allow_write", defaultValue: "쓰기로 허용")
        case .readWrite:
            return String(localized: "fsaccess.consent.allow_read_write", defaultValue: "읽기/쓰기로 허용")
        default:
            return String(localized: "common.allow", defaultValue: "허용")
        }
    }
}

#Preview {
    FSAccessConsentSheet(
        request: .init(
            entryName: "내 작업물",
            entryPath: "/Users/cheesekun/Documents/Work",
            requestedAccess: .readWrite,
            reason: "AppStream session for Photoshop"
        ),
        onDecision: { _ in }
    )
}
