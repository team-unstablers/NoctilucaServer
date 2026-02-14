//
//  SREndpointTests.swift
//  SiriusKitTests
//
//  Created by Gyuhwan Park on 2/14/26.
//

import Foundation
import Network
import Testing

@testable import SiriusKitCore

@Suite("SRNetworkAddress - description")
struct SRNetworkAddressDescriptionTests {
    @Test("IPv4 loopback")
    func ipv4Loopback() {
        let addr = SRNetworkAddress.IPv4(0x7F000001)
        #expect(addr.description == "127.0.0.1")
    }

    @Test("IPv4 all zeros")
    func ipv4AllZeros() {
        let addr = SRNetworkAddress.IPv4(0)
        #expect(addr.description == "0.0.0.0")
    }

    @Test("IPv4 all ones")
    func ipv4AllOnes() {
        let addr = SRNetworkAddress.IPv4(0xFFFFFFFF)
        #expect(addr.description == "255.255.255.255")
    }

    @Test("IPv4 private address")
    func ipv4PrivateAddress() {
        // 192.168.1.1 = 0xC0A80101
        let addr = SRNetworkAddress.IPv4(0xC0A80101)
        #expect(addr.description == "192.168.1.1")
    }

    @Test("IPv6 loopback")
    func ipv6Loopback() {
        let addr = SRNetworkAddress.IPv6(high: 0, low: 1)
        #expect(addr.description == "[::1]")
    }

    @Test("IPv6 all zeros")
    func ipv6AllZeros() {
        let addr = SRNetworkAddress.IPv6(high: 0, low: 0)
        #expect(addr.description == "[::]")
    }

    @Test("IPv6 full address")
    func ipv6FullAddress() {
        // 2001:db8:85a3::8a2e:370:7334
        let addr = SRNetworkAddress.IPv6(high: 0x20010db885a30000, low: 0x00008a2e03707334)
        #expect(addr.description == "[2001:db8:85a3::8a2e:370:7334]")
    }

    @Test("IPv6 with scope (lo0)")
    func ipv6WithScope() {
        let scopeId = if_nametoindex("lo0")
        guard scopeId != 0 else { return }

        let addr = SRNetworkAddress.IPv6(high: 0xfe80000000000000, low: 1, scopeId: scopeId)
        #expect(addr.description.contains("%lo0"))
        #expect(addr.description.hasPrefix("["))
        #expect(addr.description.hasSuffix("]"))
    }

    @Test("hostname")
    func hostname() {
        let addr = SRNetworkAddress.hostname("example.com")
        #expect(addr.description == "example.com")
    }
}

@Suite("SREndpoint - IPv4 parsing")
struct SREndpointIPv4ParsingTests {
    @Test("dotted decimal with port")
    func dottedWithPort() {
        let endpoint = SREndpoint.parse(likelyIPv4: "192.168.1.1:9090")
        #expect(endpoint != nil)
        #expect(endpoint?.address == .IPv4(0xC0A80101))
        #expect(endpoint?.port == 9090)
    }

    @Test("dotted decimal without port")
    func dottedWithoutPort() {
        let endpoint = SREndpoint.parse(likelyIPv4: "192.168.1.1")
        #expect(endpoint != nil)
        #expect(endpoint?.address == .IPv4(0xC0A80101))
        #expect(endpoint?.port == 8282)
    }

    @Test("loopback")
    func loopback() {
        let endpoint = SREndpoint.parse(likelyIPv4: "127.0.0.1")
        #expect(endpoint != nil)
        #expect(endpoint?.address == .IPv4(0x7F000001))
        #expect(endpoint?.port == 8282)
    }

    @Test("raw UInt32 with port")
    func rawUInt32WithPort() {
        // 128.128.128.128 = 0x80808080 = 2155905152
        let endpoint = SREndpoint.parse(likelyIPv4: "2155905152:8282")
        #expect(endpoint != nil)
        #expect(endpoint?.address == .IPv4(2155905152))
        #expect(endpoint?.port == 8282)
    }

    @Test("raw UInt32 without port")
    func rawUInt32WithoutPort() {
        let endpoint = SREndpoint.parse(likelyIPv4: "2155905152")
        #expect(endpoint != nil)
        #expect(endpoint?.address == .IPv4(2155905152))
        #expect(endpoint?.port == 8282)
    }

    @Test("invalid dotted decimal")
    func invalidDotted() {
        let endpoint = SREndpoint.parse(likelyIPv4: "999.999.999.999")
        #expect(endpoint == nil)
    }

    @Test("partial dotted decimal")
    func partialDotted() {
        let endpoint = SREndpoint.parse(likelyIPv4: "1.2.3")
        #expect(endpoint == nil)
    }

    @Test("not a number")
    func notANumber() {
        let endpoint = SREndpoint.parse(likelyIPv4: "hello")
        #expect(endpoint == nil)
    }
}

@Suite("SREndpoint - IPv6 parsing")
struct SREndpointIPv6ParsingTests {
    @Test("full address with port")
    func fullAddressWithPort() {
        let endpoint = SREndpoint.parse(likelyIPv6: "[2001:0db8:85a3:0000:0000:8a2e:0370:7334]:8282")
        #expect(endpoint != nil)
        #expect(endpoint?.port == 8282)
        if case .IPv6(let high, let low, _) = endpoint?.address {
            #expect(high == 0x20010db885a30000)
            #expect(low == 0x00008a2e03707334)
        } else {
            #expect(Bool(false), "expected IPv6 address")
        }
    }

    @Test("loopback without port")
    func loopbackWithoutPort() {
        let endpoint = SREndpoint.parse(likelyIPv6: "[::1]")
        #expect(endpoint != nil)
        #expect(endpoint?.address == .IPv6(high: 0, low: 1))
        #expect(endpoint?.port == 8282)
    }

    @Test("all zeros")
    func allZeros() {
        let endpoint = SREndpoint.parse(likelyIPv6: "[::]:9090")
        #expect(endpoint != nil)
        #expect(endpoint?.address == .IPv6(high: 0, low: 0))
        #expect(endpoint?.port == 9090)
    }

    @Test("link-local with scope")
    func linkLocalWithScope() {
        let scopeId = if_nametoindex("lo0")
        guard scopeId != 0 else { return }

        let endpoint = SREndpoint.parse(likelyIPv6: "[fe80::1%lo0]:9090")
        #expect(endpoint != nil)
        #expect(endpoint?.port == 9090)
        if case .IPv6(_, _, let parsedScopeId) = endpoint?.address {
            #expect(parsedScopeId == scopeId)
        } else {
            #expect(Bool(false), "expected IPv6 address")
        }
    }

    @Test("no bracket fails")
    func noBracket() {
        let endpoint = SREndpoint.parse(likelyIPv6: "::1")
        #expect(endpoint == nil)
    }

    @Test("empty bracket fails")
    func emptyBracket() {
        let endpoint = SREndpoint.parse(likelyIPv6: "[]")
        #expect(endpoint == nil)
    }

    @Test("invalid address in bracket fails")
    func invalidAddress() {
        let endpoint = SREndpoint.parse(likelyIPv6: "[not-an-ipv6]:80")
        #expect(endpoint == nil)
    }
}

@Suite("SREndpoint - auto-parse")
struct SREndpointAutoParseTests {
    @Test("routes IPv4")
    func routesIPv4() {
        let endpoint = SREndpoint.parse("10.0.0.1:8080")
        #expect(endpoint.address == .IPv4(0x0A000001))
        #expect(endpoint.port == 8080)
    }

    @Test("routes IPv6")
    func routesIPv6() {
        let endpoint = SREndpoint.parse("[::1]:8282")
        #expect(endpoint.address == .IPv6(high: 0, low: 1))
        #expect(endpoint.port == 8282)
    }

    @Test("routes hostname")
    func routesHostname() {
        let endpoint = SREndpoint.parse("my-host.local")
        #expect(endpoint.address == .hostname("my-host.local"))
        #expect(endpoint.port == 8282)
    }

    @Test("hostname with port")
    func hostnameWithPort() {
        let endpoint = SREndpoint.parse("example.com:443")
        #expect(endpoint.address == .hostname("example.com"))
        #expect(endpoint.port == 443)
    }

    @Test("raw UInt32 routes to IPv4")
    func rawUInt32RoutesToIPv4() {
        let endpoint = SREndpoint.parse("12345")
        if case .IPv4(let raw) = endpoint.address {
            #expect(raw == 12345)
        } else {
            #expect(Bool(false), "expected IPv4 for raw UInt32 input")
        }
    }
}

@Suite("SREndpoint - isValid")
struct SREndpointIsValidTests {
    @Test("valid IPv4 dotted")
    func validIPv4Dotted() {
        #expect(SREndpoint.isValidIPv4("1.2.3.4"))
    }

    @Test("valid IPv4 dotted with port")
    func validIPv4DottedWithPort() {
        #expect(SREndpoint.isValidIPv4("1.2.3.4:80"))
    }

    @Test("valid IPv4 raw UInt32")
    func validIPv4RawUInt32() {
        #expect(SREndpoint.isValidIPv4("2155905152:8282"))
    }

    @Test("invalid IPv4")
    func invalidIPv4() {
        #expect(!SREndpoint.isValidIPv4("abc"))
    }

    @Test("valid IPv6")
    func validIPv6() {
        #expect(SREndpoint.isValidIPv6("[::1]"))
    }

    @Test("valid IPv6 with port")
    func validIPv6WithPort() {
        #expect(SREndpoint.isValidIPv6("[::1]:80"))
    }

    @Test("invalid IPv6 without bracket")
    func invalidIPv6NoBracket() {
        #expect(!SREndpoint.isValidIPv6("::1"))
    }
}

@Suite("SREndpoint - Equatable & Hashable")
struct SREndpointEqualityTests {
    @Test("same endpoint is equal")
    func sameEndpointEqual() {
        let a = SREndpoint(address: .IPv4(0x7F000001), port: 8282)
        let b = SREndpoint(address: .IPv4(0x7F000001), port: 8282)
        #expect(a == b)
    }

    @Test("different port is not equal")
    func differentPortNotEqual() {
        let a = SREndpoint(address: .IPv4(0x7F000001), port: 8282)
        let b = SREndpoint(address: .IPv4(0x7F000001), port: 9090)
        #expect(a != b)
    }

    @Test("different address is not equal")
    func differentAddressNotEqual() {
        let a = SREndpoint(address: .IPv4(0x7F000001), port: 8282)
        let b = SREndpoint(address: .IPv4(0x0A000001), port: 8282)
        #expect(a != b)
    }

    @Test("IPv6 different scopeId is not equal")
    func ipv6DifferentScopeNotEqual() {
        let a = SREndpoint(address: .IPv6(high: 0, low: 1, scopeId: 1), port: 8282)
        let b = SREndpoint(address: .IPv6(high: 0, low: 1, scopeId: 2), port: 8282)
        #expect(a != b)
    }

    @Test("Set deduplication works")
    func setDeduplication() {
        let a = SREndpoint(address: .IPv4(0x7F000001), port: 8282)
        let b = SREndpoint(address: .IPv4(0x7F000001), port: 8282)
        let set: Set<SREndpoint> = [a, b]
        #expect(set.count == 1)
    }
}

@Suite("SREndpoint - NWEndpoint conversion")
struct SREndpointNWEndpointTests {
    @Test("IPv4 roundtrip")
    func ipv4Roundtrip() {
        let original = SREndpoint(address: .IPv4(0xC0A80101), port: 9090)
        let nw = original.toNWEndpoint()
        let restored = SREndpoint(from: nw)
        #expect(restored == original)
    }

    @Test("IPv6 roundtrip (scope lost)")
    func ipv6Roundtrip() {
        let original = SREndpoint(address: .IPv6(high: 0, low: 1), port: 8282)
        let nw = original.toNWEndpoint()
        let restored = SREndpoint(from: nw)
        #expect(restored == original)
    }

    @Test("hostname roundtrip")
    func hostnameRoundtrip() {
        let original = SREndpoint(address: .hostname("example.com"), port: 443)
        let nw = original.toNWEndpoint()
        let restored = SREndpoint(from: nw)
        #expect(restored == original)
    }

    @Test("NWEndpoint IPv4 to SREndpoint")
    func nwIPv4ToSR() {
        let nw = NWEndpoint.hostPort(host: .ipv4(.loopback), port: 8282)
        let endpoint = SREndpoint(from: nw)
        #expect(endpoint != nil)
        #expect(endpoint?.address == .IPv4(0x7F000001))
    }

    @Test("NWEndpoint unix returns nil")
    func nwUnixReturnsNil() {
        let nw = NWEndpoint.unix(path: "/tmp/test.sock")
        let endpoint = SREndpoint(from: nw)
        #expect(endpoint == nil)
    }
}

@Suite("SREndpoint - description/parse roundtrip")
struct SREndpointRoundtripTests {
    @Test("IPv4 roundtrip")
    func ipv4Roundtrip() {
        let original = SREndpoint(address: .IPv4(0xC0A80101), port: 9090)
        let parsed = SREndpoint.parse(original.description)
        #expect(parsed == original)
    }

    @Test("IPv6 roundtrip")
    func ipv6Roundtrip() {
        let original = SREndpoint(address: .IPv6(high: 0x20010db885a30000, low: 0x00008a2e03707334), port: 8282)
        let parsed = SREndpoint.parse(original.description)
        #expect(parsed == original)
    }

    @Test("hostname roundtrip")
    func hostnameRoundtrip() {
        let original = SREndpoint(address: .hostname("example.com"), port: 443)
        let parsed = SREndpoint.parse(original.description)
        #expect(parsed == original)
    }
}
