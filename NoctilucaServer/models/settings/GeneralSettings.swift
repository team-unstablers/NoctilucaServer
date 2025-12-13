//
//  GeneralSettings.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/4/25.
//

import Foundation

extension AppSettings {
    struct General: Category {
        /// 최대 동시 접속 세션 수
        var maxConcurrentSessions: Int = 1
    }
    
    struct Notifications: Category {
        var enabled: Bool = false
    }
}
