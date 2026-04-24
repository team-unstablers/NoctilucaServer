//
//  NoctilucaClientSession+Notice.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/9/25.
//

import Foundation

import SiriusKit
import NoctilucaPluginKit

extension NoctilucaClientSession {
    func noticeMessage(_ severity: NoticeSeverity, code: ServerNoticeCode, message: String? = nil) -> ServerNotice {
        let utcNow = Date()
        let timestamp = UInt64(utcNow.timeIntervalSince1970 * 1000)
        
        let message = message ?? code.defaultMessage
        
        let noticeMessage = ServerNotice(
            severity: severity,
            code: code,
            message: message,
            timestamp: timestamp
        )
        
        return noticeMessage
    }
    
    func notice(_ severity: NoticeSeverity, code: ServerNoticeCode, message: String? = nil) async throws {
        let noticeMessage = self.noticeMessage(severity, code: code, message: message)
        try await self.mainChannel.sendServerNotice(noticeMessage)
    }
}

extension ServerNoticeCode {
    var defaultMessage: String {
        switch self {
        case .jackpot:
            return "Congratulations! You've hit the JACKPOT! Enjoy your special reward! XDD"
            
        case .unsupportedOpcode:
            return "The server received a message with an unsupported operation code."
        case .unsupportedAuthMethod:
            return "The authentication method requested by the client is not supported by the server."
        case .nonceMismatch:
            return "The nonce provided by the client does not match the expected value."
        case .timeout:
            return "The client did not respond within the expected time frame."
        case .internalServerError:
            return "An unexpected error occurred on the server."
            
        default:
            return "An unspecified server notice has been issued."
        }
    }
}
