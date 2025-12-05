//
//  AuthEntry+Codable.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/5/25.
//

import Foundation

import NoctilucaPluginKit

extension AuthEntry: @retroactive Codable {
    
    public enum CodingKeys: String, CodingKey {
        case method
        case identifier
        case data
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let method = try container.decode(AuthMethod.self, forKey: .method)
        let identifier = try container.decode(String.self, forKey: .identifier)
        let data = try container.decodeIfPresent(Data.self, forKey: .data)
        
        self.init(method: method, identifier: identifier, data: data)
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(method, forKey: .method)
        try container.encode(identifier, forKey: .identifier)
        try container.encodeIfPresent(data, forKey: .data)
    }
    
}
