//
//  SiriusFrameStreamDecoderTests.swift
//  SiriusKitTests
//
//  Created by Codex on 2/13/26.
//

import Foundation
import Testing

@testable import SiriusKitCore

@Suite("SiriusFrameStreamDecoder")
struct SiriusFrameStreamDecoderTests {
    @Test("1바이트 단위 fragmentation을 정상 복원한다")
    func decodesFragmentedInputByteByByte() {
        let frameA = makeFrame(opcode: 0x1001, payload: Data("alpha".utf8))
        let frameB = makeFrame(opcode: 0x1002, payload: Data("beta".utf8))
        var streamBytes = Data()
        streamBytes.append(frameA)
        streamBytes.append(frameB)

        var decoder = SiriusFrameStreamDecoder()
        var decoded: [SiriusFrame] = []

        for byte in streamBytes {
            decoder.append(Data([byte]))
            while let frame = decoder.nextFrame() {
                decoded.append(frame)
            }
        }

        #expect(decoded.count == 2)
        #expect(decoded[0].opcode == MessageOpcode(rawValue: 0x1001))
        #expect(decoded[0].data == Data("alpha".utf8))
        #expect(decoded[1].opcode == MessageOpcode(rawValue: 0x1002))
        #expect(decoded[1].data == Data("beta".utf8))
        #expect(decoder.bufferedByteCount == 0)
    }

    @Test("coalesced chunk에서 연속 프레임을 추출한다")
    func decodesCoalescedFrames() {
        let frameA = makeFrame(opcode: 0x2001, payload: Data("a".utf8))
        let frameB = makeFrame(opcode: 0x2002, payload: Data("bb".utf8))
        let frameC = makeFrame(opcode: 0x2003, payload: Data("ccc".utf8))

        var decoder = SiriusFrameStreamDecoder()
        var coalesced = Data()
        coalesced.append(frameA)
        coalesced.append(frameB)
        coalesced.append(frameC)
        decoder.append(coalesced)

        let first = decoder.nextFrame()
        let second = decoder.nextFrame()
        let third = decoder.nextFrame()
        let fourth = decoder.nextFrame()

        #expect(first?.opcode == MessageOpcode(rawValue: 0x2001))
        #expect(first?.data == Data("a".utf8))
        #expect(second?.opcode == MessageOpcode(rawValue: 0x2002))
        #expect(second?.data == Data("bb".utf8))
        #expect(third?.opcode == MessageOpcode(rawValue: 0x2003))
        #expect(third?.data == Data("ccc".utf8))
        #expect(fourth == nil)
    }

    @Test("빈 payload 프레임을 처리한다")
    func decodesEmptyPayloadFrame() {
        let emptyPayload = Data()
        let encoded = makeFrame(opcode: 0x3001, payload: emptyPayload)

        var decoder = SiriusFrameStreamDecoder()
        decoder.append(encoded)
        let decoded = decoder.nextFrame()

        #expect(decoded?.opcode == MessageOpcode(rawValue: 0x3001))
        #expect(decoded?.length == 0)
        #expect(decoded?.data == emptyPayload)
        #expect(decoder.nextFrame() == nil)
    }

    @Test("대형 payload 프레임을 처리한다")
    func decodesLargePayloadFrame() {
        let payload = Data(repeating: 0xAB, count: 256 * 1024)
        let encoded = makeFrame(opcode: 0x4001, payload: payload)

        var decoder = SiriusFrameStreamDecoder()
        decoder.append(encoded)
        let decoded = decoder.nextFrame()

        #expect(decoded?.opcode == MessageOpcode(rawValue: 0x4001))
        #expect(decoded?.length == UInt32(payload.count))
        #expect(decoded?.data == payload)
        #expect(decoder.nextFrame() == nil)
    }

    @Test("부분 헤더와 부분 payload 누적 후 프레임을 완성한다")
    func decodesAfterPartialHeaderAndPayloadArrival() {
        let payload = Data("partial-payload".utf8)
        let encoded = makeFrame(opcode: 0x5001, payload: payload)

        var decoder = SiriusFrameStreamDecoder()

        decoder.append(encoded.prefix(3))
        #expect(decoder.nextFrame() == nil)

        decoder.append(encoded[3..<6])
        #expect(decoder.nextFrame() == nil)

        decoder.append(encoded[6..<(6 + 4)])
        #expect(decoder.nextFrame() == nil)

        decoder.append(encoded[(6 + 4)...])
        let decoded = decoder.nextFrame()

        #expect(decoded?.opcode == MessageOpcode(rawValue: 0x5001))
        #expect(decoded?.data == payload)
        #expect(decoder.nextFrame() == nil)
        #expect(decoder.bufferedByteCount == 0)
    }

    @Test("consumed prefix가 임계치를 넘으면 compaction이 수행된다")
    func compactsConsumedPrefixWhenThresholdIsExceeded() {
        let payloadA = Data(repeating: 0x01, count: 24)
        let payloadB = Data(repeating: 0x02, count: 24)
        let frameA = makeFrame(opcode: 0x6001, payload: payloadA)
        let frameB = makeFrame(opcode: 0x6002, payload: payloadB)

        var decoder = SiriusFrameStreamDecoder(compactThreshold: 8)
        var coalesced = Data()
        coalesced.append(frameA)
        coalesced.append(frameB)
        decoder.append(coalesced)

        let first = decoder.nextFrame()

        #expect(first?.opcode == MessageOpcode(rawValue: 0x6001))
        #expect(first?.data == payloadA)
        #expect(decoder.consumedPrefixByteCount == 0)
        #expect(decoder.storageByteCount == frameB.count)
        #expect(decoder.bufferedByteCount == frameB.count)

        let second = decoder.nextFrame()
        #expect(second?.opcode == MessageOpcode(rawValue: 0x6002))
        #expect(second?.data == payloadB)
        #expect(decoder.bufferedByteCount == 0)
    }

    private func makeFrame(opcode: UInt16, payload: Data) -> Data {
        var encoded = Data()
        let opcodeBE = opcode.bigEndian
        let payloadLengthBE = UInt32(payload.count).bigEndian

        withUnsafeBytes(of: opcodeBE) { encoded.append(contentsOf: $0) }
        withUnsafeBytes(of: payloadLengthBE) { encoded.append(contentsOf: $0) }
        encoded.append(payload)

        return encoded
    }
}
