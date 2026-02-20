//
//  SiriusXPCProtocol.swift
//  SiriusKit
//
//  Created by Claude on 2/20/26.
//

import Foundation

// MARK: - Daemon → Agent (데몬이 에이전트를 호출하는 인터페이스)

/// noctilucad가 NoctilucaServer(Agent)에게 사전 인증된 클라이언트 연결 및 스트림 이벤트를 전달하기 위한 인터페이스.
///
/// 하나의 NSXPCConnection 위에서 여러 클라이언트를 clientID/streamID로 식별하여 멀티플렉싱한다.
@objc
public protocol SiriusAgentXPCInterface {

    /// 사전 인증된 클라이언트 연결을 에이전트에 전달한다.
    ///
    /// 데몬이 QUIC 연결을 수락하고 MainChannel 핸드셰이크/인증을 완료한 후 호출된다.
    /// - Parameters:
    ///   - clientID: 프록시 클라이언트 식별자 (ServerRoleClientTransportIdentifier와 대응)
    ///   - metadata: 인증 결과 메타데이터 (세션 ID, 클라이언트 정보, 원격 주소)
    ///   - reply: 에이전트가 클라이언트를 수락했는지 여부
    func acceptPreAuthenticatedClient(
        _ clientID: NSUUID,
        metadata: SiriusXPCAuthMetadata,
        reply: @escaping (Bool) -> Void
    )

    /// 원격 클라이언트가 새 스트림을 열었음을 에이전트에 전달한다.
    ///
    /// - Parameters:
    ///   - clientID: 해당 클라이언트 식별자
    ///   - streamID: 새 스트림 식별자 (StreamIdentifier와 대응)
    ///   - reply: 에이전트가 스트림을 수락했는지 여부
    func clientDidOpenRemoteStream(
        _ clientID: NSUUID,
        streamID: NSUUID,
        reply: @escaping (Bool) -> Void
    )

    /// 스트림으로 수신된 데이터를 에이전트에 전달한다.
    ///
    /// 데이터는 Sirius 프레임 헤더(opcode 2B + length 4B)를 포함한 raw bytes이다.
    /// 에이전트의 XPCStream은 SiriusFrameStreamDecoder를 사용하여 이 데이터를 프레임 단위로 파싱한다.
    ///
    /// Reply가 없는 oneway 호출이다 (수신 확인 불필요, 최대 처리량 우선).
    func clientDidReceiveStreamData(
        _ clientID: NSUUID,
        streamID: NSUUID,
        data: NSData
    )

    /// 스트림이 종료되었음을 에이전트에 알린다.
    func clientStreamDidClose(
        _ clientID: NSUUID,
        streamID: NSUUID
    )

    /// 스트림에서 에러가 발생했음을 에이전트에 알린다.
    func clientStreamDidError(
        _ clientID: NSUUID,
        streamID: NSUUID,
        errorDescription: NSString
    )

    /// 클라이언트 연결이 종료되었음을 에이전트에 알린다.
    func clientDidDisconnect(_ clientID: NSUUID)
}

// MARK: - ServiceClass XPC Serialization

public extension ServiceClass {
    /// XPC 전송을 위해 UInt8로 변환한다.
    var xpcRawValue: UInt8 {
        switch self {
        case .userInput: return 0
        case .realtimeVideo: return 1
        case .realtimeAudio: return 2
        case .signaling: return 3
        case .background: return 4
        }
    }

    /// XPC에서 수신한 UInt8 값으로 ServiceClass를 생성한다.
    init?(xpcRawValue: UInt8) {
        switch xpcRawValue {
        case 0: self = .userInput
        case 1: self = .realtimeVideo
        case 2: self = .realtimeAudio
        case 3: self = .signaling
        case 4: self = .background
        default: return nil
        }
    }
}

// MARK: - Agent → Daemon (에이전트가 데몬을 호출하는 인터페이스)

/// NoctilucaServer(Agent)가 noctilucad에 자신을 등록(announce)하고,
/// 스트림 데이터를 클라이언트로 전송하기 위한 인터페이스.
@objc
public protocol SiriusDaemonXPCInterface {

    // MARK: Announcement

    /// 에이전트가 시동되었음을 데몬에 알린다 (announce).
    ///
    /// - Parameters:
    ///   - uid: 에이전트를 실행 중인 사용자의 UID. loginwindow의 경우 0.
    ///   - reply: 등록 성공 여부
    func agentDidStartup(uid: uid_t, reply: @escaping (Bool) -> Void)

    /// 에이전트가 종료됨을 데몬에 알린다 (depart).
    func agentWillShutdown(reply: @escaping () -> Void)

    // MARK: Stream Operations

    /// 서버(에이전트) 측에서 새 스트림을 열도록 데몬에 요청한다.
    ///
    /// 데몬은 실제 QUIC 트랜스포트에서 새 스트림을 생성하고, 해당 스트림의 프록시를 설정한다.
    /// - Parameters:
    ///   - clientID: 대상 클라이언트 식별자
    ///   - streamID: 에이전트가 할당한 새 스트림 식별자
    ///   - reply: 스트림 생성 성공 여부
    func openStream(
        clientID: NSUUID,
        streamID: NSUUID,
        reply: @escaping (Bool) -> Void
    )

    /// 에이전트가 스트림에 데이터를 쓰도록 데몬에 요청한다.
    ///
    /// 데이터는 Sirius 프레임 헤더를 포함한 raw bytes이다.
    /// 데몬은 이 데이터를 실제 QUIC 스트림에 기록한다.
    /// - Parameters:
    ///   - clientID: 대상 클라이언트 식별자
    ///   - streamID: 대상 스트림 식별자
    ///   - data: 기록할 데이터 (프레임 헤더 포함)
    ///   - reply: (bytesWritten, errorDescription?) 튜플
    func writeStreamData(
        clientID: NSUUID,
        streamID: NSUUID,
        data: NSData,
        reply: @escaping (UInt32, NSString?) -> Void
    )

    /// 에이전트가 스트림 닫기를 데몬에 요청한다.
    func closeStream(
        clientID: NSUUID,
        streamID: NSUUID,
        reply: @escaping (Bool) -> Void
    )

    /// 에이전트가 스트림의 서비스 클래스(우선순위)를 설정하도록 데몬에 요청한다.
    ///
    /// 데몬은 실제 QUIC 스트림에 setServiceClass를 호출한다.
    func setStreamServiceClass(
        clientID: NSUUID,
        streamID: NSUUID,
        rawValue: UInt8,
        reply: @escaping (Bool) -> Void
    )

    /// 에이전트가 클라이언트 연결 끊기를 데몬에 요청한다.
    func disconnectClient(
        _ clientID: NSUUID,
        reply: @escaping (Bool) -> Void
    )
}

// MARK: - NSXPCInterface Factories

// MARK: - NSXPCInterface Factories

/// NSXPCInterface 생성 시 커스텀 타입 화이트리스팅을 수행하는 팩토리 함수.
public func createSiriusAgentXPCInterface() -> NSXPCInterface {
    let interface = NSXPCInterface(with: SiriusAgentXPCInterface.self)

    // Swift에서 Class metatype을 Set<AnyHashable>에 넣으려면 NSSet 경유가 필요하다.
    let metadataClasses = NSSet(array: [
        SiriusXPCAuthMetadata.self,
        NSUUID.self,
        NSString.self,
        NSData.self,
        NSNumber.self,
        // swiftlint:disable:next force_cast
    ] as [AnyObject]) as! Set<AnyHashable>

    // acceptPreAuthenticatedClient의 metadata 파라미터 (index 1)에 SiriusXPCAuthMetadata 허용
    interface.setClasses(
        metadataClasses,
        for: #selector(SiriusAgentXPCInterface.acceptPreAuthenticatedClient(_:metadata:reply:)),
        argumentIndex: 1,
        ofReply: false
    )

    return interface
}

public func createSiriusDaemonXPCInterface() -> NSXPCInterface {
    let interface = NSXPCInterface(with: SiriusDaemonXPCInterface.self)
    return interface
}
