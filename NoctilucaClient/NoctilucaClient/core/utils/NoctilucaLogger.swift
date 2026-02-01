//
//  NoctilucaLogger.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/5/25.
//

import SiriusKitClient

func NoctilucaLogger(category: String) -> SiriusLogger {
    return SiriusLogger(category: category, subsystem: NoctilucaMeta.bundleIdentifier)
}
func NoctilucaLogger(category: String, subsystem: String) -> SiriusLogger {
    return SiriusLogger(category: category, subsystem: NoctilucaMeta.scopedIdentifier(subsystem))
}
