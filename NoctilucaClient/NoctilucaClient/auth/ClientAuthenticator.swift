//
//  ClientAuthenticator.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/21/25.
//

import Foundation

import SiriusKitClient

final class ClientAuthenticator {
    private let logger = NoctilucaLogger(category: "ClientAuthenticator")

    private let registry: ClientAuthPluginRegistry

    private var autoCandidates: [ClientAuthEntry] = []
    private var autoCandidateIndex: Int = 0
    private var isAutoExhausted: Bool = false

    init(registry: ClientAuthPluginRegistry) {
        self.registry = registry
    }

    func supportedMethods() -> Set<ClientAuthMethod> {
        registry.supportedMethods()
    }

    func availableMethods(for challenge: AuthChallenge) -> [ClientAuthMethod] {
        let supported = supportedMethods()
        return challenge.acceptedMethods.compactMap { rawValue in
            let method = ClientAuthMethod(rawValue: rawValue)
            return supported.contains(method) ? method : nil
        }
    }

    func configureAutoCredentials(sessionEntries: [ClientAuthEntry], globalEntries: [ClientAuthEntry]) {
        autoCandidates = sessionEntries + globalEntries
        autoCandidateIndex = 0
        isAutoExhausted = false
    }

    func nextAutoAuthRequest(for challenge: AuthChallenge) -> (method: ClientAuthMethod, payload: Data)? {
        guard !isAutoExhausted else {
            return nil
        }

        let accepted = Set(challenge.acceptedMethods)

        while autoCandidateIndex < autoCandidates.count {
            let entry = autoCandidates[autoCandidateIndex]
            autoCandidateIndex += 1

            guard accepted.contains(entry.method.rawValue) else {
                continue
            }

            if let payload = payload(for: entry, nonce: challenge.nonce) {
                return (entry.method, payload)
            }
        }

        isAutoExhausted = true
        return nil
    }

    func payload(for entry: ClientAuthEntry, nonce: Data) -> Data? {
        let plugins = registry.plugins(supporting: entry.method)

        for plugin in plugins {
            do {
                return try plugin.payload(for: entry, nonce: nonce)
            } catch {
                logger.debug("payload(): failed using plugin \(type(of: plugin).id): \(error.localizedDescription)")
            }
        }

        return nil
    }
}
