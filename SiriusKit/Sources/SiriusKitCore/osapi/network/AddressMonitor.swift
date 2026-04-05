//
//  AddressWatcher.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 2/9/26.
//

import Foundation
import Combine
import Network
import os

/// NWPathMonitor 시작 전 초기 주소 수집용 (모든 활성 인터페이스 대상)
private func getInterfaceAddresses() -> [IPAddress] {
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
        return []
    }
    defer { freeifaddrs(ifaddr) }

    var addresses: [IPAddress] = []
    var current: UnsafeMutablePointer<ifaddrs>? = firstAddr
    while let addr = current {
        defer { current = addr.pointee.ifa_next }

        guard let sa = addr.pointee.ifa_addr else { continue }

        let flags = addr.pointee.ifa_flags
        // 루프백·다운 인터페이스 제외
        guard (flags & UInt32(IFF_UP)) != 0,
              (flags & UInt32(IFF_LOOPBACK)) == 0 else {
            continue
        }

        var resolved: IPAddress?
        switch Int32(sa.pointee.sa_family) {
        case AF_INET:
            sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
                var addrBytes = sin.pointee.sin_addr
                let data = Data(bytes: &addrBytes, count: MemoryLayout<in_addr>.size)
                resolved = IPv4Address(data)
            }
        case AF_INET6:
            sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { sin6 in
                var addrBytes = sin6.pointee.sin6_addr
                let data = Data(bytes: &addrBytes, count: MemoryLayout<in6_addr>.size)
                resolved = IPv6Address(data)
            }
        default:
            break
        }

        if let resolved {
            addresses.append(resolved)
        }
    }

    return addresses.sorted { a, _ in a is IPv4Address }
}

private func getInterfaceAddresses(orderedBy interfaceNames: [String]) -> [IPAddress] {
    var addressesByInterface: [String: [IPAddress]] = [:]
    let interfaceNameSet = Set(interfaceNames)
    
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
        return []
    }
    defer { freeifaddrs(ifaddr) }
    
    var current: UnsafeMutablePointer<ifaddrs>? = firstAddr
    while let addr = current {
        defer { current = addr.pointee.ifa_next }
        
        guard let name = addr.pointee.ifa_name,
              let sa = addr.pointee.ifa_addr else {
            continue
        }
        
        let ifName = String(cString: name)
        guard interfaceNameSet.contains(ifName) else {
            continue
        }
        
        var resolved: IPAddress?
        switch Int32(sa.pointee.sa_family) {
        case AF_INET:
            sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
                var addrBytes = sin.pointee.sin_addr
                let data = Data(bytes: &addrBytes, count: MemoryLayout<in_addr>.size)
                resolved = IPv4Address(data)
            }
        case AF_INET6:
            sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { sin6 in
                var addrBytes = sin6.pointee.sin6_addr
                let data = Data(bytes: &addrBytes, count: MemoryLayout<in6_addr>.size)
                resolved = IPv6Address(data)
            }
        default:
            break
        }
        
        if let resolved {
            addressesByInterface[ifName, default: []].append(resolved)
        }
    }
    
    // NWPath.availableInterfaces 우선순위 순서를 유지하되,
    // 각 인터페이스 내에서는 IPv6을 우선으로 정렬
    return interfaceNames.flatMap { name in
        (addressesByInterface[name] ?? []).sorted { a, _ in a is IPv6Address }
    }
}


@MainActor
public class AddressMonitor: ObservableObject {
    public static let shared = AddressMonitor()

    private let logger = Logger(subsystem: "SiriusKitCore", category: "AddressMonitor")

    @Published
    private(set) public var currentAddresses: [IPAddress] = []

    public var currentPrimaryAddress: IPAddress? {
        return currentAddresses.first
    }

    private let monitor: NWPathMonitor
    private let queue: DispatchQueue

    init() {
        self.monitor = NWPathMonitor()
        self.queue = DispatchQueue(label: "AddressMonitorQueue")

        self.currentAddresses = getInterfaceAddresses()

        self.monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }

            guard path.status == .satisfied else {
                self.logger.warning("Network path is unsatisfied: \(String(describing: path.status))")
                return
            }

            let orderedInterfaceNames = path.availableInterfaces.map { $0.name }
            let addresses = getInterfaceAddresses(orderedBy: orderedInterfaceNames)

            DispatchQueue.main.async {
                self.currentAddresses = addresses
            }
        }
    }
    
    @MainActor
    deinit {
        self.stop()
    }
    
    public func start() {
        self.monitor.start(queue: self.queue)
    }
    
    public func stop() {
        self.monitor.cancel()
    }
}
