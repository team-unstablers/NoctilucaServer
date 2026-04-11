//
//  SiriusSession.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/29/25.
//

import Foundation

package protocol SiriusSession: AnyObject, Identifiable, Sendable {
    var id: UUID { get }

    var transport: (any TransportLayer) { get }
    var featureProvider: (any FeatureProvider) { get }

    var shouldAcceptChannelCreation: Bool { get set }
}
