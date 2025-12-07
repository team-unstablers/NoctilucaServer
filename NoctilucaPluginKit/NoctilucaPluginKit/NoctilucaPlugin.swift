//
//  NoctilucaPlugin.swift
//  NoctilucaPluginKit
//
//  Created by Gyuhwan Park on 12/5/25.
//

public enum NoctilucaPluginType: String {
    case auth = "auth"
    case feature = "feature"
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
