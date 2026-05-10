//
//  MiscSettings.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/4/25.
//

import Foundation

extension AppSettings {
    struct Misc: Category {
        var showPerformanceOverlay: Bool = false
        var showDebugWindow: Bool = false
        var showAppStreamWindowInfoOverlay: Bool = false

        init () {}

        enum CodingKeys: String, CodingKey {
            case showPerformanceOverlay
            case showDebugWindow
            case showAppStreamWindowInfoOverlay
        }

        init(from decoder: any Decoder) throws {
            self.init()

            guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
                return
            }

            self.showPerformanceOverlay = container.decodeSafe(
                Bool.self,
                forKey: AppSettings.Misc.CodingKeys.showPerformanceOverlay,
                default: false
            )
            self.showDebugWindow = container.decodeSafe(
                Bool.self,
                forKey: AppSettings.Misc.CodingKeys.showDebugWindow,
                default: false
            )
            self.showAppStreamWindowInfoOverlay = container.decodeSafe(
                Bool.self,
                forKey: AppSettings.Misc.CodingKeys.showAppStreamWindowInfoOverlay,
                default: false
            )
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(showPerformanceOverlay, forKey: .showPerformanceOverlay)
            try container.encode(showDebugWindow, forKey: .showDebugWindow)
            try container.encode(showAppStreamWindowInfoOverlay, forKey: .showAppStreamWindowInfoOverlay)
        }
    }

    struct Plugins: Category {
    }
}
