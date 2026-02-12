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


struct NOCCertificateView: View {
    enum SelectionTag: Hashable {
        case leaf
        case chain(index: Int)
    }
    
    let leaf: SecCertificateLike
    let chain: [SecCertificateLike]
    
    @State
    var selection: SelectionTag? = .leaf
    
    @ViewBuilder
    var chainSelector: some View {
        VStack {
            List(selection: $selection) {
                HStack(spacing: 0) {
                    Text(leaf.commonName)
                    Text(" - 리프 인증서")
                        .italic()
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .tag(SelectionTag.leaf)
                .focusable(true)
                
                ForEach(0..<chain.count, id: \.self) { index in
                    let intermediate = chain[index]
                    HStack(spacing: 0) {
                        Text(intermediate.commonName)
                        Text(" - 체인 인증서")
                            .italic()
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    .tag(SelectionTag.chain(index: index))
                    .focusable(true)
                }
            }
            .listStyle(.plain)
#if os(macOS)
            .frame(maxHeight: 96)
#else
            .font(.callout)
            .frame(maxHeight: 192)
#endif
        }
#if os(macOS)
        .border(.tertiary)
#else
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .fill(.clear)
                .strokeBorder(.tertiary)
        }
#endif

    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("인증서 체인")
                .font(.headline)
                .padding(.bottom, 8)
                .foregroundStyle(.primary)
                .bold(DeviceKind.current == .mac ? false : true)
            
            chainSelector
            
            Text("인증서 정보")
                .font(.headline)
                .padding(.vertical, 8)
                .foregroundStyle(.primary)
                .bold(DeviceKind.current == .mac ? false : true)

            VStack {
                let currentCertificate = if case .chain(let index) = selection ?? .leaf {
                    chain[index]
                } else {
                    leaf
                }

                ScrollView {
                    NOCCertificateDetailView(certificate: currentCertificate)
                        .id(selection)
                }
            }
#if os(macOS)
            .border(.tertiary)
#else
            .padding()
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.clear)
                    .strokeBorder(.tertiary)
            }
#endif
        }
    }
}

#if os(macOS)
typealias SecCertificateLike = SecCertificate

extension SecCertificate {
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
    
    var issuer: String? {
        self.extractIssuer()
    }
    
    var algorithmDescription: String? {
        self.extractAlgorithmDescription()
    }

    var publicKey: Data? {
        self.extractPublicKey()
    }
}


struct NOCCertificateDetailView: NSViewRepresentable {
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
    var issuer: String? { get }
    var algorithmDescription: String? { get }
    var publicKey: Data? { get }
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
    
    var issuer: String? {
        self.extractIssuer()
    }
    
    var algorithmDescription: String? {
        self.extractAlgorithmDescription()
    }
    
    var publicKey: Data? {
        self.extractPublicKey()
    }

}

struct NOCCertificateDetailView: View {
    let certificate: SecCertificateLike

    private var validityStatus: (text: String, color: Color) {
        let now = Date()
        if let notBefore = certificate.notBefore, now < notBefore {
            return ("아직 유효하지 않음", .orange)
        } else if let notAfter = certificate.notAfter, now > notAfter {
            return ("만료됨", .red)
        } else if certificate.notBefore != nil && certificate.notAfter != nil {
            return ("유효", .green)
        } else {
            return ("알 수 없음", .secondary)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                    Text(certificate.commonName)
                        .font(.callout)
                        .bold()
                    
                    if let issuer = certificate.issuer {
                        Text("\(issuer)가 발급함")
                            .font(.footnote)
                    }
                }
                
                /*
                Spacer()

                let status = validityStatus
                Text(status.text)
                    .font(.caption)
                    .bold()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(status.color.opacity(0.15))
                    .foregroundStyle(status.color)
                    .clipShape(Capsule())
                 */
            }
            

            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text("\(certificate.notBefore?.formatted(date: .abbreviated, time: .omitted) ?? "알 수 없음") 부터 유효")
                } icon: {
                    Image(systemName: "calendar")
                }

                Label {
                    Text("\(certificate.notAfter?.formatted(date: .abbreviated, time: .omitted) ?? "알 수 없음") 에 만료")
                } icon: {
                    Image(systemName: "calendar.badge.clock")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let fingerprint = certificate.fingerprint {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SHA-256 지문")
                        .font(.footnote)
                        .bold()

                    Text(fingerprint)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            
            if let algorithmDescription = certificate.algorithmDescription {
                VStack(alignment: .leading, spacing: 4) {
                    Text("키 알고리즘")
                        .font(.footnote)
                        .bold()

                    Text(algorithmDescription)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            
            if let publicKey = certificate.publicKey {
                VStack(alignment: .leading, spacing: 4) {
                    Text("공개 키")
                        .font(.footnote)
                        .bold()

                    Text(publicKey.asPrettyHexString())
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
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
    
    func asPrettyHexString() -> String {
        return self.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

#if DEBUG

/// 키체인에서 아무 인증서나 적당히 고릅니다
fileprivate func pickCertificate(_ label: String) -> SecCertificateLike? {
#if os(macOS)
    let result = SRKeychain.shared.queryItem(by: label, clazz: .certificate)
    guard let item = try? result.get() else {
        return nil
    }

    return item as! SecCertificate
#else
    return MockedCertificate(
        commonName: label,
        notBefore: Date(),
        notAfter: Calendar.current.date(byAdding: .year, value: 1, to: Date()),
        fingerprint: "BF:29:09:83:7F:06:EA:B4:2C:04:4B:30:50:73:A1:3B:9E:50:9E:1B",
        issuer: "Contoso Inc.",
        algorithmDescription: "RSA 2048-bit",
        publicKey: try? SRSecurity.shared.createSecureRandomBytes(count: 256),
    )
#endif
}

#Preview {
    let leaf = pickCertificate("전자 병아리 #3156")!
    let chain = [
        pickCertificate("전자 병아리 주식회사 Intermediate CA")!,
        pickCertificate("전자 병아리 주식회사 Root CA")!
    ]
    

    VStack {
        NOCCertificateView(leaf: leaf, chain: chain)
    }
    .padding()
}

#endif
