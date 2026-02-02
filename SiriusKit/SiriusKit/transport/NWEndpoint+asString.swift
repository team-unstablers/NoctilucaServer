//
//  NWEndpoint+asString.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 1/10/26.
//

import Foundation
import Network

extension IPv4Address {
    func asString() -> String {
        let data = self.rawValue

        return "\(data[0]).\(data[1]).\(data[2]).\(data[3])"
    }
}

extension IPv6Address {
    func asString() -> String {
        // rawValue(Data)를 안전하게 접근
        return self.rawValue.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return "" }

            // IPv6 주소를 담을 버퍼 (INET6_ADDRSTRLEN은 보통 46)
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))

            // inet_ntop: 바이너리 주소를 텍스트로 변환 (0 압축 자동 처리)
            guard let result = inet_ntop(AF_INET6, baseAddress, &buffer, socklen_t(INET6_ADDRSTRLEN)) else {
                return ""
            }

            return String(cString: result)
        }
    }
}

extension NWEndpoint.Host {
    func asString() -> String {
        switch self {
        case .ipv4(let ipv4):
            return ipv4.asString()
        case .ipv6(let ipv6):
            return ipv6.asString()
        case .name(let name, _):
            return name
        default:
            return "(unknown)"
        }
    }
}

extension NWEndpoint {
    func asString() -> String {
        switch self {
        case .hostPort(let host, let port):
            switch host {
            case .ipv6:
                return "[\(host.asString())]:\(port.rawValue)"
            default:
                return "\(host.asString()):\(port.rawValue)"
            }
        case .unix(let path):
            return "unix:\(path)"
        default:
            return "(unknown)"
        }

    }
}
