//
//  TransportLayer.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/29/25.
//

import Foundation

public typealias TransportLayerIdentifier = UUID

public enum TransportLayerError: Error {
    case notImplemented
    case connectionFailed(error: Error?)
    case openStreamFailed(error: Error?)
    case mainChannelOpenFailed
}

public protocol TransportLayer: AnyObject, Identifiable {
    var id: TransportLayerIdentifier { get }

    func disconnect() async
    func openStream() async -> Result<Stream, TransportLayerError>
}
