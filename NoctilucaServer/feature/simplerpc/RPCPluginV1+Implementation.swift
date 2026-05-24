//
//  RPCPluginV1+Implementation.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 5/22/26.
//

import Foundation

import SiriusKit

import NoctilucaPluginKit

extension RPCResponseCode {
    /// `SimpleRPCErrorCode` 로부터 매핑합니다. wire 상에서는 UInt32 rawValue 가
    /// 1:1 매핑되며, 1000 이상 영역은 오퍼레이션 정의 코드입니다.
    init(_ siriusCode: SimpleRPCErrorCode) {
        self.init(rawValue: siriusCode.rawValue)
    }

    /// `SimpleRPCErrorCode` 로 평탄화합니다.
    func toSiriusErrorCode() -> SimpleRPCErrorCode {
        return SimpleRPCErrorCode(rawValue: self.rawValue)
    }
}

extension RPCResult {
    /// 채널 레이어로부터 받은 `requestId` 와 결합해 wire 응답을 합성합니다.
    func toSiriusResponse(requestId: UUID) -> SimpleRPCResponse {
        return SimpleRPCResponse(
            requestId: requestId,
            code: self.code.toSiriusErrorCode(),
            retval: self.retval
        )
    }
}
