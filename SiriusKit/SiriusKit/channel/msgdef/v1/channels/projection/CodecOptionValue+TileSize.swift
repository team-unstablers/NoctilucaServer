//
//  CodecOptionValue+TileSize.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/20/25.
//

public extension CodecOptionValue {
    /// 64x64 타일 크기
    static let kTileSize64x64 = Self(rawValue: "64")
    
    /// 128x128 타일 크기
    static let kTileSize128x128 = Self(rawValue: "128")
    
    /// 256x256 타일 크기
    static let kTileSize256x256 = Self(rawValue: "256")
}
