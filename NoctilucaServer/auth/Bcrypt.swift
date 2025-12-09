//
//  Bcrypt.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/9/25.
//

import libbcrypt

enum BcryptError: LocalizedError {
    case libraryError(retval: Int32)
    case invalidInput
}

struct Bcrypt {
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
    
    /// FIXME: UI 스레드에서 호출하지 않도록 할것
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
    
    static func sha512(value: consuming Data) throws -> Data {
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
    
    static func verify(password: consuming Data, hash: consuming Data) throws -> Bool {
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
}
