//
//  Data+SiriusMessage.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/23/25.
//

import Foundation
internal import SwiftProtobuf

public struct SiriusFrame {
    /// 프레임 헤더 크기 (opcode 2바이트 + length 4바이트)
    public static let headerSize: Int = 6

    public let opcode: MessageOpcode
    public let length: UInt32

    public let data: Data

    public init(opcode: MessageOpcode, length: UInt32, data: Data) {
        self.opcode = opcode
        self.length = length
        self.data = data
    }

    public func isValid() -> Bool {
        return data.count == Int(length)
    }
}

package extension Data {
    func toSiriusFrame() -> SiriusFrame? {
        // assert: self.count() >= (sizeof(UInt16) + sizeof(UInt32))
        guard self.count >= 6 else {
            return nil
        }

        let opcodeData = self.subdata(in: 0..<2)
        let lengthData = self.subdata(in: 2..<6)

        let opcode = opcodeData.withUnsafeBytes { ptr -> UInt16 in
            return ptr.load(as: UInt16.self).bigEndian
        }

        let length = lengthData.withUnsafeBytes { ptr -> UInt32 in
            return ptr.load(as: UInt32.self).bigEndian
        }

        let messageData = self.subdata(in: 6..<self.count)

        return SiriusFrame(opcode: MessageOpcode(rawValue: opcode),
                           length: length, data: messageData)
    }
}
