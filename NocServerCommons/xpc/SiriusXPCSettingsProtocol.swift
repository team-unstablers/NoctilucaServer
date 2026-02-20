//
//  SiriusXPCSettingsProtocol.swift
//  NocServerCommons
//
//  Created by Gyuhwan Park on 2/20/26.
//

import Foundation

/// noctilucad 설정 서비스의 Mach 서비스 이름.
public let kNoctilucaSettingsMachServiceName = "pl.unstabler.noctiluca.server.noctilucad.settings"

// MARK: - Agent → Daemon (설정 읽기/쓰기)

/// NoctilucaServer(Agent)가 noctilucad의 DaemonSettings를 읽고 쓰기 위한 XPC 인터페이스.
///
/// 기존 트랜스포트 XPC(SiriusDaemonXPCInterface)와는 별도의 Mach 서비스로 운영되며,
/// 단방향(Agent → Daemon) 요청-응답 방식으로 동작한다.
@objc
public protocol SiriusDaemonSettingsXPCInterface {

    // MARK: General Settings

    /// DaemonSettings 전체를 JSON(NSData)으로 조회한다.
    ///
    /// DaemonSettings의 Codable 인코딩을 사용하므로,
    /// Security.allowedEntries는 CodingKeys에서 제외되어 자연스럽게 반환되지 않는다.
    ///
    /// - Parameter reply: (JSON data, error description) 튜플
    func getSettings(reply: @escaping (NSData?, NSString?) -> Void)

    /// DaemonSettings 전체를 JSON(NSData)으로 업데이트한다.
    ///
    /// 데몬은 수신된 JSON을 디코딩한 후, 기존 Security.allowedEntries를 보존하여 저장한다.
    /// AuthEntry 변경은 이 API가 아닌 전용 AuthEntry CRUD API를 사용해야 한다.
    ///
    /// - Parameters:
    ///   - settingsData: JSON으로 인코딩된 DaemonSettings
    ///   - reply: (success, error description) 튜플
    func updateSettings(_ settingsData: NSData, reply: @escaping (Bool, NSString?) -> Void)

    // MARK: Auth Entry CRUD

    /// 등록된 모든 AuthEntry를 redacted 형태로 조회한다.
    ///
    /// 반환되는 배열의 각 원소는 SiriusXPCRedactedAuthEntry이며,
    /// AuthEntry.data(해시, 키 등 보안 데이터)는 포함되지 않는다.
    ///
    /// - Parameter reply: (NSArray<SiriusXPCRedactedAuthEntry>?, error description) 튜플
    func getAuthEntries(reply: @escaping (NSArray?, NSString?) -> Void)

    /// 새 AuthEntry를 추가한다.
    ///
    /// 데몬은 method에 따라 credential을 해싱(e.g. SHA-512 + bcrypt)한 후 Keychain에 저장한다.
    /// 에이전트는 평문 credential을 전달하면 된다.
    ///
    /// - Parameters:
    ///   - methodRawValue: AuthMethod.rawValue (e.g. "app.noctiluca.server.auth.simple-password")
    ///   - identifier: 엔트리 식별자
    ///   - credential: 평문 credential 데이터
    ///   - reply: (success, error description) 튜플
    func addAuthEntry(
        methodRawValue: NSString,
        identifier: NSString,
        credential: NSData,
        reply: @escaping (Bool, NSString?) -> Void
    )

    /// AuthEntry를 제거한다.
    ///
    /// method + identifier 조합으로 대상을 식별하여 제거한다.
    ///
    /// - Parameters:
    ///   - methodRawValue: AuthMethod.rawValue
    ///   - identifier: 엔트리 식별자
    ///   - reply: (success, error description) 튜플
    func removeAuthEntry(
        methodRawValue: NSString,
        identifier: NSString,
        reply: @escaping (Bool, NSString?) -> Void
    )
}

// MARK: - NSXPCInterface Factory

/// SiriusDaemonSettingsXPCInterface에 대한 NSXPCInterface를 생성한다.
///
/// getAuthEntries reply의 NSArray에 SiriusXPCRedactedAuthEntry 타입을 화이트리스트 등록한다.
public func createSiriusDaemonSettingsXPCInterface() -> NSXPCInterface {
    let interface = NSXPCInterface(with: SiriusDaemonSettingsXPCInterface.self)

    let authEntryClasses = NSSet(array: [
        SiriusXPCRedactedAuthEntry.self,
        NSArray.self,
        NSString.self,
        NSData.self,
        NSNumber.self,
        // swiftlint:disable:next force_cast
    ] as [AnyObject]) as! Set<AnyHashable>

    // getAuthEntries reply의 첫 번째 인자 (index 0)에 RedactedAuthEntry 배열 허용
    interface.setClasses(
        authEntryClasses,
        for: #selector(SiriusDaemonSettingsXPCInterface.getAuthEntries(reply:)),
        argumentIndex: 0,
        ofReply: true
    )

    return interface
}
