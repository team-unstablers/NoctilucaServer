//
//  SREndpoint+Loopback.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 2/14/26.
//

import Foundation

// MARK: - Private Helpers

/// 시스템의 모든 IPv4 주소를 host byte order `UInt32` 배열로 반환합니다.
/// 루프백 인터페이스의 주소도 포함합니다.
private func getAllIPv4Addresses() -> [UInt32] {
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
        return []
    }
    defer { freeifaddrs(ifaddr) }

    var addresses: [UInt32] = []
    var current: UnsafeMutablePointer<ifaddrs>? = firstAddr
    while let addr = current {
        defer { current = addr.pointee.ifa_next }

        guard let sa = addr.pointee.ifa_addr,
              Int32(sa.pointee.sa_family) == AF_INET else {
            continue
        }

        sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
            let hostOrder = UInt32(bigEndian: sin.pointee.sin_addr.s_addr)
            addresses.append(hostOrder)
        }
    }
    return addresses
}

/// 시스템의 모든 IPv6 주소를 `(high, low)` UInt64 쌍 배열로 반환합니다.
/// 루프백 인터페이스의 주소도 포함합니다.
private func getAllIPv6Addresses() -> [(high: UInt64, low: UInt64)] {
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
        return []
    }
    defer { freeifaddrs(ifaddr) }

    var addresses: [(high: UInt64, low: UInt64)] = []
    var current: UnsafeMutablePointer<ifaddrs>? = firstAddr
    while let addr = current {
        defer { current = addr.pointee.ifa_next }

        guard let sa = addr.pointee.ifa_addr,
              Int32(sa.pointee.sa_family) == AF_INET6 else {
            continue
        }

        sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { sin6 in
            let in6 = sin6.pointee.sin6_addr
            let (high, low) = withUnsafeBytes(of: in6) { ptr -> (UInt64, UInt64) in
                let h = UInt64(bigEndian: ptr.load(fromByteOffset: 0, as: UInt64.self))
                let l = UInt64(bigEndian: ptr.load(fromByteOffset: 8, as: UInt64.self))
                return (h, l)
            }
            addresses.append((high: high, low: low))
        }
    }
    return addresses
}

/// 시스템의 호스트 이름을 반환합니다.
private func getLocalHostname() -> String? {
    let maxLen = Int(sysconf(_SC_HOST_NAME_MAX)) + 1
    var buffer = [CChar](repeating: 0, count: maxLen)
    guard gethostname(&buffer, buffer.count) == 0 else {
        return nil
    }
    return String(cString: buffer)
}

// MARK: - SRNetworkAddress + Loopback

public extension SRNetworkAddress {
    /// 이 주소가 로컬 머신을 가리키는 주소인지 판별합니다.
    ///
    /// 다음 조건 중 하나라도 만족하면 `true`를 반환합니다:
    /// - IPv4: `127.0.0.0/8`, `0.0.0.0/8` 범위이거나 시스템 인터페이스에 할당된 주소
    /// - IPv6: `::1`, `::` 이거나 시스템 인터페이스에 할당된 주소
    /// - Hostname: `localhost`, `loopback`, 시스템 호스트 이름, 또는 mDNS `.local` 접미사 매칭
    var isLoopbackAddress: Bool {
        switch self {
        case .IPv4(let ipv4):
            func matchesCIDR(network: UInt32, prefixLength: UInt8) -> Bool {
                let mask: UInt32 = prefixLength == 0
                    ? 0
                    : ~UInt32(0) << (32 - prefixLength)
                return (ipv4 & mask) == (network & mask)
            }

            // 127.0.0.0/8 (표준 루프백 범위)
            if matchesCIDR(network: 0x7F00_0000, prefixLength: 8) { return true }
            // 0.0.0.0/8 ("this host on this network")
            if matchesCIDR(network: 0x0000_0000, prefixLength: 8) { return true }

            // 시스템 인터페이스에 할당된 주소와 매칭
            return getAllIPv4Addresses().contains(ipv4)

        case .IPv6(let high, let low, _):
            // ::1 (표준 IPv6 루프백)
            if high == 0 && low == 1 { return true }
            // :: (unspecified)
            if high == 0 && low == 0 { return true }

            // 시스템 인터페이스에 할당된 주소와 매칭 (scopeId 무시)
            return getAllIPv6Addresses().contains { $0.high == high && $0.low == low }

        case .hostname(let hostname):
            let lowered = hostname.lowercased()

            // 알려진 루프백 호스트 이름
            if lowered == "localhost" || lowered == "loopback" {
                return true
            }

            // 시스템 호스트 이름 비교 + mDNS (.local) 처리
            guard let localHostname = getLocalHostname()?.lowercased() else {
                return false
            }

            let localBase = localHostname.hasSuffix(".local")
                ? String(localHostname.dropLast(6))
                : localHostname
            let inputBase = lowered.hasSuffix(".local")
                ? String(lowered.dropLast(6))
                : lowered

            return inputBase == localBase
        }
    }
}
