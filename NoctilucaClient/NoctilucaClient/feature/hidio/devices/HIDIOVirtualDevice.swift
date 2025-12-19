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
}

protocol HIDIOVirtualDevice {
    static var kind: HIDIOVirtualDeviceKind { get }
    
    func connect(to controller: HIDIOController)
    func disconnect()
}



