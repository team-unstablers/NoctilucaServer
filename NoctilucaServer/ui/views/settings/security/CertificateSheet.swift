//
//  CertificateSheet.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 1/10/26.
//

import Foundation
import Cocoa
import Security
import SecurityInterface
import SwiftUI

struct NOCCertificateView: NSViewRepresentable {
    let certificate: SecCertificate
    
    func makeNSView(context: Context) -> SFCertificateView {
        let certView = SFCertificateView()
        certView.setCertificate(certificate)
        
        return certView
    }
    
    func updateNSView(_ nsView: SFCertificateView, context: Context) {
        // No update needed
    }
}


struct CertificateSheet: View {
    let certificate: SecCertificate
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack {
            NOCCertificateView(certificate: certificate)
            
            HStack {
                Spacer()
                Button(String(localized: "settings.security.certificate.close", defaultValue: "닫기")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
    }
}
