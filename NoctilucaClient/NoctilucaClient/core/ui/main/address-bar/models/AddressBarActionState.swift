//
//  AddressBarActionState.swift
//  NoctilucaClient
//

import Foundation

enum AddressBarActionState {
    case connecting(progress: Double)
    case fileTransfer(progress: Double)

    var label: String {
        switch self {
        case .connecting:
            return "연결 중"
        case .fileTransfer:
            return "파일 전송 중"
        }
    }

    var progress: Double {
        switch self {
        case .connecting(let progress):
            return progress
        case .fileTransfer(let progress):
            return progress
        }
    }
}
