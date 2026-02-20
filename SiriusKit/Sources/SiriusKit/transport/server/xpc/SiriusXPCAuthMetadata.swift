//
//  SiriusXPCAuthMetadata.swift
//  SiriusKit
//
//  Created by Claude on 2/20/26.
//

import Foundation

/// noctilucad가 MainChannel 핸드셰이크/인증을 완료한 후,
/// NoctilucaServer(Agent)에 전달하는 사전 인증 메타데이터.
///
/// NSSecureCoding을 준수하여 NSXPCConnection을 통해 직렬화/역직렬화된다.
@objc public final class SiriusXPCAuthMetadata: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    // MARK: - Properties

    /// 인증 완료 시 AuthResponse에서 클라이언트에 전송한 세션 ID.
    public let sessionID: UUID

    /// 클라이언트의 에이전트 이름 (ClientHello.agentName).
    public let agentName: String

    /// 클라이언트의 프로토콜 버전 (SiriusProtocolVersion.rawValue).
    public let protocolVersionRaw: UInt32

    /// 원격 클라이언트의 주소 문자열 (예: "192.168.1.100:54321").
    public let remoteAddress: String

    // MARK: - Init

    public init(
        sessionID: UUID,
        agentName: String,
        protocolVersionRaw: UInt32,
        remoteAddress: String
    ) {
        self.sessionID = sessionID
        self.agentName = agentName
        self.protocolVersionRaw = protocolVersionRaw
        self.remoteAddress = remoteAddress
        super.init()
    }

    // MARK: - NSSecureCoding

    private enum CodingKeys {
        static let sessionID = "sessionID"
        static let agentName = "agentName"
        static let protocolVersionRaw = "protocolVersionRaw"
        static let remoteAddress = "remoteAddress"
    }

    public required init?(coder: NSCoder) {
        guard let sessionIDString = coder.decodeObject(of: NSString.self, forKey: CodingKeys.sessionID) as? String,
              let sessionID = UUID(uuidString: sessionIDString)
        else {
            return nil
        }

        guard let agentName = coder.decodeObject(of: NSString.self, forKey: CodingKeys.agentName) as? String else {
            return nil
        }

        guard let remoteAddress = coder.decodeObject(of: NSString.self, forKey: CodingKeys.remoteAddress) as? String else {
            return nil
        }

        self.sessionID = sessionID
        self.agentName = agentName
        self.protocolVersionRaw = UInt32(coder.decodeInt32(forKey: CodingKeys.protocolVersionRaw))
        self.remoteAddress = remoteAddress
        super.init()
    }

    public func encode(with coder: NSCoder) {
        coder.encode(sessionID.uuidString as NSString, forKey: CodingKeys.sessionID)
        coder.encode(agentName as NSString, forKey: CodingKeys.agentName)
        coder.encode(Int32(protocolVersionRaw), forKey: CodingKeys.protocolVersionRaw)
        coder.encode(remoteAddress as NSString, forKey: CodingKeys.remoteAddress)
    }

    // MARK: - CustomStringConvertible

    public override var description: String {
        "SiriusXPCAuthMetadata(sessionID: \(sessionID), agentName: \(agentName), protocol: 0x\(String(protocolVersionRaw, radix: 16)), remote: \(remoteAddress))"
    }
}
