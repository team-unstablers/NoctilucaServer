//
//  TransferChannelArguments.swift
//  NoctilucaClient
//

import Foundation
import SiriusKitClient

// MARK: - Purpose / Direction

struct TransferChannelPurpose: RawRepresentable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let fileTransfer = Self(rawValue: "file-transfer")
    public static let clipboardData = Self(rawValue: "clipboard-data")
    public static let fsaccessMount = Self(rawValue: "fsaccess-mount")
}

struct TransferChannelDirection: RawRepresentable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let upload = Self(rawValue: "upload")
    public static let download = Self(rawValue: "download")
}

// MARK: - Query String parser/encoder

enum TransferQueryString {
    enum ParseError: Error, CustomStringConvertible {
        case bareKey(token: String)

        var description: String {
            switch self {
            case .bareKey(let token): return "bare key in query string: \(token)"
            }
        }
    }

    /// RFC 3986 query-component → [key: value]. Bare keys (no '=') throw.
    /// '+' is treated as a literal '+' (NOT folded to space).
    static func parse(_ source: String) throws -> [String: String] {
        if source.isEmpty { return [:] }

        var pairs: [String: String] = [:]
        for token in source.split(separator: "&", omittingEmptySubsequences: false) {
            let str = String(token)
            if str.isEmpty { continue }
            guard let eq = str.firstIndex(of: "=") else {
                throw ParseError.bareKey(token: str)
            }
            let key = String(str[..<eq])
            let rawValue = String(str[str.index(after: eq)...])
            let decoded = rawValue.removingPercentEncoding ?? rawValue
            pairs[key] = decoded
        }
        return pairs
    }

    /// [(key, value)] → RFC 3986 query-component. Caller decides ordering.
    static func encode(_ pairs: [(String, String)]) -> String {
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~"
        )
        return pairs.map { (key, value) in
            let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(key)=\(encoded)"
        }.joined(separator: "&")
    }
}

// MARK: - ArgumentsSet

enum TransferArgumentsParseError: Error, CustomStringConvertible {
    case wrongArity(expected: Int, got: Int)
    case bareKey(slot: String, token: String)

    var description: String {
        switch self {
        case .wrongArity(let expected, let got):
            return "transfer args expected \(expected) elements, got \(got)"
        case .bareKey(let slot, let token):
            return "bare key in \(slot): \(token)"
        }
    }
}

struct TransferChannelArgumentsSet {
    let purpose: TransferChannelPurpose
    let direction: TransferChannelDirection
    let purposeArgs: [String: String]
    let transferArgs: [String: String]

    /// transferArgs["compress"] 의 CSV 를 [CompressionMethod] 로 풀어준다.
    var proposedCompressionMethods: [CompressionMethod] {
        guard let csv = transferArgs["compress"], !csv.isEmpty else { return [] }
        return csv.split(separator: ",").map { CompressionMethod(rawValue: String($0)) }
    }
}

extension TransferChannelArgumentsSet {
    static func parse(from args: [String]) throws -> TransferChannelArgumentsSet {
        guard args.count == 4 else {
            throw TransferArgumentsParseError.wrongArity(expected: 4, got: args.count)
        }
        let purpose = TransferChannelPurpose(rawValue: args[0])
        let direction = TransferChannelDirection(rawValue: args[1])

        let purposePairs: [String: String]
        do {
            purposePairs = try TransferQueryString.parse(args[2])
        } catch let TransferQueryString.ParseError.bareKey(token) {
            throw TransferArgumentsParseError.bareKey(slot: "purposeArgs", token: token)
        }

        let transferPairs: [String: String]
        do {
            transferPairs = try TransferQueryString.parse(args[3])
        } catch let TransferQueryString.ParseError.bareKey(token) {
            throw TransferArgumentsParseError.bareKey(slot: "transferArgs", token: token)
        }

        return TransferChannelArgumentsSet(
            purpose: purpose,
            direction: direction,
            purposeArgs: purposePairs,
            transferArgs: transferPairs
        )
    }

    func serialize() -> [String] {
        let purposePairs = purposeArgs.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        let transferPairs = transferArgs.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        return [
            purpose.rawValue,
            direction.rawValue,
            TransferQueryString.encode(purposePairs),
            TransferQueryString.encode(transferPairs),
        ]
    }
}

// MARK: - Builders for callers

extension TransferChannelArgumentsSet {
    /// `file-transfer` purpose builder.
    static func fileTransfer(
        direction: TransferChannelDirection,
        name: String,
        path: String? = nil,
        offset: UInt64 = 0,
        length: UInt64,
        compress: [CompressionMethod] = []
    ) -> TransferChannelArgumentsSet {
        var purposeArgs: [String: String] = [
            "name": name,
            "offset": String(offset),
            "length": String(length),
        ]
        if let path = path { purposeArgs["path"] = path }

        var transferArgs: [String: String] = [:]
        if !compress.isEmpty {
            transferArgs["compress"] = compress.map { $0.rawValue }.joined(separator: ",")
        }
        return .init(
            purpose: .fileTransfer,
            direction: direction,
            purposeArgs: purposeArgs,
            transferArgs: transferArgs
        )
    }

    /// `clipboard-data` purpose builder.
    static func clipboardData(
        direction: TransferChannelDirection,
        itemIndex: UInt32,
        representationIndex: UInt32,
        compress: [CompressionMethod] = []
    ) -> TransferChannelArgumentsSet {
        var transferArgs: [String: String] = [:]
        if !compress.isEmpty {
            transferArgs["compress"] = compress.map { $0.rawValue }.joined(separator: ",")
        }
        return .init(
            purpose: .clipboardData,
            direction: direction,
            purposeArgs: [
                "item-index": String(itemIndex),
                "representation-index": String(representationIndex),
            ],
            transferArgs: transferArgs
        )
    }
}
