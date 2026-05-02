//
//  FrameBuilder.swift
//  SiriusKitClientTests
//

import Foundation
@testable import SiriusKitCore

enum FrameBuilder {
    static func serverHelloFrame(
        protocolVersion: SiriusProtocolVersion = .v1_0,
        supportedFeatures: [UUID] = [],
        serverName: String? = "MockServer",
        motd: String? = nil
    ) throws -> SiriusFrame {
        let message = ServerHello(
            protocolVersion: protocolVersion,
            supportedFeatures: supportedFeatures,
            serverName: serverName,
            motd: motd
        )
        let data = try message.serialize()
        return SiriusFrame(opcode: .serverHello, length: UInt32(data.count), data: data)
    }

    static func authChallengeFrame(
        acceptedMethods: [String] = ["password"],
        nonce: Data = Data([0x01, 0x02, 0x03, 0x04]),
        message: String? = nil
    ) throws -> SiriusFrame {
        let msg = AuthChallenge(
            acceptedMethods: acceptedMethods,
            nonce: nonce,
            message: message
        )
        let data = try msg.serialize()
        return SiriusFrame(opcode: .authChallenge, length: UInt32(data.count), data: data)
    }

    static func authResponseFrame(
        sessionID: UUID? = UUID()
    ) throws -> SiriusFrame {
        let message = AuthResponse(sessionID: sessionID)
        let data = try message.serialize()
        return SiriusFrame(opcode: .authResponse, length: UInt32(data.count), data: data)
    }

    static func channelStartResponseFrame(
        success: Bool
    ) throws -> SiriusFrame {
        let message = ChannelStartResponse(success: success)
        let data = try message.serialize()
        return SiriusFrame(opcode: .channelStartResponse, length: UInt32(data.count), data: data)
    }

    static func channelStartRequestFrame(
        featureID: UUID,
        channelID: UUID = UUID(),
        args: [String] = []
    ) throws -> SiriusFrame {
        let message = ChannelStartRequest(
            featureID: featureID,
            channelID: channelID,
            args: args
        )
        let data = try message.serialize()
        return SiriusFrame(opcode: .channelStartRequest, length: UInt32(data.count), data: data)
    }

    static func serverNoticeFrame(
        severity: NoticeSeverity = .fatal,
        code: ServerNoticeCode = ServerNoticeCode(rawValue: 0),
        message: String = "",
        timestamp: UInt64 = 0
    ) throws -> SiriusFrame {
        let msg = ServerNotice(
            severity: severity,
            code: code,
            message: message,
            timestamp: timestamp
        )
        let data = try msg.serialize()
        return SiriusFrame(opcode: .serverNotice, length: UInt32(data.count), data: data)
    }

    static func goodbyeFrame(
        code: ClosureCode = .successful,
        message: String? = nil
    ) throws -> SiriusFrame {
        let msg = Goodbye(code: code, message: message)
        let data = try msg.serialize()
        return SiriusFrame(opcode: .goodbye, length: UInt32(data.count), data: data)
    }
}
