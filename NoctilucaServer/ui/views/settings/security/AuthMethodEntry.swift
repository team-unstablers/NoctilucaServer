//
//  AuthMethodEntry.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/4/25.
//

import Foundation
import SwiftUI

struct AuthMethodEntry: View {
    let method: AllowedAuthMethod
    
    /// FIXME: i18n
    var methodTypeLabel: String {
        switch method {
#if DEBUG
        case .none:
            return "인증을 요구하지 않음 (권장하지 않음)"
#endif
        case .password(_):
            return "UNIX PAM 인증 (사용자명-비밀번호)"
        case .simplePassword(_):
            return "간단 비밀번호 인증 (권장하지 않음)"
        case .sshKey(_):
            return "SSH 키 인증"
        }
    }
    
    /// FIXME: i18n
    var descriptionText: String {
        switch method {
#if DEBUG
        case .none:
            return "아무런 인증도 요구하지 않습니다. (보안 문제가 발생할 수 있으므로 권장하지 않습니다.)"
#endif
        case .password(let allowItem):
            switch allowItem {
            case .group(let name):
                return "\(name) 그룹에 속한 Mac 사용자에게 사용자명-비밀번호 인증을 허용합니다."
            case .user(let name):
                return "\(name) 사용자에게 사용자명-비밀번호 인증을 허용합니다."
            }
        case .simplePassword(_):
            return "비밀번호만을 사용한 인증을 허용합니다. (보안 문제가 발생할 수 있으므로 권장하지 않습니다.)"
        case .sshKey(let publicKey):
            return "\(publicKey)"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(methodTypeLabel)
                .font(.headline)
            Text(descriptionText)
                .font(.subheadline.monospaced())
                .lineLimit(1)
        }
    }
}

#if DEBUG
#Preview {
    VStack(alignment: .leading) {
        AuthMethodEntry(method: .none)
        AuthMethodEntry(method: .password(allows: .user(name: "cheesekun")))
        AuthMethodEntry(method: .sshKey(publicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINGHpezMcBEmby7zNaxPmj4cFPZ/P6zi3wcO5xC1LPZz cheesekun@cheese-mbpr14.local"))
    }
}
#endif
