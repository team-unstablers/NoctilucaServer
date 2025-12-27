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

/// '입력 잠금' 기능이 있는 가상 디바이스.
/// 입력 장치를 exclusive하게 점유하는 방식으로 동작하는 디바이스는 이 프로토콜을 상속받아야 합니다.
protocol HIDIOLockableVirtualDevice: HIDIOVirtualDevice {
    /// 디바이스의 입력을 잠그고, exclusive하게 점유합니다.
    func lock() throws
    /// 디바이스의 입력 잠금을 해제하고, 점유를 해제합니다.
    func unlock() throws
}

protocol HIDIOVirtualDeviceBus {
    func connect(to controller: HIDIOController)
    func disconnect()
}

