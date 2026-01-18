//
//  ClientAuthPluginRegistry.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/21/25.
//

import Foundation

final class ClientAuthPluginRegistry {
    static let shared = ClientAuthPluginRegistry()

    private(set) var plugins: [ClientAuthPluginV1] = []

    private init() {
        register(plugin: PAMAuthClientPlugin())
        register(plugin: SimplePasswordAuthClientPlugin())
        register(plugin: SSHAuthClientPlugin())
    }

    func register(plugin: ClientAuthPluginV1) {
        if plugins.contains(where: { $0 === plugin }) {
            return
        }

        plugins.append(plugin)
    }

    func unregister(plugin: ClientAuthPluginV1) {
        plugins.removeAll { $0 === plugin }
    }

    func unregisterAll() {
        plugins.removeAll()
    }

    func supportedMethods() -> Set<ClientAuthMethod> {
        plugins.reduce(into: Set<ClientAuthMethod>()) { result, plugin in
            result.formUnion(type(of: plugin).supportedMethods)
        }
    }

    func plugins(supporting method: ClientAuthMethod) -> [ClientAuthPluginV1] {
        plugins.filter { type(of: $0).supportedMethods.contains(method) }
    }
}
