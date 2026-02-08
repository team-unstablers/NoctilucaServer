//
//  CodecOption.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/13/25.
//

import Foundation

struct CodecResolutionLevel: RawRepresentable, Codable, Hashable, Equatable {
    var rawValue: Int
    
    init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    /// 자동 / 제한 없음 (협상 결정을 맡김)
    static let unlimited = Self(rawValue: 0)
    
    /// SD 해상도 (480p)
    static let sd480p = Self(rawValue: 1)
    
    /// HD 해상도 (720p)
    static let hd720p = Self(rawValue: 2)
    
    /// Full HD 해상도 (1080p)
    static let hd1080p = Self(rawValue: 3)
    
    /// 2K 해상도 (1440p)
    static let hd2k = Self(rawValue: 4)
    
    /// 4K 해상도 (2160p)
    static let hd4k = Self(rawValue: 5)
    
    var displayText: String {
        switch self {
        case .unlimited:
            return "제한 없음"
        case .sd480p:
            return "480p (SD급)"
        case .hd720p:
            return "720p (HD급)"
        case .hd1080p:
            return "1080p (Full HD급)"
        case .hd2k:
            return "1440p (2K급)"
        case .hd4k:
            return "2160p (4K급)"
        default:
            return "알 수 없음"
        }
    }
    
    /// 이.. 이딴식으로 이걸 구현해도 되는건가...
    /// 4:3 기준으로 처리한다 - 16:9나 16:10보다 픽셀 수가 많기 때문에 대체로 다 걸림
    var pixelCount: Int {
        switch self {
        case .unlimited:
            // FIXME
            return Int.max
        case .sd480p:
            return 720 * 480
        case .hd720p:
            return 1280 * 960
        case .hd1080p:
            return 1920 * 1440
        case .hd2k:
            return 2560 * 1920
        case .hd4k:
            return 3840 * 2880
        
        default:
            return Int.max
        }
    }
}

