//
//  ChannelManager.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/23/25.
//

import Foundation

public class ChannelManager {
    private(set) public var channels: [UUID: Channel] = [:]
    
    func registerChannel(_ channel: Channel, for identifier: UUID) throws {
        guard !channels.keys.contains(identifier) else {
            throw ...
        }
        
        self.channels[identifier] = channel
    }
    
    func unregisterChannel(identifier: UUID) {
        self.channels.removeValue(forKey: identifier)
    }
    
    func filter(byFeature feature: SiriusFeature) -> [Channel] {
        return self.channels.values.filter {
            ($0 as? Channel.HasFeature)?.feature == feature
        }
    }
}
