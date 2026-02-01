//
//  AddressBarAction.swift
//  NoctilucaClient
//

import Foundation

/// AddressBar에서 발생하는 사용자 액션
enum AddressBarAction {
    /// 엔드포인트로 연결 요청
    case submit(EndpointKind)
    /// 취소 (ESC 키 또는 동일 URL 재입력)
    case cancel
}
