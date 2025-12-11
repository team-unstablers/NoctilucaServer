//
//  EventInjector.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/11/25.
//

import Foundation

import Carbon
import CoreGraphics

import SiriusKit


enum EventInjectorError: LocalizedError {
    case initializationError

    var errorDescription: String? {
        switch (self) {
        case .initializationError:
            return "could not initialize EventInjector instance. (insufficient permission?)"
        }
    }
}

class EventInjector {
    public static let MOUSE_DOWN_STATE_LEFT: UInt16 = 0b1
    public static let MOUSE_DOWN_STATE_RIGHT: UInt16 = 0b10

    public let serialQueue = DispatchQueue(label: "EventInjector", qos: .userInteractive)

    var eventSource: CGEventSource!

    var keyDownState = Set<Int>()

    var mouseClickedButton: Int64 = 0
    var mouseClickedAt: Double = 0

    var mouseDownState: UInt16 = 0
    var lastMousePosition: CGPoint? = nil

    init() {
    }

    func prepare() throws {
        guard let eventSource = CGEventSource(stateID: .combinedSessionState) else {
            throw EventInjectorError.initializationError
        }

        self.eventSource = eventSource
    }
}

extension CGEvent {
    func sanitizeModifierFlags(with keyDownState: Set<Int>) {
        // HACK: 이유는 모르겠으나 fn 키가 계속 눌림
        flags.remove(.maskSecondaryFn)
        flags.remove(.maskNumericPad)
        flags.remove(.maskShift)
        flags.remove(.maskAlternate)
        flags.remove(.maskControl)
        flags.remove(.maskCommand)

        if ((keyDownState.contains(kVK_Shift) ||
              keyDownState.contains(kVK_RightShift))) {
            flags.insert(.maskShift)
        }

        if ((keyDownState.contains(kVK_Option) ||
              keyDownState.contains(kVK_RightOption))) {
            flags.insert(.maskAlternate)
        }

        if ((keyDownState.contains(kVK_Control) ||
              keyDownState.contains(kVK_RightControl))) {
            flags.insert(.maskControl)
        }

        if ((keyDownState.contains(kVK_Command) ||
              keyDownState.contains(kVK_RightCommand))) {
            flags.insert(.maskCommand)
        }
    }
}
