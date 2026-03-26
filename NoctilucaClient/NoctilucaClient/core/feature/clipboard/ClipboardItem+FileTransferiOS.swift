//
//  ClipboardItem+FileTransferiOS.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 3/24/26.
//

#if os(iOS)
import Foundation

import UIKit

import SiriusKitClient
import UniformTypeIdentifiers

extension ClipboardItem {
    /// 이 ClipboardItem이 파일 전송 메타데이터를 포함하는지 확인합니다.
    var isFileTransfer: Bool {
        self.representations.first?.contentType == FileTransferContentType.fileTransfer
    }

    /// 파일 전송 메타데이터를 파싱합니다.
    var fileTransferMetadata: FileTransferMetadata? {
        guard let repr = self.representations.first(where: {
            $0.contentType == FileTransferContentType.fileTransfer
        }),
              let data = repr.data else {
            return nil
        }
        return try? JSONDecoder().decode(FileTransferMetadata.self, from: data)
    }
}
#endif
