//
//  ContactItem.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/19/25.
//

import Foundation

struct ContactItem {
    let name: String
    let endpointURL: String
    
    init(name: String?, endpointURL: String) {
        self.name = name ?? ""
        self.endpointURL = endpointURL
    }
}

extension ContactItem {
    var displayName: String {
        return name.isEmpty ? endpointURL : name
    }
}
