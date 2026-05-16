//
//  RPCHandlerPluginV1.swift
//  NoctilucaPluginKit
//
//  Created by Gyuhwan Park on 5/13/26.
//

import Foundation

public struct RPCResponseCode: RawRepresentable, Sendable, Equatable, Hashable {
    public let rawValue: UInt32
    
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
    
    /// The request completed successfully.
    public static let success = Self(rawValue: 0)

    /// The responder encountered an internal error (uncaught exception, etc.) while executing the operation.
    public static let internalError = Self(rawValue: 1)

    /// One or more `args` elements could not be parsed or validated by the operation.
    public static let invalidArgs = Self(rawValue: 2)

    /// The responder does not recognize `operation`, or the operation is recognized but disabled on this peer.
    public static let notSupported = Self(rawValue: 3)

    /// The caller lacks the privilege required to invoke this operation.
    public static let permissionDenied = Self(rawValue: 4)

    /// The responder timed out while executing the operation. Senders MAY retry, but SHOULD treat repeated timeouts as a transient failure of the operation rather than the channel.
    public static let timeout = Self(rawValue: 5)

    /// Operation-specific error codes occupy the range >= 1000.
    /// Each operation's specification defines its own non-zero codes within this range.
}

public protocol RPCResponse: Sendable {
    
}

public protocol RPCRequest: Sendable {
    var operation: String { get }
    var args: [String] { get }
    
    func resolve(with code: RPCResponseCode) -> RPCResponse
    func resolve(with code: RPCResponseCode, retval: String) -> RPCResponse
}

public protocol RPCHandlerPluginV1: AnyObject, Sendable {
    static var id: String { get }
    static var name: String { get }
    static var description: String { get }
    
    static var authors: [String] { get }
    static var license: SoftwareLicense { get }
    
    static var version: UInt32 { get }
    static var displayVersion: String { get }
    
    /// 이 플러그인이 지원할 RPC 오퍼레이션 목록.
    /// 역방향 도메인 표기 방식 (e.g. `com.example.buy-bananas`) 를 사용하십시오.
    /// - NOTE: `app.noctiluca.*` 네임스페이스는 team unstablers Inc. (teamid XHA76UVA95) 로 서명되지 않으면 사용할 수 없습니다. 다른 아이덴티티로 서명된 경우, 플러그인 자체가 동작하지 않을 수 있습니다.
    /// - NOTE: `sirius.*`, `so.libsirius.*` 네임스페이스는 예약되어 있으며, 현 시점에서는 사용이 금지되어 있습니다. 해당 네임스페이스를 가진 오퍼레이션은 플러그인으로 요청이 라우트되지 않습니다.
    static var supportedOperations: Set<String> { get }
    
    init()
    
    /// RPC 요청을 받았습니다.
    func onRPCRequest(request: RPCRequest) async throws -> RPCResponse
}
