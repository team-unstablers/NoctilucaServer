//
//  CInteropHandle.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/21/25.
//

import Foundation

protocol CInteropHandle: AnyObject {
    
}

extension CInteropHandle {
    /// C function의 userInfo / context 핸들(포인터)로부터 자기 자신을 복원합니다.
    @inlinable
    static func fromCInteropHandle(_ handle: UnsafeMutableRawPointer) -> Self {
        return Unmanaged<Self>.fromOpaque(handle).takeUnretainedValue()
    }
    
    /// C function의 userInfo / context 핸들(포인터)로 전달할 자기 자신의 포인터를 반환합니다.
    var asCInteropHandle: UnsafeMutableRawPointer {
        Unmanaged.passUnretained(self).toOpaque()
    }
}


