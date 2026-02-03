//
//  MsQuicServerIdentityAdapter.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 2/3/26.
//

import Foundation
import Security

import SwiftMsQuicHelper

/// SecIdentity를 MsQuic의 QuicCredentialConfig로 변환하는 어댑터
///
/// MsQuic은 PKCS#12 형식의 인증서를 요구하므로, SecIdentity를 PKCS#12로 export하여
/// 임시 파일로 저장한 뒤 MsQuic에 전달합니다.
/// 이 클래스가 deinit될 때 임시 파일이 자동으로 삭제됩니다.
final class MsQuicServerIdentityAdapter {
    enum AdapterError: Error {
        case pkcs12ExportFailed(OSStatus)
        case tempFileCreationFailed
        case identityNotAvailable
    }

    private let pkcs12Data: Data
    private let password: String


    /// QUICServerIdentity로부터 어댑터를 생성합니다.
    ///
    /// - Parameters:
    ///   - identity: QUICServerIdentity 프로토콜을 구현한 객체
    /// - Throws: PKCS#12 export 실패 시 에러
    init(identity: any QUICServerIdentity) async throws {
        let secIdentity = try await identity.getServerIdentity()

        // PKCS#12 export용 임시 패스워드 생성
        self.password = UUID().uuidString

        // SecIdentity를 PKCS#12로 export
        self.pkcs12Data = try Self.exportToPKCS12(identity: secIdentity, password: self.password)
    }

    deinit {
        // 임시 파일 삭제
        // try? FileManager.default.removeItem(atPath: tempFilePath)
    }

    /// MsQuic용 QuicCredentialConfig를 생성합니다.
    func createCredentialConfig() -> QuicCredentialConfig {
        /*
        return QuicCredentialConfig(
            type: .certificatePkcs12(blob: self.pkcs12Data, password: self.password),
            flags: [.noCertificateValidation]
        )
         */
        
        return QuicCredentialConfig(type: .certificateFile(
            certPath: "/Users/cheesekun/works/noctiluca/swift-msquic/server.crt",
            keyPath: "/Users/cheesekun/works/noctiluca/swift-msquic/server.key"
        ))
    }

    /// SecIdentity를 PKCS#12 형식으로 export합니다.
    private static func exportToPKCS12(identity: SecIdentity, password: String) throws -> Data {
        // SecItemImportExportKeyParameters 구조체 설정
        var keyParams = SecItemImportExportKeyParameters()
        // keyParams.version = UInt32(SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION)

        // passphrase를 CFString으로 설정
        let passphrase = password as CFString
        keyParams.passphrase = Unmanaged.passUnretained(passphrase)

        var exportData: CFData?
        let exportStatus = SecItemExport(
            identity,
            .formatPKCS12,
            [],
            &keyParams,
            &exportData
        )

        guard exportStatus == errSecSuccess, let data = exportData as Data? else {
            throw AdapterError.pkcs12ExportFailed(exportStatus)
        }

        return data
    }
}
