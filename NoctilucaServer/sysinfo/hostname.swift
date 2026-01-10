//
//  hostname.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 1/10/26.
//

import Foundation

func hostname() -> String {
    return ProcessInfo.processInfo.hostName
}
