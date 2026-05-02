//
//  FileTransferCoordinator+iOS.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 3/24/26.
//

#if os(iOS)
import Foundation
import UIKit
import UniformTypeIdentifiers

import SiriusKitClient

// MARK: - iOS: 사전 다운로드 + NSItemProvider 생성

extension FileTransferCoordinator {

    /// 파일을 임시 디렉토리에 미리 다운로드하여 URL을 반환한다.
    /// iOS에서는 낮은 우선순위로 실행되며, 동시 다운로드 수가 제한된다.
    func predownloadFile(metadata: FileTransferMetadata) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let tempURL = tempDir.appendingPathComponent(metadata.name)

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        if metadata.isDirectory {
            try await downloadDirectory(metadata: metadata, to: tempURL)
        } else {
            try await downloadFile(metadata: metadata, to: tempURL)
        }

        return tempURL
    }

    /// 이미 다운로드된 파일 URL을 감싸는 NSItemProvider를 생성한다.
    func createItemProvider(for metadata: FileTransferMetadata, fileURL: URL) -> NSItemProvider {
        let itemProvider = NSItemProvider()
        itemProvider.suggestedName = metadata.name

        let utType: UTType
        if metadata.isDirectory {
            utType = .directory
        } else {
            utType = UTType(mimeType: metadata.contentType) ?? .data
        }

        itemProvider.registerFileRepresentation(
            for: utType,
            visibility: .all,
            openInPlace: false
        ) { completion in
            completion(fileURL, false, nil)
            return Progress()
        }

        return itemProvider
    }
}
#endif
