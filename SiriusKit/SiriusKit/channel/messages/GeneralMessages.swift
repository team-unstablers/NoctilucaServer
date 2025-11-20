//
//  GeneralMessages.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/20/25.
//

import Foundation

extension MessageOpcode {
    static let serverNotice: MessageOpcode = MessageOpcode(rawValue: 0x0001)
    static let clientHello: MessageOpcode = MessageOpcode(rawValue: 0x0002)
    static let serverHello: MessageOpcode = MessageOpcode(rawValue: 0x0003)
}

public struct ServerHello: SiriusMessage {
    typealias ProtobufMessage = Sirius_Msgdef_ServerHello
    
    public let protocolVersion: SiriusProtocolVersion
    public let supportedFeatures: [SiriusFeature]
    
    public let serverName: String?
    public let motd: String?
    
    init(protocolVersion: SiriusProtocolVersion, supportedFeatures: [SiriusFeature], serverName: String?, motd: String?) {
        self.protocolVersion = protocolVersion
        self.supportedFeatures = supportedFeatures
        self.serverName = serverName
        self.motd = motd
    }
    
    init(from protobufMessage: Sirius_Msgdef_ServerHello) throws {
        self.protocolVersion = SiriusProtocolVersion(rawValue: protobufMessage.protocolVersion)
        self.supportedFeatures = protobufMessage.supportedFeatures.map {
            SiriusFeature(rawValue: UUID(msgdef: $0))
        }
        self.serverName = protobufMessage.hasServerName ? protobufMessage.serverName : nil
        self.motd = protobufMessage.hasMotd ? protobufMessage.motd : nil
    }
    
    func toProtobufMessage() -> ProtobufMessage {
        var message = ProtobufMessage()
        
        message.protocolVersion = self.protocolVersion.rawValue
        message.supportedFeatures = self.supportedFeatures.map { $0.rawValue.asMsgDef() }
        if let serverName = self.serverName {
            message.serverName = serverName
        }
        if let motd = self.motd {
            message.motd = motd
        }
        
        return message
    }
}


