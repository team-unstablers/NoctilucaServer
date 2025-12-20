//
//  Codec+HDR.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 12/21/25.
//

import Foundation

import SiriusKit

extension Codec {
    var supports10Bit: Bool {
        if self.fourCC == .avc1 {
            return __H264__supports10Bit
        }
        
        if self.fourCC == .hvc1 {
            return __HEVC__supports10Bit
        }
        
        return false
    }
    
    fileprivate var __H264__supports10Bit: Bool {
        guard self.option(.profile) == .kProfileH264High10 else {
            return false
        }
        
        return true
    }
    
    fileprivate var __HEVC__supports10Bit: Bool {
        guard self.option(.profile) == .kProfileHEVCMain10 else {
            return false
        }
        
        return true
    }
}
