//
//  NSScreen+compatibleDisplayID.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 1/1/26.
//

import Foundation

import Cocoa
import CoreGraphics

extension NSScreen {
    var compatibleDisplayID: CGDirectDisplayID? {
        if #available(macOS 26.0, *) {
            return self.cgDirectDisplayID
        } else {
            return deviceDescription[.init("NSScreenNumber")] as? CGDirectDisplayID
        }
    }
}
