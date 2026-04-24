//
//  ServerNoticeCode.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 12/9/25.
//

import Foundation

public struct ServerNoticeCode: RawRepresentable, Equatable, Hashable, Sendable {
    public typealias RawValue = UInt32

    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    // - MARK: MISC (0x0700 ~ 0x0FFF)

    /// ??? 왜 이딴거 정의해요
    ///
    /// # JACKPOT (0x0777)
    /// 이 코드는 non-normative한 이스터 에그입니다.
    /// 구현체는 이 코드를 무시해도 무방합니다.
    ///
    /// 일부 서버 구현체는 각 접속마다 '복권 추첨'을 수행해, 당첨된 클라이언트에게
    /// 이 코드를 담은 `ServerNotice`를 전달하기도 합니다.
    ///
    /// ## 추첨 방식 (구현 정의)
    /// - 접속이 이루어질 때마다 복권을 긁고 참가시키기
    /// - 서버 틱마다 자동으로 복권을 긁고 참가시키기
    /// - 특정 이벤트(예: N번째 접속)를 계기로 추첨
    /// - ...
    ///
    /// 당첨 확률은 구현에 맡기되, 실제로 당첨되면 놀랄 정도로 낮아야 합니다.
    /// **1/777** 정도를 권장합니다. (숫자 자체가 의미심장하죠?)
    ///
    /// ## 보상 (구현 정의)
    /// - `ServerNotice.message`에 축하 메시지를 담아 보낼 수 있음
    /// - 당첨된 세션에 대해 최우선 스케줄링을 보장해줄 수 있음
    /// - ...
    ///
    /// ## 면책
    /// - 장난입니다. **이스터 에그 목적 외에는 절대 사용하지 마세요.**
    /// - 이 이스터 에그는 엔터프라이즈 환경에서 동작해선 안됩니다. 그 사람들은 진지하니까요.
    public static let jackpot = ServerNoticeCode(rawValue: 0x0777)

    // - MARK: CLIENT FAULT (0x4000 ~ 0x4FFF)

    /// 서버가 미래 버전의 Sirius 프로토콜에 추가되었거나, 아직 지원하지 않는 유형의 메시지를 받았을 때 사용됩니다.
    public static let unsupportedOpcode = ServerNoticeCode(rawValue: 0x4005)

    /// 클라이언트가 서버가 지원하지 않는 인증 방식을 선택했을 때 사용됩니다.
    public static let unsupportedAuthMethod = ServerNoticeCode(rawValue: 0x4006)

    /// `AuthRequest`의 nonce가 직전 `AuthChallenge`의 nonce와 일치하지 않을 때 사용됩니다.
    public static let nonceMismatch = ServerNoticeCode(rawValue: 0x4007)

    /// 상대 피어가 주어진 시간 내에 응답하지 않았습니다.
    public static let timeout = ServerNoticeCode(rawValue: 0x4008)

    /// 인증에 실패했습니다.
    public static let authenticationFailed = ServerNoticeCode(rawValue: 0x4009)

    /// 수신한 프레임의 페이로드 길이가 프로토콜이 정한 상한을 초과했습니다.
    /// 자세한 내용은 프로토콜 introduction의 "FRAME SIZE LIMIT" 섹션을 참조하세요.
    public static let frameTooLarge = ServerNoticeCode(rawValue: 0x400A)

    // - MARK: SERVER FAULT (0x5000 ~ 0x5FFF)

    /// 서버 내부에서 예기치 못한 오류가 발생했을 때 사용됩니다.
    public static let internalServerError = ServerNoticeCode(rawValue: 0x5000)

    /// 서버가 세션 시트를 할당하는 데 실패했습니다.
    /// 보통 자원 부족 또는 최대 동시 세션 수 초과 등의 이유로 발생합니다.
    public static let sessionAllocationFailed = ServerNoticeCode(rawValue: 0x5001)

}
