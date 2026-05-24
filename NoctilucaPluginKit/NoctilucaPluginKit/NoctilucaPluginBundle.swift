//
//  NoctilucaPlugin.swift
//  NoctilucaPluginKit
//
//  Created by Gyuhwan Park on 12/5/25.
//

import Foundation

/// 플러그인 번들이 취할 수 있는 액션 목록
public enum NoctilucaPluginBundleAction: String, Codable, Sendable {
    /// 플러그인 번들 자체의 설정 UI를 엽니다.
    /// 이 액션에 대한 수행 요청을 받으면, 플러그인 번들은 적절한 설정 UI를 사용자에게 표시해야 합니다.
    case showSettingsUI = "showSettingsUI"
}

public protocol NoctilucaPluginBundle: AnyObject, Sendable {
    /// 플러그인 번들을 초기화합니다.
    /// 이 메서드는 플러그인이 로드될 때 호출됩니다.
    static func initialize() async throws
    
    /// 플러그인 번들을 비활성화합니다.
    /// 이 메서드는 플러그인이 언로드될 때 호출됩니다.
    static func deinitialize() throws
    
    /// 주어진 액션을 디스패치 요청합니다.
    /// - 서버는 플러그인 번들이 지원하지 않는 액션을 dispatch해선 안됩니다.
    static func dispatchAction(action: NoctilucaPluginBundleAction) async throws
    
    /// Export된 플러그인 목록
    ///
    /// REQUIREMENTS:
    ///  - 호스트 애플리케이션에서는 initialize() 메소드가 성공적으로 수행된 이후, 이 속성에 접근합니다.
    ///  - 이 속성은 initialize() 메소드 이후 deinitialize()가 호출되기 전까지 변경되어선 안됩니다.
    static var exports: [NoctilucaPluginExport] { get }
    
    /// 플러그인 번들이 지원하는 액션 목록
    static var supportedActions: [NoctilucaPluginBundleAction] { get }
}
