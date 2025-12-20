//
//  Codec+HDR.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 12/21/25.
//

import Foundation

public enum CodecHDRIneligibilityReason: String, Codable, Sendable {
    case unsupportedCodec = "unsupported_codec"
    case unsupportedProfile = "unsupported_profile"
    case unsupportedColorDepth = "unsupported_color_depth"
    case unsupportedOption = "unsupported_option"
}

public enum CodecHDRIneligibilityWarning: String, Codable, Sendable {
    /// 이 구성은 심각한 퍼포먼스 / 호환성 이슈가 있을 수 있습니다.
    case performanceIssue = "performance_issue"
    
    /// 이 구성은 화질 저하 이슈가 있을 수 있습니다.
    case qualityIssue = "quality_issue"
}


public enum CodecHDREligibility {
    /// 이 코덱 구성은 HDR 비디오 전송에 적합합니다.
    case eligible
    
    /// 이 코덱 구성은 HDR 비디오 전송이 가능하지만, 권장하지 않습니다.
    case eligibleWithWarnings(warnings: Set<CodecHDRIneligibilityWarning>)
    
    /// 이 코덱 구성은 HDR 비디오 전송에 적합하지 않습니다.
    case ineligible(reason: CodecHDRIneligibilityReason)
    
    var isEligible: Bool {
        switch self {
        case .eligible, .eligibleWithWarnings:
            return true
        case .ineligible:
            return false
        }
    }
}

public extension Codec {
    /// 코덱 구성이 HDR(High Dynamic Range)에 적합한지 판정합니다.
    var isEligibleForHDR: CodecHDREligibility {
        if self.fourCC == .avc1 {
            return __H264__isEligibleForHDR
        }
        
        if self.fourCC == .hvc1 {
            return __HEVC__isEligibleForHDR
        }
        
        return .ineligible(reason: .unsupportedCodec)
    }
    
    fileprivate var __H264__isEligibleForHDR: CodecHDREligibility {
        // 1. H.264 코덱의 경우, High10 프로파일만 HDR을 지원합니다.
        guard self.option(.profile) == .kProfileH264High10 else {
            return .ineligible(reason: .unsupportedProfile)
        }
        
        // 2. 10-bit color depth를 지원해야 합니다.
        guard self.option(.colorDepth) == .kColorDepth10Bit else {
            return .ineligible(reason: .unsupportedColorDepth)
        }
        
        /// H.264 High10은 HDR 전송에 적합하지만, 하드웨어 가속을 지원하는 기기가 극히 제한적입니다.
        return .eligibleWithWarnings(warnings: [.performanceIssue])
    }
    
    fileprivate var __HEVC__isEligibleForHDR: CodecHDREligibility {
        /// 1. HEVC 코덱의 경우, Main10 프로파일만 HDR을 지원합니다.
        guard self.option(.profile) == .kProfileHEVCMain10 else {
            return .ineligible(reason: .unsupportedProfile)
        }
        
        /// 2. 10-bit color depth를 지원해야 합니다.
        guard self.option(.colorDepth) == .kColorDepth10Bit else {
            return .ineligible(reason: .unsupportedColorDepth)
        }
        
        return .eligible
    }
}
