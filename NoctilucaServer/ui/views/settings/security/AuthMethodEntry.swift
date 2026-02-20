//
//  AuthMethodEntry.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/4/25.
//

import Foundation
import SwiftUI

import NoctilucaPluginKit

struct AuthMethodEntry: View {
    let entry: RedactedAuthEntry
    
    var methodTypeLabel: String {
        switch entry.method {
#if DEBUG
        case .null:
            return String(localized: "settings.security.auth_entry.null.title", defaultValue: "인증을 요구하지 않음 (권장하지 않음)")
#endif
        case .password:
            return String(localized: "settings.security.auth_entry.password.title", defaultValue: "UNIX PAM 인증 (사용자명-비밀번호)")
        case .simplePassword:
            return String(localized: "settings.security.auth_entry.simple_password.title", defaultValue: "간단 비밀번호 인증 (권장하지 않음)")
        case .sshKey:
            return String(localized: "settings.security.auth_entry.ssh_key.title", defaultValue: "SSH 키 인증")

        default:
            return String(localized: "settings.security.auth_entry.external.title", defaultValue: "외부 인증 방법") + " (\(entry.method.rawValue))"
        }
    }
    
    var descriptionText: String {
        switch entry.method {
#if DEBUG
        case .null:
            return String(localized: "settings.security.auth_entry.null.description", defaultValue: "아무런 인증도 요구하지 않습니다. (보안 문제가 발생할 수 있으므로 권장하지 않습니다.)")
#endif
        case .password:
            if entry.identifier.hasPrefix("group") {
                let groupName = entry.identifier.dropFirst("group:".count)
                return String(format: String(localized: "settings.security.auth_entry.password.group_description", defaultValue: "%@ 그룹에 속한 Mac 사용자에게 사용자명-비밀번호 인증을 허용합니다."), String(groupName))
            } else if entry.identifier.hasPrefix("user") {
                let userName = entry.identifier.dropFirst("user:".count)
                return String(format: String(localized: "settings.security.auth_entry.password.user_description", defaultValue: "%@ 사용자에게 사용자명-비밀번호 인증을 허용합니다."), String(userName))
            } else {
                return String(localized: "settings.security.auth_entry.password.default_description", defaultValue: "지정된 사용자 또는 그룹에 속한 Mac 사용자에게 사용자명-비밀번호 인증을 허용합니다.")
            }
        case .simplePassword:
            return String(localized: "settings.security.auth_entry.simple_password.description", defaultValue: "비밀번호만을 사용한 인증을 허용합니다. (보안 문제가 발생할 수 있으므로 권장하지 않습니다.)")
        case .sshKey:
            return entry.identifier

        default:
            return String(localized: "settings.security.auth_entry.external.description", defaultValue: "외부 플러그인을 통해 제공되는 인증 방법입니다.")
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
        /*
        AuthMethodEntry(method: .none)
        AuthMethodEntry(method: .password(allows: .user(name: "cheesekun")))
        AuthMethodEntry(method: .sshKey(publicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINGHpezMcBEmby7zNaxPmj4cFPZ/P6zi3wcO5xC1LPZz cheesekun@cheese-mbpr14.local"))
         */
    }
}
#endif
