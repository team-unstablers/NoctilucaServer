//
//  NSImage+png.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 1/19/26.
//

import Foundation

import CoreGraphics
import AppKit

extension NSImage {
    /// Returns the PNG data representation of the image, correctly handling resolution.
    var pngData: Data? {
        guard let tiffRepresentation = tiffRepresentation,
              let bitmapImageRep = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmapImageRep.representation(using: .png, properties: [:])
    }
}
