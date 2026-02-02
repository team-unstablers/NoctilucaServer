//
//  TiledFrame.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 1/3/26.
//

import Foundation

import CoreGraphics

/// ZRLE, MJPG 등에서 tiled-형식 프레임을 표현하기 위한 구조체입니다.
public struct ProjectionFrameTile {
    /// 타일을 표시할 위치. 픽셀 단위.
    public let geometry: CGRect
    
    /// 타일 데이터.
    public let data: Data
    
    public init(geometry: CGRect, data: Data) {
        self.geometry = geometry
        self.data = data
    }
}

// TODO: 유닛 테스트 작성할 것
public extension ProjectionFrameTile {
    /// [ tile_count: UInt32 ] [ [ geometry: (x, y, w, h: UInt16) ] [ data_length: UInt32 ] [ data: bytes ] ]
    
    static func decode(_ data: borrowing Data) throws -> [ProjectionFrameTile] {
        let tileCount = data.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        var offset = 4
        
        var tiles: [ProjectionFrameTile] = []
        tiles.reserveCapacity(Int(tileCount))
        
        for _ in 0..<tileCount {
            let x = data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
            offset += 2
            let y = data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
            offset += 2
            let w = data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
            offset += 2
            let h = data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
            offset += 2
            
            let dataLength = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            offset += 4
            
            let tileData = data.subdata(in: offset..<(offset + Int(dataLength)))
            offset += Int(dataLength)
            
            let geometry = CGRect(x: Int(x), y: Int(y), width: Int(w), height: Int(h))
            let tile = ProjectionFrameTile(geometry: geometry, data: consume tileData)
            tiles.append(consume tile)
        }
        
        return consume tiles
    }
    
    static func encode(_ tiles: [ProjectionFrameTile]) throws -> Data {
        var data = Data()
        
        let tileCount = UInt32(tiles.count)
        data.append(withUnsafeBytes(of: tileCount.bigEndian) { Data($0) })
        
        for tile in tiles {
            let x = UInt16(tile.geometry.origin.x)
            let y = UInt16(tile.geometry.origin.y)
            let w = UInt16(tile.geometry.size.width)
            let h = UInt16(tile.geometry.size.height)
            
            data.append(withUnsafeBytes(of: x.bigEndian) { Data($0) })
            data.append(withUnsafeBytes(of: y.bigEndian) { Data($0) })
            data.append(withUnsafeBytes(of: w.bigEndian) { Data($0) })
            data.append(withUnsafeBytes(of: h.bigEndian) { Data($0) })
            
            let dataLength = UInt32(tile.data.count)
            data.append(withUnsafeBytes(of: dataLength.bigEndian) { Data($0) })
            data.append(tile.data)
        }
        
        return consume data
    }
}


