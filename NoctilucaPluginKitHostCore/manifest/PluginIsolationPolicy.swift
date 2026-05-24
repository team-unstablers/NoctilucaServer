//
//  PluginIsolationPolicy.swift
//  NoctilucaPluginKitHostCore
//
//  Created by Gyuhwan Park on 5/16/26.
//

import Foundation

/// 플러그인 번들 실행 컨텍스트의 격리 정책
public enum PluginIsolationPolicy: Sendable, Hashable {
    /// 별도 프로세스에서 격리 실행
    case isolate

    /// 격리하지 않음 (in-process 실행).
    /// team unstablers Inc. (teamid `XHA76UVA95`) 서명 번들에만 유효합니다.
    case noIsolate
}
