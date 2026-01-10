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
    
#if os(macOS)
    func extractMetadataValue(for key: CFString) -> Any? {
        guard let valuesDict = SecCertificateCopyValues(self, [key] as [CFString] as CFArray, nil) as? [String: Any] else {
            return nil
        }
        
        guard let container = valuesDict[key as String] as? [String: Any] else {
            return nil
        }
        
        return container[kSecPropertyKeyValue as String]
    }
#endif
    
    
    func extractCommonName() -> String? {
        if #available(macOS 15.0, iOS 18.0, *) {
            var commonName: CFString? = nil
            
            guard SecCertificateCopyCommonName(self, &commonName) == errSecSuccess,
                  let unwrappedCommonName = commonName as String?
            else {
                return nil
            }
            
            return unwrappedCommonName
        } else {
#if os(macOS)
            guard let rawValue = extractMetadataValue(for: kSecOIDCommonName) as? String else {
                return nil
            }
            
            return rawValue
#else
            return nil
#endif
        }
    }
    
    /// SHA-256 fingerprint
    func extractFingerprint() -> Data? {
        let data = SecCertificateCopyData(self) as Data
        let digest = SHA256.hash(data: data)
        
        return digest.withUnsafeBytes { Data($0) }
    }
    
    func extractNotBefore() -> Date? {
        if #available(macOS 15.0, iOS 18.0, *) {
            let notBefore = SecCertificateCopyNotValidBeforeDate(self) as? Date
            return notBefore
        } else {
#if os(macOS)
            guard let rawValue = extractMetadataValue(for: kSecOIDX509V1ValidityNotBefore) as? NSNumber else {
                return nil
            }
            
            return Date(timeIntervalSinceReferenceDate: rawValue.doubleValue)
#else
            return nil
#endif
        }
    }
    
    func extractNotAfter() -> Date? {
        if #available(macOS 15.0, iOS 18.0, *) {
            let notAfter = SecCertificateCopyNotValidAfterDate(self) as? Date
            return notAfter
        } else {
#if os(macOS)
            guard let rawValue = extractMetadataValue(for: kSecOIDX509V1ValidityNotAfter) as? NSNumber else {
                return nil
            }
            
            return Date(timeIntervalSinceReferenceDate: rawValue.doubleValue)
#else
            return nil
#endif
        }
    }
}
