//
//  ContactItem.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/19/25.
//

import Foundation

struct ContactItem {
    let id: UUID
    let name: String
    let endpointURL: String
    
    init(id: UUID = UUID(), name: String?, endpointURL: String) {
        self.id = id
        self.name = name ?? ""
        self.endpointURL = endpointURL
    }
}

extension ContactItem {
    var displayName: String {
        return name.isEmpty ? endpointURL : name
    }
}
