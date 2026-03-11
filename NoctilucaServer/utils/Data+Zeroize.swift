//
//  Data+Zeroize.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 3/12/26.
//

import Foundation

extension Data {
    /// Best-effort: Data 내부 버퍼를 0으로 채운다.
    /// COW 특성상 다른 복사본의 메모리까지는 보장하지 않는다.
    mutating func zeroize() {
        guard !self.isEmpty else { return }
        self.withUnsafeMutableBytes { ptr in
            _ = memset_s(ptr.baseAddress!, ptr.count, 0, ptr.count)
        }
    }
}
