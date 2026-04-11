//
//  SRRect.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 1/10/26.
//

import Foundation
internal import SwiftProtobuf

public struct SRRect: Equatable, Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
    
    internal init(from pbMessage: Sirius_Msgdef_V1_Channels_Projection_SRRect) {
        self.x = pbMessage.x
        self.y = pbMessage.y
        self.width = pbMessage.width
        self.height = pbMessage.height
    }
    
    
    internal func toProtobufMessage() -> Sirius_Msgdef_V1_Channels_Projection_SRRect {
        var message = Sirius_Msgdef_V1_Channels_Projection_SRRect()
        
        message.x = self.x
        message.y = self.y
        message.width = self.width
        message.height = self.height
        
        return message
    }
}

public struct SRPoint: Equatable, Hashable, Sendable {
    public let x: Double
    public let y: Double
    
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
    
    internal init(from pbMessage: Sirius_Msgdef_V1_Channels_Projection_SRPoint) {
        self.x = pbMessage.x
        self.y = pbMessage.y
    }
    
    internal func toProtobufMessage() -> Sirius_Msgdef_V1_Channels_Projection_SRPoint {
        var message = Sirius_Msgdef_V1_Channels_Projection_SRPoint()
        
        message.x = self.x
        message.y = self.y
        
        return message
    }
}

public struct SRSize: Equatable, Hashable, Sendable {
    public let width: Double
    public let height: Double
    
    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
    
    internal init(from pbMessage: Sirius_Msgdef_V1_Channels_Projection_SRSize) {
        self.width = pbMessage.x
        self.height = pbMessage.y
    }
    
    internal func toProtobufMessage() -> Sirius_Msgdef_V1_Channels_Projection_SRSize {
        var message = Sirius_Msgdef_V1_Channels_Projection_SRSize()
        
        message.x = self.width
        message.y = self.height
        
        return message
    }
}


