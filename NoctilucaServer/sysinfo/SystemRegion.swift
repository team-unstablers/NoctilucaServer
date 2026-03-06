//
//  SystemRegion.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 3/4/26.
//

import Foundation

struct SystemRegion {
    /// EEA(유럽경제지역) 국가 ISO 3166-1 alpha-2 코드 (EU 27 + EFTA/EEA 3)
    private static let eeaRegionCodes: Set<String> = [
        // EU 27
        "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR",
        "DE", "GR", "HU", "IE", "IT", "LV", "LT", "LU", "MT", "NL",
        "PL", "PT", "RO", "SK", "SI", "ES", "SE",
        // EFTA/EEA
        "IS", "LI", "NO",
    ]

    /// 영국 ISO 3166-1 alpha-2 코드
    private static let ukRegionCode = "GB"

    /// 현재 시스템 지역이 EEA 또는 영국인지 여부
    static var isEEAOrUK: Bool {
        guard let regionCode = Locale.current.region?.identifier else {
            return false
        }
        return eeaRegionCodes.contains(regionCode) || regionCode == ukRegionCode
    }
}
