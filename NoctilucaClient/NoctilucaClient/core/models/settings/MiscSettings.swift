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
        
        init () {}
        
        enum CodingKeys: String, CodingKey {
            case showPerformanceOverlay
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
        }
        
        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(showPerformanceOverlay, forKey: .showPerformanceOverlay)
        }
    }

    struct Plugins: Category {
    }
}
