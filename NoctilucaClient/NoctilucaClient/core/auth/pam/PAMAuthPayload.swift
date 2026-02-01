//
//  PAMPayload.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/11/25.
//

import Foundation

internal struct PAMAuthPayload {
    static func __usernameLength(from payload: borrowing Data) -> UInt32 {
        payload.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
    }
    
    static func __passwordLength(from payload: borrowing Data) -> UInt32 {
        payload.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
    }
    
    static func validate(payload: borrowing Data) -> Bool {
        // [uint32_t: username length] [uint32_t: password length] [username bytes] [password bytes]
        
        guard payload.count >= 8 else {
            return false
        }
        
        let usernameLength = __usernameLength(from: payload)
        let passwordLength = __passwordLength(from: payload)
        
        return payload.count == 8 + Int(usernameLength) + Int(passwordLength)
    }
    
    static func payload(username: consuming String, password: consuming String) -> Data {
        // TODO: 이거 메모리에 안 남아야 함
        let size = (4 + 4) + username.utf8.count + password.utf8.count
        
        var payload = Data(count: size)
        
        withUnsafeBytes(of: UInt32(username.utf8.count).bigEndian) { lengthBytes in
            payload.replaceSubrange(0..<4, with: lengthBytes)
        }
        
        withUnsafeBytes(of: UInt32(password.utf8.count).bigEndian) { lengthBytes in
            payload.replaceSubrange(4..<8, with: lengthBytes)
        }
        
        payload.replaceSubrange(8..<(8 + username.utf8.count), with: username.utf8)
        payload.replaceSubrange((8 + username.utf8.count)..<size, with: password.utf8)
        
        assert(validate(payload: payload), "Generated PAM auth payload is invalid")
        
        return consume payload
    }
    
    static func username(from payload: borrowing Data) -> Data {
        let usernameLength = __usernameLength(from: payload)
        let usernameData = payload.subdata(in: 8..<(8 + Int(usernameLength)))
        
        return usernameData
    }
    
    static func password(from payload: borrowing Data) -> Data {
        let usernameLength = __usernameLength(from: payload)
        let passwordLength = __passwordLength(from: payload)
        let passwordData = payload.subdata(in: (8 + Int(usernameLength))..<(8 + Int(usernameLength) + Int(passwordLength)))
        
        return passwordData
    }
}
