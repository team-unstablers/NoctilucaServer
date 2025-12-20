//
//  CodecDefinition.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/13/25.
//

import Foundation
import SiriusKit

extension CodecSpecification {
    func isCompatible(with another: CodecSpecification) -> Bool {
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
    
    func isColorFormatCompatible(with another: CodecSpecification) -> Bool {
        let oursColorFormat = self.options[.colorFormat] ?? .kColorFormatAuto
        let theirsColorFormat = another.options[.colorFormat] ?? .kColorFormatAuto
        
        if oursColorFormat == .kColorFormatAuto || theirsColorFormat == .kColorFormatAuto {
            return true
        }
        
        return oursColorFormat == theirsColorFormat
    }
    
    func isHardwareAccelerationCompatible(with another: CodecSpecification) -> Bool {
        let oursHWAccel = self.options[.hardwareAcceleration] ?? .kHardwareAccelerationTrue
        let theirsHWAccel = another.options[.hardwareAcceleration] ?? .kHardwareAccelerationTrue
        
        
        if oursHWAccel == .kHardwareAccelerationTrue || theirsHWAccel == .kHardwareAccelerationTrue {
            return true
        }
        
        if oursHWAccel == .kHardwareAccelerationForced {
            return theirsHWAccel == .kHardwareAccelerationForced
        }
        
        if oursHWAccel == .kHardwareAccelerationFalse {
            return theirsHWAccel == .kHardwareAccelerationFalse
        }
        
        return false
    }
    
    func isProfileCompatible(with another: CodecSpecification) -> Bool {
        let oursProfile = self.options[.profile] ?? .kProfileAuto
        let theirsProfile = another.options[.profile] ?? .kProfileAuto
        
        if oursProfile == .kProfileAuto || theirsProfile == .kProfileAuto {
            return true
        }
        
        if oursProfile == .kProfileH264Baseline {
            // Baseline은 상대편의 모든 프로파일과 호환됨
            return true
        }
        
        if oursProfile == .kProfileH264Main {
            // 상대편이 Baseline만 아니면 됨
            return theirsProfile != .kProfileH264Baseline
        }
        
        if oursProfile == .kProfileH264High {
            // High는 Main과 High만 호환됨
            return theirsProfile == .kProfileH264High
        }
        
        return false
    }
    
    func isFrameRateCompatible(with another: CodecSpecification) -> Bool {
        let oursFrameRate = self.frameRate
        let theirsFrameRate = another.frameRate
        
        if oursFrameRate == 0 || theirsFrameRate == 0 {
            return true
        }
        
        return oursFrameRate >= theirsFrameRate
    }
    
    func isResolutionLevelCompatible(with another: CodecSpecification) -> Bool {
        let oursLevel = self.maximumResolutionLevel
        let theirsLevel = another.maximumResolutionLevel
        
        if oursLevel == .unlimited || theirsLevel == .unlimited {
            return true
        }
        
        return oursLevel.rawValue >= theirsLevel.rawValue
    }
}
