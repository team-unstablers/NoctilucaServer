//
//  SiriusServerBuilder.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/24/25.
//

import Foundation
import Network
import SiriusKitCore

public enum SiriusServerBuilderError: Error {
    case invalidConfiguration(String)
}

public struct SiriusServerBuilder {
    public enum TransportProtocol {
        case quic(implementation: String,
                  port: UInt16,
                  identity: (any QUICServerIdentity))

        func buildServerTransport() -> ServerRoleRootTransport {
            switch self {
            case .quic(let implementation, let port, let identity):
                let port = NWEndpoint.Port(rawValue: port)!
                
                switch implementation {
                case TransportLayerImplementation.appleQuic.identifier:
                    return ServerRoleQUICRootTransport(port: port, using: identity)
                case TransportLayerImplementation.msQuic.identifier:
                    return ServerRoleMsQuicRootTransport(port: port.rawValue, using: identity)
                default:
                    // WARN: unsupported implementation type
                    return ServerRoleMsQuicRootTransport(port: port.rawValue, using: identity)
                }

            }
        }
    }

    private(set) var featureProvider: (any FeatureProvider)?
    private(set) var transportProtocol: TransportProtocol?

    private(set) var extraConfigurations: [String: String] = [:]

    public init() {

    }

    public func useFeatureProvider(_ featureProvider: any FeatureProvider) -> Self {
        var this = self
        this.featureProvider = featureProvider

        return this
    }

    // useFeatureProvider 대신 .registerFeature(..., implementation: ...) 같은건 어떄?

    public func useTransportProtocol(_ transportProtocol: TransportProtocol) -> Self {
        var this = self
        this.transportProtocol = transportProtocol

        return this
    }

    // TODO: maximum connections, idle timeout, etc.

    public func withExtraConfiguration(_ value: String, forKey key: String) -> Self {
        var this = self
        this.extraConfigurations[key] = value

        return this
    }

    internal func validate() -> Result<Void, SiriusServerBuilderError> {
        guard featureProvider != nil else {
            return .failure(.invalidConfiguration("Feature provider is not set."))
        }

        guard transportProtocol != nil else {
            return .failure(.invalidConfiguration("Transport protocol is not set."))
        }

        return .success(())
    }

    public func build() -> Result<SiriusServer, SiriusServerBuilderError> {
        let validationResult = self.validate()

        if case .failure(let error) = validationResult {
            return .failure(error)
        }

        let serverTransport = transportProtocol!.buildServerTransport()

        let server = SiriusServer(
            serverTransport: serverTransport,
            featureProvider: featureProvider!
        )

        return .success(server)
    }

}
