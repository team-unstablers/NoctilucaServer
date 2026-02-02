//
//  SiriusClientBuilder.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/29/25.
//

import Foundation
import Network

public enum SiriusClientBuilderError: Error {
    case invalidConfiguration(String)
}

public struct SiriusClientBuilder {
    public enum TransportProtocol {
        case quic(host: String, port: UInt16)
        
        func buildTransport() -> any ClientRoleTransport {
            switch self {
            case .quic(let host, let port):
                return ClientRoleQUICTransport(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)
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
    
    internal func validate() -> Result<Void, SiriusClientBuilderError> {
        guard featureProvider != nil else {
            return .failure(.invalidConfiguration("Feature provider is not set."))
        }
        
        guard transportProtocol != nil else {
            return .failure(.invalidConfiguration("Transport protocol is not set."))
        }
        
        return .success(())
    }
    
    
    public func build() -> Result<SiriusClient, SiriusClientBuilderError> {
        let validationResult = self.validate()
        
        if case .failure(let error) = validationResult {
            return .failure(error)
        }
        
        let transport = transportProtocol!.buildTransport()
        
        let client = SiriusClient(
            transport: transport,
            featureProvider: featureProvider!
        )
        
        return .success(client)
    }
}
