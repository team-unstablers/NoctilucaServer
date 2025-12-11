//
//  AuthChallengeSheetView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/10/25.
//

import SwiftUI
import SiriusKitClient

enum AuthChallengeSheetAction {
    case confirm(method: String, nonce: Data, payload: Data)
    case cancel
}

typealias AuthChallengeSheetActionHandler = (AuthChallengeSheetAction) -> Void

// FIXME
struct PAMAuthChallengeForm: View {
    let authChallenge: AuthChallenge
    let handler: AuthChallengeSheetActionHandler
    
    @State
    var username: String = ""
    
    @State
    var password: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            /*
            Picker("인증 방법", selection: .constant("asdf")) {
                Text("PAM username-password 인증")
                    .tag("asdf")
                
                Text("간단 비밀번호 인증")
                Text("SSH 키 인증")
            }
            .padding(.bottom, 12)
             */
            Text("사용자명")
                .padding(.bottom, 6)
            TextField("사용자명 입력", text: $username)
                .textFieldStyle(.roundedBorder)
                .padding(.bottom, 12)
            
            Text("비밀번호")
                .padding(.bottom, 6)
            SecureField("비밀번호 입력", text: $password)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    performSubmit()
                }
        }
        .padding(12)
        .background(Color.gray.mix(with: .white, by: 0.9))
        .clipShape(.rect(cornerRadius: 8))
        .padding(.bottom, 12)
        
        HStack {
            Spacer()
            Button("취소", role: .cancel) {
                handler(.cancel)
            }
            .keyboardShortcut(.escape)
            Button("확인", role: .confirm) {
                performSubmit()
            }
        }
    }
    
    func performSubmit() {
        // TODO: 별도 authenticator 플러그인 인터페이스로 뺴야 함
        handler(.confirm(method: "password", nonce: authChallenge.nonce, payload: Data()))
    }
}

struct AuthChallengeSheetView: View {
    let authChallenge: AuthChallenge
    let handler: AuthChallengeSheetActionHandler
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("인증 챌린지를 받았습니다")
                .font(.headline)
                .padding(.bottom, 4)
                .foregroundStyle(.primary)
            Text("서버의 메시지: \(authChallenge.message ?? "(없음)")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)
            
            PAMAuthChallengeForm(
                authChallenge: authChallenge,
                handler: handler
            )
        }
        .padding(24)
    }
}

#Preview {
    let authChallenge = AuthChallenge(acceptedMethods: ["password"],
                                      nonce: Data(),
                                      message: "제한 구역입니다")
    
    AuthChallengeSheetView(authChallenge: authChallenge) { action in
        print(action)
    }
}
