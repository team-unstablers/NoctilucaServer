//
//  AuthChallengeSheetViewModel.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/21/25.
//

import Foundation
import Combine

import SiriusKitClient

final class AuthChallengeSheetViewModel: ObservableObject {
    let authChallenge: AuthChallenge
    let availableMethods: [ClientAuthMethod]

    @Published var selectedMethod: ClientAuthMethod

    @Published var username: String = ""
    @Published var password: String = ""
    @Published var simplePassword: String = ""

    init(authChallenge: AuthChallenge, availableMethods: [ClientAuthMethod]) {
        self.authChallenge = authChallenge
        self.availableMethods = availableMethods
        if let first = availableMethods.first {
            self.selectedMethod = first
        } else {
            let fallback = authChallenge.acceptedMethods.first ?? ClientAuthMethod.password.rawValue
            self.selectedMethod = ClientAuthMethod(rawValue: fallback)
        }
    }

    var canSubmit: Bool {
        switch selectedMethod {
        case .password:
            return !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .simplePassword:
            return !simplePassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .sshKey:
            return false
        default:
            return false
        }
    }

    func makeEntry() -> ClientAuthEntry? {
        switch selectedMethod {
        case .password:
            let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
            return ClientAuthEntry(
                method: .password,
                displayName: nil,
                payload: .password(username: trimmedUsername, password: password)
            )
        case .simplePassword:
            return ClientAuthEntry(
                method: .simplePassword,
                displayName: nil,
                payload: .simplePassword(password: simplePassword)
            )
        case .sshKey:
            return nil
        default:
            return nil
        }
    }
}
