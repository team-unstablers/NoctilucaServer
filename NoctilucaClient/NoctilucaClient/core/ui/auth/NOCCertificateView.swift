//
//  NOCCertificateView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/10/26.
//

import Foundation
import SwiftUI

import Security

#if os(macOS)
import SecurityInterface
#endif

import SiriusKitClient

#if os(macOS)
typealias SecCertificateLike = SecCertificate

struct NOCCertificateView: NSViewRepresentable {
    let certificate: SecCertificate

    func makeNSView(context: Context) -> SFCertificateView {
        let certView = SFCertificateView()
        certView.setCertificate(certificate)
        certView.setDetailsDisclosed(true)

        return certView
    }

    func updateNSView(_ nsView: SFCertificateView, context: Context) {
        // No update needed
    }
}
#else

protocol SecCertificateLike {
    var commonName: String { get }
    var notBefore: Date? { get }
    var notAfter: Date? { get }
    var fingerprint: String? { get }
}

extension SecCertificate: SecCertificateLike {
    var commonName: String {
        self.extractCommonName() ?? ""
    }

    var notBefore: Date? {
        self.extractNotBefore()
    }

    var notAfter: Date? {
        self.extractNotAfter()
    }

    var fingerprint: String? {
        self.extractFingerprint()?.asFingerprintString()
    }
}

struct NOCCertificateView: View {
    let certificate: SecCertificateLike

    var body: some View {
        VStack(alignment: .leading) {
            Text(certificate.commonName)
                .font(.callout)
                .bold()

            Text("\(certificate.notBefore?.formatted(date: .abbreviated, time: .omitted) ?? "알 수 없음")부터 \(certificate.notAfter?.formatted(date: .abbreviated, time: .omitted) ?? "알 수 없음")까지 유효")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let fingerprint = certificate.fingerprint {
                Text(fingerprint)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif

extension Data {
    func asFingerprintString() -> String {
        return self.map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}
