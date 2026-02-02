//
//  TiledFrameTests.swift
//  SiriusKitTests
//
//  Created by Codex on 1/2/26.
//

import CoreGraphics
import Foundation
import Testing

@testable import SiriusKit

@Suite("ProjectionFrameTile")
struct ProjectionFrameTileTests {
    @Test("encode writes big-endian layout")
    func encodeWritesExpectedLayout() throws {
        let tile = ProjectionFrameTile(
            geometry: CGRect(x: 10, y: 20, width: 30, height: 40),
            data: Data([0x01, 0x02, 0x03])
        )

        let encoded = try ProjectionFrameTile.encode([tile])
        let expected = Data([
            0x00, 0x00, 0x00, 0x01, // tile_count
            0x00, 0x0A, // x
            0x00, 0x14, // y
            0x00, 0x1E, // w
            0x00, 0x28, // h
            0x00, 0x00, 0x00, 0x03, // data_length
            0x01, 0x02, 0x03 // data
        ])

        #expect(encoded == expected, "encode should produce a big-endian layout")
    }

    @Test("encode/decode round-trip preserves tiles")
    func roundTripPreservesTiles() throws {
        let tiles = [
            ProjectionFrameTile(
                geometry: CGRect(x: 0, y: 0, width: 16, height: 16),
                data: Data([0xAA, 0xBB])
            ),
            ProjectionFrameTile(
                geometry: CGRect(x: 32, y: 48, width: 64, height: 80),
                data: Data()
            )
        ]

        let encoded = try ProjectionFrameTile.encode(tiles)
        let decoded = try ProjectionFrameTile.decode(encoded)

        #expect(decoded.count == tiles.count, "decoded tile count should match")

        for (index, tile) in tiles.enumerated() {
            #expect(decoded[index].geometry == tile.geometry, "decoded geometry should match input")
            #expect(decoded[index].data == tile.data, "decoded data should match input")
        }
    }

    @Test("encode/decode handles empty tiles")
    func emptyTilesRoundTrip() throws {
        let encoded = try ProjectionFrameTile.encode([])
        let expected = Data([0x00, 0x00, 0x00, 0x00])

        #expect(encoded == expected, "empty encode should only contain tile_count")

        let decoded = try ProjectionFrameTile.decode(encoded)
        #expect(decoded.isEmpty, "decoded tiles should be empty")
    }
}
