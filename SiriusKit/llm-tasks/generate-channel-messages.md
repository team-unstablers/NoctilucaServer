<agent-task id="generate-channel-message">
    <objective>
        # Channel 메시지 정의 업데이트 하기
        
        - `dependencies/libsirius/msgdef/` 아래의 Protobuf 3 메시지 정의 파일들을 검토하고, 새로운 기능 추가나 기존 기능 변경에 따라 필요한 Channel 메시지들을 생성하거나 수정합니다.
    </objective>
    
    <tasks>
        1. Protobuf 3 메시지 정의 파일들을 분석하고, `SiriusKit/channel/messages` 디렉토리에 정의된 Channel 메시지들과 비교합니다.
        2. 새로운 기능 추가나 기존 기능 변경에 따라 필요한 Channel 메시지 / inner objects들을 추가하거나 수정합니다.
            - 각 Channel 메시지 / inner objects들은 protoc-gen-swift를 통해 자동 생성된 Swift 코드로 상호 변환될 수 있어야 합니다.
        3. 변경된 메시지 정의에 따라 관련된 문서나 주석도 함께 업데이트합니다.
    </tasks>
    
    <code id="expected-output" lang="swift">
    import Foundation
    import SwiftProtobuf
    
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
    </code>
    
    <see-also important>
        - `SiriusKit/autogen/msgdef` - protoc-gen-swift를 통해 자동 생성된 Swift 코드들이 위치한 디렉토리입니다.
    </see-also>
    
    <note important>
        - 메시지들은 각각 Opcode가 할당되어 있습니다.
        <code lang="protobuf3">
        /// opcode = 0x0001
        message ServerNotice {
          NoticeSeverity severity = 1;
          fixed32 code = 2;
          string message = 3;
          fixed64 timestamp = 4;
        }
        </code>
        
        - 만약 작업 중 어떻게 진행해야 할지 확실하지 않은 부분이 있다면, 반드시 사용자에게 질문하여 명확히 한 후에 작업을 진행하세요.
    </note>
    
</agent-task>
