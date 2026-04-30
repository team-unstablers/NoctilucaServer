//
//  PAMAuthPlugin+passwd.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/5/25.
//

import Foundation
import Darwin

struct PasswdEntry {
    let uid: uid_t
    let gid: gid_t
    let username: String
}

enum PasswdError: Error {
    case systemError(errno: Int32)
}

struct Passwd {
    private static let initialBufferSize: Int = 16384
    private static let maxBufferSize: Int = 1 << 20  // 1 MiB

    static func __getpwnam(_ username: String) throws -> PasswdEntry? {
        let initial = Self.suggestedBufferSize(for: Int32(_SC_GETPW_R_SIZE_MAX))
        return try Self.withGrowingBuffer(initial: initial) { buffer, bufsize in
            var pwd = passwd()
            var resultPtr: UnsafeMutablePointer<passwd>? = nil
            let retval = getpwnam_r(username, &pwd, buffer, bufsize, &resultPtr)
            return Self.handlePwResult(retval: retval, pwd: pwd, resultPtr: resultPtr)
        }
    }

    static func __getpwuid(_ uid: uid_t) throws -> PasswdEntry? {
        let initial = Self.suggestedBufferSize(for: Int32(_SC_GETPW_R_SIZE_MAX))
        return try Self.withGrowingBuffer(initial: initial) { buffer, bufsize in
            var pwd = passwd()
            var resultPtr: UnsafeMutablePointer<passwd>? = nil
            let retval = getpwuid_r(uid, &pwd, buffer, bufsize, &resultPtr)
            return Self.handlePwResult(retval: retval, pwd: pwd, resultPtr: resultPtr)
        }
    }

    static func __getgrgid_gr_name(_ gid: gid_t) throws -> String? {
        let initial = Self.suggestedBufferSize(for: Int32(_SC_GETGR_R_SIZE_MAX))
        return try Self.withGrowingBuffer(initial: initial) { buffer, bufsize -> LookupOutcome<String> in
            var grp = group()
            var resultPtr: UnsafeMutablePointer<group>? = nil
            let retval = getgrgid_r(gid, &grp, buffer, bufsize, &resultPtr)

            switch retval {
            case 0:
                guard resultPtr != nil else { return .notFound }
                return .found(String(cString: grp.gr_name))
            case ERANGE:
                return .needsMoreSpace
            default:
                return .systemError(errno: retval)
            }
        }
    }

    // MARK: - Private helpers

    private enum LookupOutcome<T> {
        case found(T)
        case notFound
        case needsMoreSpace
        case systemError(errno: Int32)
    }

    private static func suggestedBufferSize(for sysconfKey: Int32) -> Int {
        let value = sysconf(sysconfKey)
        if value <= 0 { return Self.initialBufferSize }
        return max(Int(value), Self.initialBufferSize)
    }

    private static func handlePwResult(
        retval: Int32,
        pwd: passwd,
        resultPtr: UnsafeMutablePointer<passwd>?
    ) -> LookupOutcome<PasswdEntry> {
        switch retval {
        case 0:
            guard resultPtr != nil else { return .notFound }
            return .found(PasswdEntry(
                uid: pwd.pw_uid,
                gid: pwd.pw_gid,
                username: String(cString: pwd.pw_name)
            ))
        case ERANGE:
            return .needsMoreSpace
        default:
            return .systemError(errno: retval)
        }
    }

    private static func withGrowingBuffer<T>(
        initial: Int,
        body: (UnsafeMutablePointer<CChar>, Int) -> LookupOutcome<T>
    ) throws -> T? {
        var bufsize = initial
        while true {
            var buffer = [CChar](repeating: 0, count: bufsize)
            let outcome = buffer.withUnsafeMutableBufferPointer { ptr -> LookupOutcome<T> in
                return body(ptr.baseAddress!, bufsize)
            }

            switch outcome {
            case .found(let value):
                return value
            case .notFound:
                return nil
            case .needsMoreSpace:
                let next = bufsize * 2
                if next > Self.maxBufferSize {
                    throw PasswdError.systemError(errno: ERANGE)
                }
                bufsize = next
                continue
            case .systemError(let err):
                throw PasswdError.systemError(errno: err)
            }
        }
    }
}
