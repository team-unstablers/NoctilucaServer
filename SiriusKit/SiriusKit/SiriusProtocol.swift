//
//  SiriusProtocol.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/20/25.
//

import Foundation

public struct SiriusProtocolVersion: RawRepresentable, Equatable, Hashable {
    public typealias RawValue = UInt32
    public let rawValue: RawValue
    
    public init(rawValue: RawValue) {
        self.rawValue = rawValue
    }
    
    public static let v1_0: SiriusProtocolVersion = SiriusProtocolVersion(rawValue: 0x0100)
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
    static let hidio = SiriusFeature(rawValue: UUID(uuidString: "405E6E75-8B64-4E8F-91FF-E9E5A2C6BC77")!)
    
    /**
     Projection: 화면 캡쳐를 설정하고 제어합니다.
     */
    static let projection = SiriusFeature(rawValue: UUID(uuidString: "362A7AF0-2AC0-48DE-8F6B-5DB5D01E99DC")!)
    
    /**
     ProjectionData: 화면 캡쳐 데이터를 전송합니다.
     */
    static let projectionData = SiriusFeature(rawValue: UUID(uuidString: "CDE57E7B-9528-47F7-8FEC-14389301A990")!)
}
