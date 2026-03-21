//
//  SystemCapability+Identifier.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 3/6/26.
//

import Darwin
import IOKit

import CryptoKit

extension SystemCapability {
    private static func ioKitHardwareIdentifier() -> String? {
        // IOKit을 사용하여 플랫폼 전문가 기기 객체를 가져옵니다.
        let matchingDict = IOServiceMatching("IOPlatformExpertDevice")
        let platformExpert = IOServiceGetMatchingService(kIOMainPortDefault, matchingDict)
        guard platformExpert != 0 else { return nil }
        
        defer { IOObjectRelease(platformExpert) }
        
        // 기기의 고유 UUID 속성을 읽어옵니다.
        if let uuidCFString = IORegistryEntryCreateCFProperty(platformExpert, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
            return uuidCFString
        }
        return nil
    }
    
    /// '안전한' 하드웨어 식별자를 취득합니다.
    /// - '안전한' 이라고 부르는 이유는, 이 식별자로는 사람들을 추적할 수 없고, 그래선 안되기 때문입니다.
    /// - 나쁜 사람들을 얼마든지 이 식별자와 라이선스 시스템을 속일 수 있겠지만, 그래도 사람들을 믿고 싶습니다.
    static func hardwareIdentifier() -> String? {
        guard let ioKitIdentifier = ioKitHardwareIdentifier(),
              let bundleID = Bundle.main.bundleIdentifier
        else {
            return nil
        }
        
        // 기기 UUID와 앱 식별자를 결합 (이 앱에서만 유효한 고유 문자열 생성)
        let combinedString = "\(ioKitIdentifier)-\(bundleID)"
        
        // SHA-256으로 해싱하여 복구 및 역추적이 불가능한 안전한 문자열로 변환
        guard let data = combinedString.data(using: .utf8) else { return nil }
        let hashed = SHA512.hash(data: data)
        
        // 해시값을 64자리의 String(Hex)으로 변환
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}
