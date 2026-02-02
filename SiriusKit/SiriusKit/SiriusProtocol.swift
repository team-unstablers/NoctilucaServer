//
//  SiriusProtocol.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/20/25.
//
// swiftlint:disable identifier_name

import Foundation


/**
 # Sirius Protocol Version
  
 0x0001_0203
   |-- 0x0001: 프로토콜 메이저 버전
   |-- 0x02: 프로토콜 마이너 버전
   |-- 0x03: 리비전 넘버
 */
public struct SiriusProtocolVersion: RawRepresentable, Equatable, Hashable {
    public typealias RawValue = UInt32
    public let rawValue: RawValue
    
    public init(rawValue: RawValue) {
        self.rawValue = rawValue
    }
    
    public var majorVersion: UInt16 {
        return UInt16((rawValue & 0xFFFF_0000) >> 16)
    }
    
    public var minorVersion: UInt8 {
        return UInt8((rawValue & 0x0000_FF00) >> 8)
    }
    
    public var revisionNumber: UInt8 {
        return UInt8(rawValue & 0x0000_00FF)
    }
    
    public var displayVersion: String {
        return "\(majorVersion).\(minorVersion).\(revisionNumber)"
    }
    
    public func mutating(majorVersion: UInt16) -> Self {
        let newRawValue = (UInt32(majorVersion) << 16) | (rawValue & 0x0000_FFFF)
        return SiriusProtocolVersion(rawValue: newRawValue)
    }
    
    public func mutating(minorVersion: UInt8) -> Self {
        let newRawValue = (rawValue & 0xFFFF_00FF) | (UInt32(minorVersion) << 8)
        return SiriusProtocolVersion(rawValue: newRawValue)
    }
    
    public func mutating(revisionNumber: UInt8) -> Self {
        let newRawValue = (rawValue & 0xFFFF_FF00) | UInt32(revisionNumber)
        return SiriusProtocolVersion(rawValue: newRawValue)
    }
    
    public static let v1_0: SiriusProtocolVersion = SiriusProtocolVersion(rawValue: 0x0001_0000)
}



public struct SiriusFeature: RawRepresentable, Equatable, Hashable {
    public typealias RawValue = UUID
    public let rawValue: UUID
    
    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
    
    /**
     HIDIO: 키보드 / 마우스 등의 HID 입력을 리디렉션합니다.
     */
    public static let hidio = SiriusFeature(rawValue: UUID(uuidString: "405E6E75-8B64-4E8F-91FF-E9E5A2C6BC77")!)
    
    /**
     Projection: 화면 캡쳐를 설정하고 제어합니다.
     */
    public static let projection = SiriusFeature(rawValue: UUID(uuidString: "362A7AF0-2AC0-48DE-8F6B-5DB5D01E99DC")!)
    
    /**
     ProjectionData: 화면 캡쳐 데이터를 전송합니다.
     */
    public static let projectionData = SiriusFeature(rawValue: UUID(uuidString: "CDE57E7B-9528-47F7-8FEC-14389301A990")!)
}
