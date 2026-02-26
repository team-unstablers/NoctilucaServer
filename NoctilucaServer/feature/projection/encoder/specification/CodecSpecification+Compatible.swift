//
//  CodecDefinition.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/13/25.
//

import Foundation
import SiriusKit

extension CodecSpecification {
    func isCompatible(with another: borrowing SiriusKit.Codec) -> Bool {
        // 1. 전제 조건으로 FourCC가 동일해야 함
        guard self.fourCC == another.fourCC else {
            return false
        }
        
        // 2. 옵션 호환성 검사
        guard self.isColorFormatCompatible(with: another),
              self.isHardwareAccelerationCompatible(with: another),
              self.isProfileCompatible(with: another)
        else {
            return false
        }
        
        // 3. 영상 프로퍼티 호환성 검사
        guard self.isFrameRateCompatible(with: another),
              self.isResolutionLevelCompatible(with: another)
        else {
            return false
        }
        
        return true
    }
    
    func isColorFormatCompatible(with another: borrowing SiriusKit.Codec) -> Bool {
        let oursColorFormat = self.options[.colorFormat] ?? .kColorFormatAuto
        
        if let theirsMandatory = another.options.mandatory[.colorFormat] {
            // 상대편이 mandatory로 지정한 경우,
            // ours가 auto이거나 동일한 값이어야 함
            
            if oursColorFormat == .kColorFormatAuto || theirsMandatory == .kColorFormatAuto {
                return true
            }
            
            return oursColorFormat == theirsMandatory
        }
        
        // 상대편이 optional로 지정한 경우, 지켜지지 않아도 딱히 상관 없음
        return true
    }
    
    func isHardwareAccelerationCompatible(with another: borrowing SiriusKit.Codec) -> Bool {
        let oursHWAccel = self.options[.hardwareAcceleration] ?? .kHardwareAccelerationAuto
        
        if let theirsMandatory = another.options.mandatory[.hardwareAcceleration] {
            if oursHWAccel == .kHardwareAccelerationAuto || theirsMandatory == .kHardwareAccelerationAuto {
                return true
            }
            
            return oursHWAccel == theirsMandatory
        }
        
        // 상대편이 optional로 지정한 경우, 지켜지지 않아도 딱히 상관 없음
        return true
    }
    
    func isProfileCompatible(with another: borrowing SiriusKit.Codec) -> Bool {
        guard let theirsMandatory = another.options.mandatory[.profile] else {
            // 상대편이 optional로 지정한 경우, 지켜지지 않아도 딱히 상관 없음
            return true
        }

        switch self.fourCC {
        case .avc1:
            return isH264ProfileCompatibleStrict(with: theirsMandatory)
        case .hvc1:
            return isHEVCProfileCompatibleStrict(with: theirsMandatory)
        default:
            let oursProfile = self.options[.profile] ?? .kProfileAuto
            if oursProfile == .kProfileAuto || theirsMandatory == .kProfileAuto {
                return true
            }
            return oursProfile == theirsMandatory
        }
    }
    
    func isH264ProfileCompatibleStrict(with theirsMandatory: CodecOptionValue) -> Bool {
        let oursProfile = self.options[.profile] ?? .kProfileAuto
        
        if oursProfile == .kProfileAuto || theirsMandatory == .kProfileAuto {
            return true
        }
        
        // 낮은 프로파일(Baseline)일수록 더 넓은 호환성을 가정한다.
        let rank: (CodecOptionValue) -> Int? = { profile in
            switch profile {
            case .kProfileH264Baseline:
                return 0
            case .kProfileH264Main:
                return 1
            case .kProfileH264High:
                return 2
            default:
                return nil
            }
        }

        guard let oursRank = rank(oursProfile),
              let theirsRank = rank(theirsMandatory)
        else {
            return false
        }

        // 서버가 사용할 프로파일이 상대가 요구하는(지원 가능한) 프로파일보다 높으면 호환되지 않는다고 본다.
        return oursRank <= theirsRank
    }
    
    func isHEVCProfileCompatibleStrict(with theirsMandatory: CodecOptionValue) -> Bool {
        let oursProfile = self.options[.profile] ?? .kProfileAuto
        
        if oursProfile == .kProfileAuto || theirsMandatory == .kProfileAuto {
            return true
        }
        
        let rank: (CodecOptionValue) -> Int? = { profile in
            switch profile {
            case .kProfileHEVCMain:
                return 0
            case .kProfileHEVCMain10:
                return 1
            default:
                return nil
            }
        }

        guard let oursRank = rank(oursProfile),
              let theirsRank = rank(theirsMandatory)
        else {
            return false
        }

        return oursRank <= theirsRank
    }
    
    
    /// 서버 스펙에 클라이언트의 선호 사항을 병합합니다.
    /// - 서버가 "auto"인 옵션은 클라이언트의 선호값으로 대체됩니다.
    /// - 서버가 구체적 값을 가진 옵션은 서버 값이 유지됩니다.
    /// - 서버에 없는 옵션 중 클라이언트가 가진 것은 채택됩니다.
    func merging(with client: borrowing SiriusKit.Codec) -> CodecSpecification {
        var merged = self

        // 클라이언트의 모든 옵션 순회 (mandatory가 optional보다 우선)
        let allClientOptions = client.options.mandatory
            .merging(client.options.optional) { mandatory, _ in mandatory }

        for (key, clientValue) in allClientOptions {
            if let serverValue = merged.options[key] {
                // 서버가 auto이면 클라이언트 선호 채택
                if serverValue.rawValue == "auto" && clientValue.rawValue != "auto" {
                    merged.options[key] = clientValue
                }
            } else {
                // 서버에 해당 키가 없으면 클라이언트 값 채택
                merged.options[key] = clientValue
            }
        }

        // frameRate: 서버 0(auto)이면 클라이언트 값 채택
        if merged.frameRate == 0, let clientFrameRate = client.frameRate, clientFrameRate > 0 {
            merged.frameRate = Double(clientFrameRate)
        }

        return merged
    }

    func isFrameRateCompatible(with another: borrowing SiriusKit.Codec) -> Bool {
        let oursFrameRate = self.frameRate
        let theirsFrameRate = Double(another.frameRate ?? 0.0)
        
        if oursFrameRate == 0 || theirsFrameRate == 0 {
            return true
        }
        
        // 서버가 설정한 최대 프레임레이트(ours)를 초과하는 요청은 호환 불가로 간주한다.
        return oursFrameRate >= theirsFrameRate
    }
    
    func isResolutionLevelCompatible(with another: borrowing SiriusKit.Codec) -> Bool {
        let oursLevel = self.maximumResolutionLevel
        let theirsLevel: CodecResolutionLevel = if let size = another.size {
            CodecResolutionLevel.fromCGSize(size: size.cgSize)
        } else {
            .unlimited
        }
        
        if oursLevel == .unlimited || theirsLevel == .unlimited {
            return true
        }
        
        return oursLevel.rawValue >= theirsLevel.rawValue
    }
}
