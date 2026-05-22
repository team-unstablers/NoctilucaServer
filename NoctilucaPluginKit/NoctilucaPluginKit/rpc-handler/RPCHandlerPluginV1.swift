//
//  RPCHandlerPluginV1.swift
//  NoctilucaPluginKit
//
//  Created by Gyuhwan Park on 5/13/26.
//

import Foundation

public struct RPCResponseCode: RawRepresentable, Codable, Sendable, Equatable, Hashable {
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

/// RPC 핸들러의 단일 요청 처리 결과.
///
/// `resolve()` 같은 메서드는 wire 너머로 전달할 수 없기 때문에, 플러그인은
/// 응답 코드와 (선택적) 반환 문자열만을 담아 결과를 반환합니다. 실제 wire
/// 메시지 합성(requestId 매핑 등)은 host 측 어댑터/채널 레이어가 담당합니다.
public struct RPCResult: Codable, Sendable, Equatable {
    public let code: RPCResponseCode
    public let retval: String?

    public init(code: RPCResponseCode, retval: String? = nil) {
        self.code = code
        self.retval = retval
    }

    /// 성공 응답. `retval` 은 오퍼레이션이 정의한 의미를 갖습니다.
    public static func success(_ retval: String? = nil) -> Self {
        Self(code: .success, retval: retval)
    }

    /// 실패 응답. `code` 가 `.success` 가 아닌 경우에 사용하며, 실패 상황에서도
    /// 진단용 메시지를 `retval` 로 첨부할 수 있습니다.
    public static func failure(_ code: RPCResponseCode, retval: String? = nil) -> Self {
        Self(code: code, retval: retval)
    }
}

public protocol RPCHandlerPluginV1: AnyObject, Sendable {
    static var id: String { get }

    /// 이 플러그인이 지원할 RPC 오퍼레이션 목록.
    /// 역방향 도메인 표기 방식 (e.g. `com.example.buy-bananas`) 를 사용하십시오.
    /// - NOTE: `app.noctiluca.*` 네임스페이스는 team unstablers Inc. (teamid XHA76UVA95) 로 서명되지 않으면 사용할 수 없습니다. 다른 아이덴티티로 서명된 경우, 플러그인 자체가 동작하지 않을 수 있습니다.
    /// - NOTE: `sirius.*`, `so.libsirius.*` 네임스페이스는 예약되어 있으며, 현 시점에서는 사용이 금지되어 있습니다. 해당 네임스페이스를 가진 오퍼레이션은 플러그인으로 요청이 라우트되지 않습니다.
    static var supportedOperations: Set<String> { get }

    init()

    /// RPC 요청을 받았습니다.
    ///
    /// - Parameters:
    ///   - operation: 요청된 오퍼레이션 식별자. `supportedOperations` 중 하나입니다.
    ///   - args: 오퍼레이션 인자. 각 오퍼레이션 명세가 정의한 의미/순서를 따릅니다.
    /// - Returns: 응답 코드와 (선택적) 반환 문자열을 담은 `RPCResult`.
    func onRPCRequest(operation: String, args: [String]) async throws -> RPCResult
}
