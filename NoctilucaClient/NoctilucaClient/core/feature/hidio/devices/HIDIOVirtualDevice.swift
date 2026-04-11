//
//  HIDIODevice.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/18/25.
//

import Foundation

enum HIDIOVirtualDeviceError: LocalizedError {
    case initializationFailed(Error?)
}

enum HIDIOVirtualDeviceKind {
    case keyboard
    case mouse
    case pointer
}

struct HIDIOVirtualDeviceIdentifier: RawRepresentable, Hashable, Equatable {
    var rawValue: UUID
    
    init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

protocol HIDIOVirtualDevice {
    static var kind: HIDIOVirtualDeviceKind { get }
    /// '인스턴스'에 대한 identifier가 아닌 'Product'에 대한 identifier.
    /// USB 디바이스의 VID/PID와 유사한 개념.
    static var identifier: HIDIOVirtualDeviceIdentifier { get }

    var localIdentifier: String? { get }

    /// HIDIOController 는 @MainActor 로 격리되어 있으므로, 바인딩 연산은 MainActor 에서만 수행된다.
    /// 디바이스 구현체가 별도의 run loop thread 에서 동작하더라도, connect/disconnect 는
    /// 반드시 main thread 에서 호출해야 한다.
    @MainActor func connect(to controller: HIDIOController)
    @MainActor func disconnect()
}

protocol HIDIOVirtualDeviceBus {
    @MainActor func connect(to controller: HIDIOController)
    @MainActor func disconnect()
}

extension HIDIOVirtualDevice {
    var identifierString: String {
        let classIdentifier = type(of: self).identifier.rawValue.uuidString

        if let localIdentifier = localIdentifier {
            return "\(classIdentifier)::\(localIdentifier)"
        } else {
            return classIdentifier
        }
    }
}
