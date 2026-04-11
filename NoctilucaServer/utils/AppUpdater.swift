//
//  Updater.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 2/16/26.
//

import Foundation

import Sparkle

@MainActor
final class AppUpdater: NSObject, Sendable {
    static let shared = AppUpdater()
    
    private let logger = NoctilucaLogger(category: "AppUpdater")
    private(set) var updaterController: SPUStandardUpdaterController!
    
    private override init() {
        super.init()
        
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }
}

extension AppUpdater: SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
#if DEBUG
        return "http://localhost:9000/appcast.xml"
#else
        return "https://releases.noctiluca.app/server/v1/appcast.xml"
#endif
    }
    
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        
    }
}
