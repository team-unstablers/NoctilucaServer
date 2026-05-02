//
//  SiriusFrameStreamDecoder.swift
//  SiriusKit
//
//  Created by Codex on 2/13/26.
//

import Foundation

/// 프레임 디코더에서 발생할 수 있는 오류.
public enum SiriusFrameDecoderError: Error, Equatable, Sendable {
    /// 선언된 페이로드 길이가 프로토콜의 최대 프레임 크기 상한을 초과했습니다.
    /// spec: general introduction의 "FRAME SIZE LIMIT" 섹션 참조.
    case frameTooLarge(declaredLength: UInt32, limit: Int)
}

/// Incremental Sirius frame decoder for stream-based transports.
///
/// Frame format:
/// [opcode: 2 bytes BE] [length: 4 bytes BE] [payload: length bytes]
package struct SiriusFrameStreamDecoder {
    private static let headerSize: Int = 6

    /// 프로토콜이 정한 최대 프레임 페이로드 크기 (16 MiB).
    public static let maxPayloadSize: Int = 16 * 1024 * 1024

    private var storage: Data
    private var readOffset: Int
    private let compactThreshold: Int

    package init(initialCapacity: Int = 64 * 1024, compactThreshold: Int = 64 * 1024) {
        self.storage = Data()
        self.storage.reserveCapacity(initialCapacity)
        self.readOffset = 0
        self.compactThreshold = max(compactThreshold, Self.headerSize)
    }

    package var bufferedByteCount: Int {
        max(0, self.storage.count - self.readOffset)
    }

    package var storageByteCount: Int {
        self.storage.count
    }

    package var consumedPrefixByteCount: Int {
        self.readOffset
    }

    package mutating func append(_ chunk: Data) {
        guard !chunk.isEmpty else {
            return
        }

        self.storage.append(chunk)
    }

    package mutating func nextFrame() throws -> SiriusFrame? {
        let available = self.storage.count - self.readOffset
        guard available >= Self.headerSize else {
            return nil
        }

        let headerStart = self.readOffset
        let opcode =
            (UInt16(self.storage[headerStart]) << 8)
            | UInt16(self.storage[headerStart + 1])
        let length =
            (UInt32(self.storage[headerStart + 2]) << 24)
            | (UInt32(self.storage[headerStart + 3]) << 16)
            | (UInt32(self.storage[headerStart + 4]) << 8)
            | UInt32(self.storage[headerStart + 5])

        let payloadLength = Int(length)
        guard payloadLength <= Self.maxPayloadSize else {
            throw SiriusFrameDecoderError.frameTooLarge(
                declaredLength: length,
                limit: Self.maxPayloadSize
            )
        }

        let frameSize = Self.headerSize + payloadLength
        guard available >= frameSize else {
            return nil
        }

        let payloadStart = headerStart + Self.headerSize
        let payloadEnd = payloadStart + payloadLength
        let payload = payloadLength > 0
            ? Data(self.storage[payloadStart..<payloadEnd])
            : Data()

        self.readOffset = payloadEnd
        self.compactIfNeeded()

        return SiriusFrame(
            opcode: MessageOpcode(rawValue: opcode),
            length: length,
            data: payload
        )
    }

    private mutating func compactIfNeeded() {
        guard self.readOffset > 0 else {
            return
        }

        let remaining = self.storage.count - self.readOffset
        let shouldCompact =
            self.readOffset >= self.compactThreshold
            || self.readOffset >= (self.storage.count / 2)

        guard shouldCompact else {
            return
        }

        if remaining == 0 {
            self.storage.removeAll(keepingCapacity: true)
            self.readOffset = 0
            return
        }

        self.storage = Data(self.storage[self.readOffset..<self.storage.count])
        self.readOffset = 0
    }
}
