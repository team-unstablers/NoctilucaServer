//
//  ServerNoticeCode.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 12/9/25.
//

import Foundation

public struct ServerNoticeCode: RawRepresentable, Equatable, Hashable {
    public typealias RawValue = UInt32
    
    public let rawValue: UInt32
    
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
    
    // - MARK: MISC
    
    /// ??? 왜 이딴거 정의해요
    ///
    /// # JACKPOT (0x0777)
    /// - 일부 서버 구현체는 각 접속마다 '복권 추첨'을 수행하는 경우가 있습니다. (optional)
    /// - '복권 추첨'의 유형은 다양합니다.
    ///     - 특정 틱마다 자동으로 복권을 긁고 참가시키거나,
    ///     - 접속이 이루어질 때마다 복권을 긁고 참가시키거나,
    ///     - ...
    /// - 클라이언트는 복권에 당첨되면 서버가 제공하는 특별한 혜택을 받을 수 있습니다.
    ///     - 혜택은 서버 구현체마다 다릅니다.
    ///
    /// - ... 장난입니다. **이스터 에그 목적 외에는 절대 사용하지 마세요.**
    /// - 이 이스터 에그는 엔터프라이즈 환경에서 동작해선 안됩니다. 그 사람들은 진지하니까요.
    public static let jackpot = ServerNoticeCode(rawValue: 0x0777)
    
    // - MARK: CLIENT FAULT (0x4000 ~ 0x4FFF)
    
    /// 서버가 미래 버전의 Sirius 프로토콜에 추가되었거나, 아직 지원하지 않는 유형의 메시지를 받았을 때 사용됩니다.
    public static let unsupportedOpcode = ServerNoticeCode(rawValue: 0x4005)
    public static let unsupportedAuthMethod = ServerNoticeCode(rawValue: 0x4006)
    public static let nonceDismatch = ServerNoticeCode(rawValue: 0x4007)

    /// 클라이언트가 주어진 시간 내에 응답하지 않았습니다.
    public static let timeout = ServerNoticeCode(rawValue: 0x4008)
    
    // - MARK: SERVER FAULT (0x5000 ~ 0x5FFF)
    
    /// 서버 내부에서 예기치 못한 오류가 발생했을 때 사용됩니다.
    public static let internalServerError = ServerNoticeCode(rawValue: 0x5000)
    
}
