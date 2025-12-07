//
//  SoftwareLicense.swift
//  NoctilucaPluginKit
//
//  Created by Gyuhwan Park on 12/5/25.
//

import Foundation

// 확정된 후 @frozen 하고, 바꾸지 마십시오
public indirect enum SoftwareLicense {
    /// Custom License
    case custom(name: String, url: URL?, isOpenSource: Bool)
    
    /// dual (conditional) license
    case dual(SoftwareLicense, SoftwareLicense)
    
    /// Proprietary License
    case proprietary(name: String, url: URL?)
    
    /// MIT License
    case mit
    
    /// Apache License 2.0
    case apache2_0
    
    /// BSD 3-Clause License
    case bsd3
    
    /// GNU General Public License v3.0
    case gplv3
    
    /// GNU Lesser General Public License v3.0
    case lgplv3
    
    /// CC0 1.0 Universal (CC0 1.0) Public Domain Dedication
    case cc0
    
    // 그 외에 더 넣어야 할게 있나...?
}
