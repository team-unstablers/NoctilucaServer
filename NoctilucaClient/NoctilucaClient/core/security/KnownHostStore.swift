//
//  KnownHostStore.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/11/26.
//

import Foundation

import SiriusKitClient

struct KnownHostEntry: Identifiable, Equatable, Hashable, Codable {
    let id: UUID
    
    let endpoint: String

    let transportType: String
    let fingerprint: Data

    init(
        id: UUID = UUID(),

        endpoint: String,
        
        transportType: String = "quic",
        fingerprint: Data
    ) {
        self.id = id
        
        self.endpoint = endpoint

        self.transportType = transportType
        self.fingerprint = fingerprint
    }

    func equals(_ identity: ServerIdentity) -> Bool {
        switch identity {
        case .sslCertificate(let leaf, _):
            let fingerprint = try? identity.fingerprint()
            return self.fingerprint == fingerprint
        }
    }
}

protocol KnownHostStore: Sendable {
    func getKnownHosts() async throws -> [KnownHostEntry]

    func getKnownHost(endpoint: String) async throws -> KnownHostEntry?
    func getKnownHost(id: UUID) async throws -> KnownHostEntry?

    func saveKnownHost(_ entry: KnownHostEntry) async throws

    func removeKnownHost(endpoint: String) async throws
    func removeKnownHost(id: UUID) async throws

    func removeAllKnownHosts() async throws
}

actor KeychainBackedKnownHostStore: KnownHostStore {
    static let shared = KeychainBackedKnownHostStore()

    private static let keychainKey = "noctiluca.known-hosts"
    private static let logger = NoctilucaLogger(category: "KnownHostStore")

    private let keychain = SRKeychain.shared

    private var cache: [KnownHostEntry]
    private var cacheLoaded = false

    private init() {
        self.cache = []
    }

    func getKnownHosts() async throws -> [KnownHostEntry] {
        try loadCacheIfNeeded()
        return cache
    }

    func getKnownHost(endpoint: String) async throws -> KnownHostEntry? {
        try loadCacheIfNeeded()
        return cache.first { $0.endpoint == endpoint }
    }

    func getKnownHost(id: UUID) async throws -> KnownHostEntry? {
        try loadCacheIfNeeded()
        return cache.first { $0.id == id }
    }

    func saveKnownHost(_ entry: KnownHostEntry) async throws {
        try loadCacheIfNeeded()

        if let index = cache.firstIndex(where: { $0.endpoint == entry.endpoint }) {
            cache[index] = entry
        } else {
            cache.append(entry)
        }

        try await persist()
    }

    func removeKnownHost(endpoint: String) async throws {
        try loadCacheIfNeeded()
        cache.removeAll { $0.endpoint == endpoint }
        try await persist()
    }

    func removeKnownHost(id: UUID) async throws {
        try loadCacheIfNeeded()
        cache.removeAll { $0.id == id }
        try await persist()
    }

    func removeAllKnownHosts() async throws {
        cache = []
        cacheLoaded = true
        _ = try keychain.removeSecureData(key: Self.keychainKey).get()
    }
}

private extension KeychainBackedKnownHostStore {
    static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()

    
    func loadCacheIfNeeded() throws {
        guard !cacheLoaded else { return }
        cacheLoaded = true

        guard let data = try keychain.getSecureData(key: Self.keychainKey).get() else {
            cache = []
            return
        }

        do {
            cache = try Self.jsonDecoder.decode([KnownHostEntry].self, from: data)
        } catch {
            Self.logger.error("Failed to decode known hosts: \(error.localizedDescription)")
            cache = []
        }
    }

    @MainActor
    func persist() async throws {
        let cache = await self.cache
        let data = try Self.jsonEncoder.encode(cache)
        _ = try keychain.setSecureData(data, key: Self.keychainKey).get()
    }
}
