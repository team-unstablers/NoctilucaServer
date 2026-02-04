//
//  NSScreenLike.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 2/4/26.
//

import Foundation
import AppKit

protocol NSScreenLike {
    var compatibleDisplayID: CGDirectDisplayID? { get }
    var frame: CGRect { get }
    
    var backingScaleFactor: CGFloat { get }
}

extension NSScreen: NSScreenLike {}
