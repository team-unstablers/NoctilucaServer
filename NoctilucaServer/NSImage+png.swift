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
    /// Returns the PNG data representation of the image.
    /// - Parameter targetSize: The target size in points. If nil, uses the image's logical size (1x).
    /// - Returns: PNG data of the image rendered at the specified size, or nil if conversion fails.
    func pngData(targetSize: CGSize? = nil) -> Data? {
        let size = targetSize ?? self.size

        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        bitmapRep.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)

        self.draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: self.size),
            operation: .copy,
            fraction: 1.0
        )

        NSGraphicsContext.restoreGraphicsState()

        return bitmapRep.representation(using: .png, properties: [:])
    }
}
