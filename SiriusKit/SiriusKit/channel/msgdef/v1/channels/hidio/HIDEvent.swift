//
//  HIDEvent.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 12/26/25.
//

import Foundation
import SwiftProtobuf

public enum HIDIOEventKind {
    case raw
    
    case keyboardSetup
    case keyboard
    
    case mouseMove
    case mouseButton
    case mouseWheel
}

public protocol HIDEvent {
    static var kind: HIDIOEventKind { get }
}

internal protocol HIDEventConvertable: HIDEvent {
    static func from(_ pbMessage: Sirius_Msgdef_V1_Channels_Hidio_HIDEvent) throws -> Self
    func toProtobufMessage() -> Sirius_Msgdef_V1_Channels_Hidio_HIDEvent
}
