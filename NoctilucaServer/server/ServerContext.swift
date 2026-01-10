//
//  ServerContext.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/7/25.
//

protocol ServerContext {
    var featureProvider: NoctilucaFeatureProvider { get }
    
    var authenticator: Authenticator { get }
    var settings: AppSettings { get }
    
    /// 서버 측 소프트웨어 이름을 반환한다.
    func serverName(withVersion: Bool) -> String
}
