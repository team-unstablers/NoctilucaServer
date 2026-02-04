//
//  ConstraintedNSWindow.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/21/25.
//

import Foundation

import Cocoa

@MainActor
protocol ConstraintedNSWindow: AnyObject {
    init(to screen: NOCScreen)
}

extension ConstraintedNSWindow {
    var asNSWindow: NSWindow {
        assert(self is NSWindow, "ConstraintedNSWindow protocol can only be adopted by NSWindow subclasses.")
        return self as! NSWindow
    }
}
