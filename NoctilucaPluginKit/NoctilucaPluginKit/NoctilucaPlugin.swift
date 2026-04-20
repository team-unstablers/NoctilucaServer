//
//  NoctilucaPlugin.swift
//  NoctilucaPluginKit
//
//  Created by Gyuhwan Park on 12/5/25.
//

public enum NoctilucaPluginType: String, Sendable {
    /// 인증 플러그인. 사용자 인증과 관련된 플러그인입니다. (예: OAuth, LDAP, SSO 등...)
    case auth = "auth"
    
    /// 기능 플러그인. Sirius 프로토콜을 통해 커스텀 기능을 노출하고 제공할 수 있도록 합니다.
    case feature = "feature"

    /// 익스텐션. 저레벨 수준으로 서버 기능을 확장하는 플러그인입니다.
    /// 서버 이벤트를 관찰하고 클라이언트 연결을 intercept하거나 (fail2ban 같은) 하는 목적으로 사용됩니다.
    case `extension` = "extension"
    
    /// 키보드 핵. Sirius의 키보드 입력 기능 (HIDIO)를 확장하는 플러그인입니다. (예: 입력 방식, 키 매핑, 커스텀 단축키 등...)
    case keyboardHack = "keyboard_hack"
}

public enum NoctilucaPluginExport: Sendable {
    case auth(AuthPluginV1)
    case `extension`(NoctilucaServerExtensionV1)
    case keyboardHack(KeyboardHackPluginV1)

    public var id: String {
        switch self {
        case .auth(let plugin):
            return type(of: plugin).id
        case .extension(let plugin):
            return type(of: plugin).id
        case .keyboardHack(let plugin):
            return type(of: plugin).id
        }
    }
}
