//
//  AppStreamUIState.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/23/26.
//

import Foundation

enum AppStreamUIState: Hashable, Equatable {
    case inactive
    case presentAppSelector
    case active(bundleIdentifier: String)
}
