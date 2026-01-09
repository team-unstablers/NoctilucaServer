//
//  SRRect.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 1/10/26.
//

#if canImport(CoreGraphics)
import Foundation
import CoreGraphics

public extension SRRect {
    var cgRect: CGRect {
        CGRect(x: self.x, y: self.y, width: self.width, height: self.height)
    }
}

public extension SRSize {
    var cgSize: CGSize {
        CGSize(width: self.width, height: self.height)
    }
}

public extension SRPoint {
    var cgPoint: CGPoint {
        CGPoint(x: self.x, y: self.y)
    }
}

#endif
