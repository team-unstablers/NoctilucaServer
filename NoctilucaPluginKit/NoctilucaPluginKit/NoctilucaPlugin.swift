//
//  NoctilucaPlugin.swift
//  NoctilucaPluginKit
//
//  Created by Gyuhwan Park on 12/5/25.
//

public enum NoctilucaPluginType: String {
    case auth = "auth"
    case feature = "feature"
    
    /// 익스텐션. 저레벨 수준으로 서버 기능을 확장하는 플러그인입니다.
    /// 서버 이벤트를 관찰하고 클라이언트 연결을 intercept하거나 (fail2ban 같은) 하는 목적으로 사용됩니다.
    case `extension` = "extension"
}

public enum NoctilucaPluginExport {
    case auth(AuthPluginV1)
    
    public var id: String {
        switch self {
        case .auth(let plugin):
            return type(of: plugin).id
        }
    }
}
