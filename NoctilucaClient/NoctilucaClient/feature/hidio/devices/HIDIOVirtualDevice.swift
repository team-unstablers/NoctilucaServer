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
    
    func connect(to controller: HIDIOController)
    func disconnect()
}

protocol HIDIOVirtualDeviceBus {
    func connect(to controller: HIDIOController)
    func disconnect()
}

