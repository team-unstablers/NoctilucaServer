//
//  SecIdentity+cast.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/23/25.
//

import Foundation
import Security

public extension SecIdentity {
    func asCHandle() -> sec_identity_t {
        let handle = sec_identity_create(self)

        guard handle != nil else {
            fatalError("FIXME: handle != nil을 보장하던가 그렇지 않던가 하십시오")
        }

        return handle!
    }

    func extractLabel() -> String? {
        let query: [String: Any] = [
            kSecValueRef as String: self,
            kSecReturnAttributes as String: true
            // kSecAttrLabel이 포함된 딕셔너리를 원함
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess,
           let attributes = result as? [String: Any],
           let label = attributes[kSecAttrLabel as String] as? String {
            return label
        }

        return nil
    }
    
    func extractCertificate() -> SecCertificate? {
        var cert: SecCertificate?
        let status = SecIdentityCopyCertificate(self, &cert)
        
        if status == errSecSuccess {
            return cert
        } else {
            return nil
        }
    }
}
