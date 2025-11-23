//
//  SecCertificate+extractApplicationLabel.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/23/25.
//

import Foundation
import Security

import CryptoKit

import SwiftASN1
import X509

extension SecCertificate {
    func extractApplicationLabel() throws -> Data {
        let security = SRSecurity.shared
        
        let trust = try security.createTrust(from: self).get()
        
        guard let publicKey = SecTrustCopyKey(trust),
              let attributes = SecKeyCopyAttributes(publicKey) as? [String: Any],
              let applicationLabel = attributes[kSecAttrApplicationLabel as String] as? Data
        else {
            // FIXME
            throw SRSecurityError.createItemFailed(error: nil)
        }
        
        return applicationLabel
    }
}
