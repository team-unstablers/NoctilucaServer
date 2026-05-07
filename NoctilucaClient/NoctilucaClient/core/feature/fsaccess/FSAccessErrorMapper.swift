//
//  FSAccessErrorMapper.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 5/4/26.
//

import Foundation
import Darwin

import SiriusKitClient

/// POSIX errno 와 `FileSystemErrorCode` 사이의 매핑을 담당합니다.
///
/// 매핑 표는 `fsaccess.mdproto.md` 의 `FileSystemErrorCode` 섹션을 따릅니다.
/// 알 수 없는 errno 는 `.internal` 로 폴백합니다 — 수신측은 unknown code 도 동일하게
/// `.internal` 로 처리하므로 유실 정보 없이 보존됩니다.
enum FSAccessErrorMapper {
    static func mapErrno(_ errnoValue: Int32) -> FileSystemErrorCode {
        switch errnoValue {
        case ENOENT: return .notFound
        case EEXIST: return .alreadyExists
        case ENOTDIR: return .notDirectory
        case EISDIR: return .isDirectory
        case ENOTEMPTY: return .notEmpty
        case ENAMETOOLONG: return .pathTooLong
        case ELOOP: return .loop
        case EXDEV: return .crossDevice
        case EACCES: return .accessDenied
        case EPERM: return .permissionDenied
        case EROFS: return .readOnlyFilesystem
        case ENOSPC: return .diskFull
        case EFBIG: return .fileTooLarge
        case EDQUOT: return .quotaExceeded
        case EMFILE, ENFILE: return .tooManyHandles
        case EBUSY, ETXTBSY: return .busy
        case ESTALE: return .staleHandle
        case EIO: return .ioError
        case EBADF: return .invalidHandle
        case EINVAL: return .invalidArgument
        case ENOTSUP, EOPNOTSUPP: return .notSupported
        default: return .internal
        }
    }

    /// 가장 최근의 `errno` 값을 읽고 `ErrorInfo` 로 감쌉니다.
    /// `message` 에는 호출자가 진단을 위해 필요한 컨텍스트를 자세히 적어 주세요.
    static func errorInfoFromErrno(message: String) -> ErrorInfo {
        let errnoValue = errno
        let code = mapErrno(errnoValue)
        let platformName = String(cString: strerror(errnoValue))
        return ErrorInfo(
            code: code,
            message: "\(message) (errno=\(errnoValue) \(platformName))",
            platformCode: errnoValue,
            platformName: platformName
        )
    }

    static func errorInfo(_ code: FileSystemErrorCode, message: String) -> ErrorInfo {
        ErrorInfo(code: code, message: message, platformCode: nil, platformName: nil)
    }
}
