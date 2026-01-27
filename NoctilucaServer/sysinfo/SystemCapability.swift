//
//  SystemCapability.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 1/1/26.
//

import Darwin

struct SystemCapability {
    static var isVirtualMachine: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("kern.hv_vmm_present", &value, &size, nil, 0)
        return result == 0 && value == 1
    }
}
