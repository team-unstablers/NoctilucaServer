//
//  ApplicationServicesPrivate.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 2/24/26.
//

import Foundation
import ApplicationServices

import Gesu


@PrivateLibrary(path: "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices")
class ApplicationServicesPrivate {
    #PrivateFunction(
        "_AXUIElementGetWindow",
        args: (
            AXUIElement.self,
            UnsafeMutablePointer<CGWindowID>.self
        ),
        ret: AXError.self
    )
}
