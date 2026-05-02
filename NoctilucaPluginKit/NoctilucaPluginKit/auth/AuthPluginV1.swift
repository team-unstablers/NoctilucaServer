//
//  AuthPlugin.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/4/25.
//


import Foundation

public protocol AuthPluginV1: Actor {
    static var id: String { get }
    static var name: String { get }
    static var description: String { get }
    
    static var authors: [String] { get }
    static var license: SoftwareLicense { get }

    static var version: UInt32 { get }
    static var displayVersion: String { get }

    static var supportedMethods: Set<AuthMethod> { get }
    
    /// 플러그인이 현재 하나 이상의 인증 허용 항목을 가지고 있는지 여부를 나타냅니다.
    var hasAllowedEntries: Bool { get }

    /// 플러그인에게 인증 허용 항목을 추가하도록 요청합니다.
    func allow(_ entry: AuthEntry) async throws
    /// 플러그인에게 인증 허용 항목을 제거하도록 요청합니다.
    func deny(_ entry: AuthEntry) async throws
    
    /// 플러그인에게 주어진 인증 방법과 페이로드를 사용하여 인증을 시도하도록 요청합니다.
    func authenticate(using method: AuthMethod, payload: borrowing Data, nonce: Data) async -> Result<uid_t, AuthError>
}
