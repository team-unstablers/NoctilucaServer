//
//  Bcrypt.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/9/25.
//

import Foundation
import libbcrypt

enum BcryptError: LocalizedError {
    case libraryError(retval: Int32)
    case invalidInput
}

struct Bcrypt {
    private static let authQueue = DispatchQueue(
        label: "app.noctiluca.server.auth.bcrypt",
        qos: .userInitiated,
        attributes: .concurrent
    )

    static func generateSalt(rounds: Int32 = BCRYPT_DEFAULT_WORK_FACTOR) throws -> Data {
        var salt = Data(count: Int(BCRYPT_HASHSIZE))
        
        let retval = salt.withUnsafeMutableBytes { bytes in
            let ptr = bytes.bindMemory(to: Int8.self).baseAddress!
            return bcrypt_gensalt(rounds, ptr)
        }
        
        guard retval == 0 else {
            throw BcryptError.libraryError(retval: retval)
        }
        
        return consume salt
    }
    
    static func hash(password: consuming Data, salt: consuming Data? = nil) throws -> Data {
        let salt = try (salt ?? generateSalt())
        
        guard salt.count == Int(BCRYPT_HASHSIZE) else {
            throw BcryptError.invalidInput
        }
        
        var hash = Data(count: Int(BCRYPT_HASHSIZE))
        
        let retval = password.withUnsafeBytes { passwordBytes in
            salt.withUnsafeBytes { saltBytes in
                hash.withUnsafeMutableBytes { hashBytes in
                    let passwordPtr = passwordBytes.bindMemory(to: Int8.self).baseAddress!
                    let saltPtr = saltBytes.bindMemory(to: Int8.self).baseAddress!
                    let hashPtr = hashBytes.bindMemory(to: Int8.self).baseAddress!
                    
                    return bcrypt_hashpw(passwordPtr, saltPtr, hashPtr)
                }
            }
        }
        
        guard retval == 0 else {
            throw BcryptError.libraryError(retval: retval)
        }
        
        return consume hash
    }
    
    static func sha512(value: borrowing Data) throws -> Data {
        // SECURITY: bcrypt_sha512() 는 입력 길이를 strlen(in) 으로 측정하므로
        //          payload 에 NUL byte 가 포함되면 silently truncate 된다.
        //          서로 다른 payload 가 동일한 SHA-512 digest 로 매핑되는
        //          알고리즘 무결성 결함이 발생하므로 입력 단계에서 차단한다.
        //          (NCH-002 F-1 / S-204)
        guard !value.contains(0) else {
            throw BcryptError.invalidInput
        }

        var hash = Data(count: Int(BCRYPT_512BITS_BASE64_SIZE))

        let retval = value.withUnsafeBytes { valueBytes in
            hash.withUnsafeMutableBytes { hashBytes in
                let valuePtr = valueBytes.bindMemory(to: UInt8.self).baseAddress!
                let hashPtr = hashBytes.bindMemory(to: Int8.self).baseAddress!
                
                return bcrypt_sha512(valuePtr, hashPtr)
            }
        }
        
        guard retval == 0 else {
            throw BcryptError.libraryError(retval: retval)
        }
        
        return consume hash
    }
    
    static func verify(password: borrowing Data, hash: borrowing Data) throws -> Bool {
        guard hash.count == Int(BCRYPT_HASHSIZE) else {
            throw BcryptError.invalidInput
        }

        let retval = password.withUnsafeBytes { passwordBytes in
            hash.withUnsafeBytes { hashBytes in
                let passwordPtr = passwordBytes.bindMemory(to: Int8.self).baseAddress!
                let hashPtr = hashBytes.bindMemory(to: Int8.self).baseAddress!

                return bcrypt_checkpw(passwordPtr, hashPtr)
            }
        }

        switch retval {
        case 0:
            return true
        case 1:
            return false
        default:
            throw BcryptError.libraryError(retval: retval)
        }
    }

    // MARK: - Async wrappers (cooperative thread pool을 블로킹하지 않음)

    static func hashAsync(password: Data, salt: Data? = nil) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            authQueue.async {
                do {
                    let result = try hash(password: password, salt: salt)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func sha512Async(value: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            authQueue.async {
                do {
                    let result = try sha512(value: value)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func verifyAsync(password: Data, hash: Data) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            authQueue.async {
                do {
                    let result = try verify(password: password, hash: hash)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
