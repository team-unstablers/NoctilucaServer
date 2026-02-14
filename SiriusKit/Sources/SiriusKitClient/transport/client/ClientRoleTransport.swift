//
//  ClientRoleTransport.swift
//  SiriusKit
//
//  Created by Coding Assistant on 03/01/25.
//

import Foundation
import Security
import SiriusKitCore

typealias ClientRoleTransportIdentifier = TransportLayerIdentifier

/// 트랜스포트 계층에서 발생하는 에러
public enum ClientTransportError: LocalizedError, Sendable {
    /// 서버 인증서 검증에 실패했습니다.
    case certificateValidationFailed
    /// 서버가 연결을 거부했습니다.
    case connectionRefused
    /// 연결 시간이 초과되었습니다.
    case connectionTimeout
    /// TLS 핸드셰이크에 실패했습니다.
    case handshakeFailure
    /// 서버에 연결할 수 없습니다.
    case unreachable
    /// 연결에 실패했습니다.
    case connectionFailed(description: String)

    public var errorDescription: String? {
        switch self {
        case .certificateValidationFailed:
            return "서버 인증서 검증에 실패했습니다."
        case .connectionRefused:
            return "서버가 연결을 거부했습니다."
        case .connectionTimeout:
            return "연결 시간이 초과되었습니다."
        case .handshakeFailure:
            return "TLS 핸드셰이크에 실패했습니다."
        case .unreachable:
            return "서버에 연결할 수 없습니다."
        case .connectionFailed(let description):
            return "연결에 실패했습니다: \(description)"
        }
    }
}

/// 서버 아이덴티티 타입
public enum ServerIdentity {
    /// SSL 인증서
    case sslCertificate(leaf: SecCertificate, chain: [SecCertificate])
    
    /// 추후 Sirius-over-SSH같은게 나올 일이 있을진 모르겠지만 만약 그렇다면, 무언가 추가되겠지요..
}

public extension ServerIdentity {
    func fingerprint() throws -> Data {
        switch self {
        case .sslCertificate(let leaf, _):
            guard let fingerprint = leaf.extractFingerprint() else {
                // 진짜 만능이다 이 에러 (전혀 아님, 고쳐야됨)
                throw SRSecurityError.operationFailed(error: nil)
            }
            
            return fingerprint
        }
    }
}

/// 서버 아이덴티티 검증 정책
public enum ServerIdentityValidationPolicy: Equatable {
    /// 시스템의 트러스트 스토어를 기준으로만 검사합니다.
    case systemOnly
    
    /// 시스템의 트러스트 스토어를 절대 사용하지 않고, 항상 앱의 검증 블록만 호출합니다.
    /// 권장하지 않음: OS의 트러스트 스토어가 너무 낡아 버렸거나 오염되어 있는 경우에 사용하십시오.
    case appValidationOnly(ServerIdentityValidationBlock)
    
    /// 시스템의 트러스트 스토어를 기준으로 우선 검사하고, 그 다음에 앱의 검증 블록을 호출합니다.
    /// 기본값으로의 사용을 권장합니다.
    case systemAndAppValidation(ServerIdentityValidationBlock)
    
    /// 모든 아이덴티티를 허용합니다. 단, 유효성 검사는 수행합니다.
    case dangerouslyAllowAlways
    
    /// 모든 아이덴티티를 허용합니다. 유효성 검사도 수행하지 않습니다.
    case dangerouslyAllowAlwaysWithoutValidation
    
    public static func ==(lhs: ServerIdentityValidationPolicy, rhs: ServerIdentityValidationPolicy) -> Bool {
        switch (lhs, rhs) {
        case (.systemOnly, .systemOnly):
            return true
        case (.appValidationOnly(_), .appValidationOnly(_)):
            return true
        case (.systemAndAppValidation(_), .systemAndAppValidation(_)):
            return true
        case (.dangerouslyAllowAlways, .dangerouslyAllowAlways):
            return true
        case (.dangerouslyAllowAlwaysWithoutValidation, .dangerouslyAllowAlwaysWithoutValidation):
            return true
        default:
            return false
        }
    }
}

extension ServerIdentityValidationPolicy {
    var requiresSystemValidation: Bool {
        switch self {
        case .systemOnly, .systemAndAppValidation(_), .dangerouslyAllowAlways:
            return true
        default:
            return false
        }
    }
    
    var requiresAppValidation: Bool {
        switch self {
        case .appValidationOnly(_), .systemAndAppValidation(_):
            return true
        default:
            return false
        }
    }
    
    var validationBlock: ServerIdentityValidationBlock? {
        switch self {
        case .appValidationOnly(let block), .systemAndAppValidation(let block):
            return block
        default:
            return nil
        }
    }
    
}

public enum ServerIdentityTrustDecision {
    /// 이 아이덴티티를 신뢰합니다.
    case allow
    
    /// 이 아이덴티티를 신뢰하지 않습니다.
    case deny
}

/// 어플리케이션 레이어에서의 검증 블록.
/// NOTE: 이 검증 블록은 **최대한 빠르게** 처리되어야 합니다.
///       단, 위 문장은 'UI 표시를 하지 말라'라는 의미가 아닙니다. UI 표시 (사용자 동의) 등을 받아야 하는 경우,
///       우선 .deny로 접속을 끊고, 디시전을 받은 뒤 재접속 시 디시전 결과를 넘기는 식의 사용을 권장합니다.
public typealias ServerIdentityValidationBlock = @Sendable (ServerIdentity) -> ServerIdentityTrustDecision


struct NegotiationRequest {
    let supportedAlpns: [String]
    let allowZeroRtt: Bool
}

struct NegotiationResponse {
    let selectedAlpn: String
    let enableZeroRtt: Bool
}

protocol ClientRoleTransportDelegate: AnyObject {
    func clientTransportDidEstablishConnection(_ transport: any ClientRoleTransport) async
    func clientTransportDidOpenRemoteStream(_ transport: any ClientRoleTransport, stream: SiriusKitCore.Stream) async throws
    func clientTransportDidClose(_ transport: any ClientRoleTransport) async
    func clientTransport(_ transport: any ClientRoleTransport, didEncounterError error: any Error) async

    func clientTransport(_ transport: any ClientRoleTransport, didReceiveNegotiationRequest request: NegotiationRequest, responder: @escaping (NegotiationResponse) -> Void)
}

protocol ClientRoleTransport: TransportLayer, Hashable where ID == ClientRoleTransportIdentifier {
    var delegate: ClientRoleTransportDelegate? { get set }
    
    var endpoint: SREndpoint { get }
    
    /// 서버에서 announce한 아이덴티티 정보.
    /// 접속 전 / handshake 전에는 nil입니다.
    var identity: ServerIdentity? { get }
    
    /// 서버 아이덴티티 검증 정책
    var identityValidationPolicy: ServerIdentityValidationPolicy { get set }

    func connect() async throws
}

extension ClientRoleTransport {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
