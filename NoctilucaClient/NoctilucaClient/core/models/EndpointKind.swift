//
//  EndpointKind.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/21/25.
//

import Foundation

import SiriusKitClient

enum EndpointKind: Hashable, Equatable {
    case contact(item: ContactItem)
    // TODO: recent item
    case quickConnect(endpointURL: String)
    case connect(endpointURL: String)

    var displayText: String {
        switch self {
        case .contact(let item):
            return item.displayName
        case .quickConnect(let endpointURL):
            return String(format: String(localized: "endpoint.quick_connect_format", defaultValue: "빠른 연결: %@"), endpointURL)
        case .connect(let endpointURL):
            return String(format: String(localized: "endpoint.connect_format", defaultValue: "연결: %@"), endpointURL)
        }
    }

    var endpointURL: String {
        switch self {
        case .contact(let item):
            return item.endpointURL
        case .quickConnect(let endpointURL):
            return endpointURL
        case .connect(let endpointURL):
            return endpointURL
        }
    }
    
    var endpoint: SREndpoint {
        switch self {
        case .contact(let item):
            return SREndpoint.parse(item.endpointURL)
        case .quickConnect(let endpointURL):
            return SREndpoint.parse(endpointURL)
        case .connect(let endpointURL):
            return SREndpoint.parse(endpointURL)
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .contact(let item):
            hasher.combine("contact")
            hasher.combine(item.id)
        case .quickConnect(let endpointURL):
            hasher.combine("quickConnect")
            hasher.combine(endpointURL)
        case .connect(let endpointURL):
            hasher.combine("connect")
            hasher.combine(endpointURL)
        }
    }

    static func ==(lhs: EndpointKind, rhs: EndpointKind) -> Bool {
        switch (lhs, rhs) {
        case (.contact(let lhsItem), .contact(let rhsItem)):
            return lhsItem.id == rhsItem.id
        case (.quickConnect(let lhsURL), .quickConnect(let rhsURL)):
            return lhsURL == rhsURL
        case (.connect(let lhsURL), .connect(let rhsURL)):
            return lhsURL == rhsURL
        default:
            return false
        }
    }
}
