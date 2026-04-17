//
//  NoctilucaPlugin.swift
//  NoctilucaPluginKit
//
//  Created by Gyuhwan Park on 12/5/25.
//

import Foundation

public protocol NoctilucaPluginBundle: AnyObject, Sendable {
    /// The name of the plugin bundle.
    /// This should be a human-readable name.
    static var name: String { get }
    
    /// A brief description of the plugin's functionality.
    /// This helps users understand what the plugin does.
    static var description: String { get }

    /// 플러그인 번들을 초기화합니다.
    /// 이 메서드는 플러그인이 로드될 때 호출됩니다.
    static func initialize() async throws
    
    /// 플러그인 번들을 비활성화합니다.
    /// 이 메서드는 플러그인이 언로드될 때 호출됩니다.
    static func deinitialize() throws
    
    /// Export된 플러그인 목록
    ///
    /// REQUIREMENTS:
    ///  - 호스트 애플리케이션에서는 initialize() 메소드가 성공적으로 수행된 이후, 이 속성에 접근합니다.
    ///  - 이 속성은 initialize() 메소드 이후 deinitialize()가 호출되기 전까지 변경되어선 안됩니다.
    static var exports: [NoctilucaPluginExport] { get }
}
