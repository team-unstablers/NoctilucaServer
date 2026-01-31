//
//  UUID+msgdef.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/20/25.
//

import Foundation

extension UUID {
    /// 이거 졸라느릴거같은데 ㅋㅋㅋ;
    init(msgdef: Sirius_Msgdef_SRUUID) {
        var uuidBytes = [UInt8](repeating: 0, count: 16)
        let data = msgdef.value
        data.copyBytes(to: &uuidBytes, count: min(data.count, uuidBytes.count))
        self = UUID(uuid: (
            uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
            uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
            uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        ))
    }
    
    func asMsgDef() -> Sirius_Msgdef_SRUUID {
        var container = Sirius_Msgdef_SRUUID()
        
        withUnsafeBytes(of: self.uuid) { bytes in
            container.value = Data(bytes: bytes.baseAddress!, count: bytes.count)
        }
        
        return container
    }
}
