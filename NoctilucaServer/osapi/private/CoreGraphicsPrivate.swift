//
//  CoreGraphicsPrivate.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 1/19/26.
//

import Foundation
import CoreGraphics

import Gesu

typealias CGSConnectionID = Int

@PrivateLibrary(path: "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
class CoreGraphicsPrivate {
    #PrivateFunction(
        "CGSMainConnectionID",
        args: (),
        ret: CGSConnectionID.self
    )
    
    #PrivateFunction("CGSCurrentCursorSeed", args: (), ret: Int.self)
}
