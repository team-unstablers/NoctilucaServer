//
//  NSScreen+prettyPrint.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 1/1/26.
//

import Cocoa

extension NSScreen {
    var prettyPrintDescription: String {
        let frame = self.frame
        let scale = self.backingScaleFactor
        let displayIDString: String
        if let displayID = self.compatibleDisplayID {
            displayIDString = String(displayID)
        } else {
            displayIDString = "N/A"
        }
        return """
        NSScreen:
          Frame: \(frame.origin.x), \(frame.origin.y), \(frame.size.width), \(frame.size.height)
          Backing Scale Factor: \(scale)
          Display ID: \(displayIDString)
        """
    }
}
