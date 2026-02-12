//
//  RecentConnectionRecord.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/12/26.
//

import Foundation

struct RecentConnectionRecord: Codable, Identifiable, Sendable {
    var id: UUID
    var endpointURL: String
    var displayName: String
    var timestamp: Date
    var iconSymbol: String
    var iconBackground: String
    var contactId: UUID?
}
