//
//  SREndpoint.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 2/14/26.
//

import Foundation
import Network

// MARK: - SRNetworkAddress

public enum SRNetworkAddress: CustomStringConvertible {
    /// IPv4 주소. host byte order로 저장됩니다. (예: 127.0.0.1 = 0x7F000001)
    case IPv4(UInt32)

    /// IPv6 주소. 두 개의 UInt64로 표현됩니다.
    /// scope id는 if_nametoindex로 표현된 인터페이스 인덱스입니다. (예: en0, eth0 등)
    case IPv6(high: UInt64, low: UInt64, scopeId: UInt32 = 0)

    /// 호스트 이름. 리졸버에 의해 도메인의 A 레코드 또는 AAAA 레코드로 해석됩니다.
    case hostname(String)

    /// 사람이 보기 좋은 형태로 표현된 주소 문자열입니다.
    /// (예: `123.123.123.123`, `[::1]`, `[fe80::a2:ac5d:57d4:327e%en0]`, `example.com` 등)
    public var description: String {
        switch self {
        case .IPv4(let raw):
            let a = UInt8((raw >> 24) & 0xFF)
            let b = UInt8((raw >> 16) & 0xFF)
            let c = UInt8((raw >> 8) & 0xFF)
            let d = UInt8(raw & 0xFF)
            return "\(a).\(b).\(c).\(d)"

        case .IPv6(let high, let low, let scopeId):
            var bytes = [UInt8](repeating: 0, count: 16)
            withUnsafeBytes(of: high.bigEndian) { ptr in
                for i in 0..<8 { bytes[i] = ptr[i] }
            }
            withUnsafeBytes(of: low.bigEndian) { ptr in
                for i in 0..<8 { bytes[8 + i] = ptr[i] }
            }

            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            guard let result = inet_ntop(AF_INET6, &bytes, &buffer, socklen_t(INET6_ADDRSTRLEN)) else {
                return "[::invalid]"
            }
            let addrStr = String(cString: result)

            if scopeId != 0 {
                var ifname = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                if if_indextoname(scopeId, &ifname) != nil {
                    return "[\(addrStr)%\(String(cString: ifname))]"
                } else {
                    return "[\(addrStr)%\(scopeId)]"
                }
            }
            return "[\(addrStr)]"

        case .hostname(let name):
            return name
        }
    }
}

// MARK: - Codable & Sendable

extension SRNetworkAddress: Sendable {}

extension SRNetworkAddress: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        self = SREndpoint.parse(string).address
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

extension SREndpoint: Sendable {}

extension SREndpoint: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        self = SREndpoint.parse(string)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

// MARK: - Host String

public extension SRNetworkAddress {
    /// IPv6 bracket을 제거한 순수 주소 문자열.
    /// TLS SNI / MsQuic serverName에 사용합니다.
    /// (예: `[::1]` → `::1`, IPv4/hostname은 `description` 그대로)
    var hostString: String {
        switch self {
        case .IPv6:
            let desc = description
            if desc.hasPrefix("[") && desc.hasSuffix("]") {
                return String(desc.dropFirst().dropLast())
            }
            return desc
        default:
            return description
        }
    }
}

// MARK: - Equatable

extension SRNetworkAddress: Equatable {
    public static func == (lhs: SRNetworkAddress, rhs: SRNetworkAddress) -> Bool {
        switch (lhs, rhs) {
        case let (.IPv4(a), .IPv4(b)):
            return a == b
        case let (.IPv6(hA, lA, sA), .IPv6(hB, lB, sB)):
            return hA == hB && lA == lB && sA == sB
        case let (.hostname(a), .hostname(b)):
            return a == b
        default:
            return false
        }
    }
}

extension SRNetworkAddress: Hashable {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .IPv4(let v):
            hasher.combine(0)
            hasher.combine(v)
        case .IPv6(let high, let low, let scopeId):
            hasher.combine(1)
            hasher.combine(high)
            hasher.combine(low)
            hasher.combine(scopeId)
        case .hostname(let name):
            hasher.combine(2)
            hasher.combine(name)
        }
    }
}

// MARK: - SREndpoint

public struct SREndpoint: Equatable, Hashable, CustomStringConvertible {
    public let address: SRNetworkAddress
    public let port: UInt16

    public init(address: SRNetworkAddress, port: UInt16 = SiriusQUICDefaultPort) {
        self.address = address
        self.port = port
    }

    public var description: String {
        "\(address.description):\(port)"
    }
}

// MARK: - Parsing

extension SREndpoint {
    /// 주소 문자열을 자동으로 파싱합니다.
    /// IPv4 / IPv6를 먼저 시도하고, 실패하면 hostname으로 간주합니다.
    public static func parse(_ address: String) -> SREndpoint {
        if address.hasPrefix("[") {
            if let endpoint = parse(likelyIPv6: address) {
                return endpoint
            }
        }

        if let endpoint = parse(likelyIPv4: address) {
            return endpoint
        }

        return parseHostname(address)
    }

    /// IPv4 주소 문자열을 파싱합니다.
    /// - dotted decimal: `192.168.1.1:8282` 또는 `192.168.1.1`
    /// - raw UInt32: `2155905152:8282` 또는 `2155905152`
    public static func parse(likelyIPv4 address: String) -> SREndpoint? {
        let (addrPart, port) = splitPortSuffix(address, defaultPort: SiriusQUICDefaultPort)

        if addrPart.contains(".") {
            var addr = in_addr()
            guard inet_pton(AF_INET, addrPart, &addr) == 1 else { return nil }
            let raw = UInt32(bigEndian: addr.s_addr)
            return SREndpoint(address: .IPv4(raw), port: port)
        }

        if let rawValue = UInt32(addrPart) {
            return SREndpoint(address: .IPv4(rawValue), port: port)
        }

        return nil
    }

    /// IPv6 주소 문자열을 파싱합니다.
    /// - `[2001:db8::1]:8282`
    /// - `[fe80::1%en0]:8282` (link-local with scope)
    /// - `[::1]` (포트 생략 시 기본 포트 사용)
    public static func parse(likelyIPv6 address: String) -> SREndpoint? {
        guard address.hasPrefix("[") else { return nil }
        guard let closeBracketIndex = address.firstIndex(of: "]") else { return nil }

        let innerPart = String(address[address.index(after: address.startIndex)..<closeBracketIndex])
        guard !innerPart.isEmpty else { return nil }

        let afterBracket = address[address.index(after: closeBracketIndex)...]
        let port: UInt16
        if afterBracket.isEmpty {
            port = SiriusQUICDefaultPort
        } else if afterBracket.hasPrefix(":"), let portValue = UInt16(afterBracket.dropFirst()) {
            port = portValue
        } else {
            return nil
        }

        var scopeId: UInt32 = 0
        let addrString: String
        if let percentIndex = innerPart.lastIndex(of: "%") {
            addrString = String(innerPart[..<percentIndex])
            let scopeName = String(innerPart[innerPart.index(after: percentIndex)...])
            let idx = if_nametoindex(scopeName)
            if idx != 0 {
                scopeId = idx
            } else if let numericScope = UInt32(scopeName) {
                scopeId = numericScope
            }
        } else {
            addrString = innerPart
        }

        var addr6 = in6_addr()
        guard inet_pton(AF_INET6, addrString, &addr6) == 1 else { return nil }

        let (high, low) = in6AddrToHighLow(addr6)
        return SREndpoint(address: .IPv6(high: high, low: low, scopeId: scopeId), port: port)
    }

    /// 주어진 문자열이 유효한 IPv4 주소인지 확인합니다.
    /// 포트가 포함된 문자열도 허용합니다. (예: `1.2.3.4:80`, `2155905152:8282`)
    public static func isValidIPv4(_ address: String) -> Bool {
        parse(likelyIPv4: address) != nil
    }

    /// 주어진 문자열이 유효한 IPv6 주소인지 확인합니다.
    /// 포트가 포함된 문자열도 허용합니다. (예: `[::1]:80`, `[fe80::1%en0]:8282`)
    public static func isValidIPv6(_ address: String) -> Bool {
        parse(likelyIPv6: address) != nil
    }
}

// MARK: - NWEndpoint Conversion

extension SREndpoint {
    /// NWEndpoint로 변환합니다.
    public func toNWEndpoint() -> NWEndpoint {
        let host: NWEndpoint.Host
        switch address {
        case .IPv4(let raw):
            var networkOrder = raw.bigEndian
            let data = withUnsafeBytes(of: &networkOrder) { Data($0) }
            // swiftlint:disable:next force_unwrapping
            host = .ipv4(IPv4Address(data)!)

        case .IPv6:
            // scope 포함 문자열을 NWEndpoint.Host에 전달하여 scope도 보존
            let desc = address.description
            let stripped = String(desc.dropFirst().dropLast()) // "[addr]" -> "addr"
            host = NWEndpoint.Host(stripped)

        case .hostname(let name):
            host = .name(name, nil)
        }

        // swiftlint:disable:next force_unwrapping
        return .hostPort(host: host, port: NWEndpoint.Port(rawValue: port)!)
    }

    /// NWEndpoint에서 SREndpoint를 생성합니다.
    ///
    /// - Note: IPv6의 scope ID는 NWEndpoint에서 추출할 수 있는 공식 API가 없으므로,
    ///   변환 시 `scopeId`는 항상 `0`으로 설정됩니다.
    /// - Parameter nwEndpoint: 변환할 NWEndpoint. `.hostPort` 케이스만 지원합니다.
    /// - Returns: 변환된 SREndpoint. `.hostPort`가 아닌 경우 `nil`을 반환합니다.
    public init?(from nwEndpoint: NWEndpoint) {
        guard case let .hostPort(host, port) = nwEndpoint else {
            return nil
        }

        switch host {
        case .ipv4(let ipv4Addr):
            let data = ipv4Addr.rawValue
            let networkOrder = data.withUnsafeBytes { $0.load(as: UInt32.self) }
            let hostOrder = UInt32(bigEndian: networkOrder)
            self.init(address: .IPv4(hostOrder), port: port.rawValue)

        case .ipv6(let ipv6Addr):
            let data = ipv6Addr.rawValue
            let (high, low) = data.withUnsafeBytes { ptr -> (UInt64, UInt64) in
                let h = UInt64(bigEndian: ptr.load(fromByteOffset: 0, as: UInt64.self))
                let l = UInt64(bigEndian: ptr.load(fromByteOffset: 8, as: UInt64.self))
                return (h, l)
            }
            self.init(address: .IPv6(high: high, low: low, scopeId: 0), port: port.rawValue)

        case .name(let name, _):
            self.init(address: .hostname(name), port: port.rawValue)

        @unknown default:
            return nil
        }
    }
}

// MARK: - Private Helpers

extension SREndpoint {
    /// 문자열 끝의 `:port` 부분을 분리합니다.
    private static func splitPortSuffix(_ input: String, defaultPort: UInt16) -> (address: String, port: UInt16) {
        guard let colonIndex = input.lastIndex(of: ":") else {
            return (input, defaultPort)
        }

        let afterColon = input[input.index(after: colonIndex)...]
        guard let portValue = UInt16(afterColon) else {
            return (input, defaultPort)
        }

        let addrPart = String(input[..<colonIndex])
        return (addrPart, portValue)
    }

    /// in6_addr를 (high, low) UInt64 튜플로 변환합니다.
    package static func in6AddrToHighLow(_ addr: in6_addr) -> (high: UInt64, low: UInt64) {
        withUnsafeBytes(of: addr) { ptr in
            let high = UInt64(bigEndian: ptr.load(fromByteOffset: 0, as: UInt64.self))
            let low = UInt64(bigEndian: ptr.load(fromByteOffset: 8, as: UInt64.self))
            return (high, low)
        }
    }

    /// hostname 문자열을 파싱합니다. 포트가 포함된 경우 분리합니다.
    private static func parseHostname(_ address: String) -> SREndpoint {
        let (addrPart, port) = splitPortSuffix(address, defaultPort: SiriusQUICDefaultPort)
        return SREndpoint(address: .hostname(addrPart), port: port)
    }
}
