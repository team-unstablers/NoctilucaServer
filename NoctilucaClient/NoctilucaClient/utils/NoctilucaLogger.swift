//
//  NoctilucaLogger.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/5/25.
//

import SiriusKit

func NoctilucaLogger(category: String) -> SiriusLogger {
    return SiriusLogger(category: category, subsystem: NoctilucaMeta.bundleIdentifier)
}
