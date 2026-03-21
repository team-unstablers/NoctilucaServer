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
            return String(localized: "codec.resolution.unlimited", defaultValue: "제한 없음")
        case .sd480p:
            return String(localized: "codec.resolution.sd480p", defaultValue: "480p (SD급)")
        case .hd720p:
            return String(localized: "codec.resolution.hd720p", defaultValue: "720p (HD급)")
        case .hd1080p:
            return String(localized: "codec.resolution.hd1080p", defaultValue: "1080p (Full HD급)")
        case .hd2k:
            return String(localized: "codec.resolution.hd2k", defaultValue: "1440p (2K급)")
        case .hd4k:
            return String(localized: "codec.resolution.hd4k", defaultValue: "2160p (4K급)")
        default:
            return String(localized: "codec.resolution.unknown", defaultValue: "알 수 없음")
        }
    }
    
    /// 이 해상도 레벨에서 통상적으로 쓰이는 해상도를 반환합니다.
    /// 이.. 이딴식으로 이걸 구현해도 되는건가...
    /// 4:3 기준으로 처리한다 - 16:9나 16:10보다 픽셀 수가 많기 때문에 대체로 다 걸림
    var genericSize: CGSize? {
        switch self {
        case .unlimited:
            return nil
        case .sd480p:
            return CGSize(width: 720, height: 480)
        case .hd720p:
            return CGSize(width: 1280, height: 960)
        case .hd1080p:
            return CGSize(width: 1920, height: 1440)
        case .hd2k:
            return CGSize(width: 2560, height: 1920)
        case .hd4k:
            return CGSize(width: 3840, height: 1880)
            
        default:
            return nil
        }
    }
    
    var pixelCount: Int {
        guard let genericSize = genericSize else {
            return Int.max
        }
        
        return Int(genericSize.width) * Int(genericSize.height)
    }
}

