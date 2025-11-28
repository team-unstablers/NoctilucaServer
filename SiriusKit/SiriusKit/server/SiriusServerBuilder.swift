//
//  SiriusServerBuilder.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/24/25.
//

import Foundation
import Network

public enum SiriusServerBuilderError: Error {
    case invalidConfiguration(String)
}

public struct SiriusServerBuilder {
    public enum TransportProtocol {
        case quic(port: UInt16,
                  identitySource: QUICServerIdentitySource)
        
        func buildServerTransport() -> ServerRoleRootTransport {
            switch self {
            case .quic(let port, let identitySource):
                let port = NWEndpoint.Port(rawValue: port)!
                let identity = identitySource.build()
                
                return ServerRoleQUICRootTransport(port: port, using: identity)
            }
        }
    }
    
    private(set) var featureProvider: (any FeatureProvider)?
    private(set) var transportProtocol: TransportProtocol?
    
    private(set) var extraConfigurations: [String: String] = [:]
    
    public init() {
        
    }
    
    public func useFeatureProvider(_ featureProvider: any FeatureProvider) -> Self {
        var _self = self
        _self.featureProvider = featureProvider
        
        return _self
    }
    
    // useFeatureProvider 대신 .registerFeature(..., implementation: ...) 같은건 어떄?
    
    public func useTransportProtocol(_ transportProtocol: TransportProtocol) -> Self {
        var _self = self
        _self.transportProtocol = transportProtocol
        
        return self
    }
    
    // TODO: maximum connections, idle timeout, etc.
    
    public func withExtraConfiguration(_ value: String, forKey key: String) -> Self {
        var _self = self
        _self.extraConfigurations[key] = value
        
        return _self
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
