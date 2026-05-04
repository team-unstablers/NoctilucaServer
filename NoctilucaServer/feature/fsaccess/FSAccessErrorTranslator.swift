//
//  FSAccessErrorTranslator.swift
//  NoctilucaServer
//
//  Sirius `FileSystemErrorCode` (navigator 가 응답으로 보냄) → POSIX errno 매핑.
//  방향이 NoctilucaClient 의 `FSAccessErrorMapper` 와 반대다 (host = consuming peer
//  이므로 받은 코드를 errno 로 환원해서 데몬에 NSError 로 보낸다).
//

import Foundation

import SiriusKit

import NocFSAccessXPC

enum FSAccessErrorTranslator {
    /// `FileSystemErrorCode` → Darwin errno.
    /// 매핑되지 않은 코드는 `EIO` 로 환원 (데몬은 이 값을 `NFSError.serverFault` 로 처리).
    private static let posixMap: [FileSystemErrorCode: Int32] = [
        .notFound: ENOENT,
        .alreadyExists: EEXIST,
        .notDirectory: ENOTDIR,
        .isDirectory: EISDIR,
        .notEmpty: ENOTEMPTY,
        .pathTooLong: Int32(ENAMETOOLONG),
        .loop: ELOOP,
        .crossDevice: EXDEV,
        .accessDenied: EACCES,
        .permissionDenied: EPERM,
        .readOnlyFilesystem: EROFS,
        .diskFull: ENOSPC,
        .fileTooLarge: EFBIG,
        .quotaExceeded: EDQUOT,
        .tooManyHandles: EMFILE,
        .busy: EBUSY,
        .staleHandle: ESTALE,
        .ioError: EIO,
        .invalidHandle: EBADF,
        .invalidArgument: EINVAL,
        .notSupported: ENOTSUP,
        .invalidPath: EINVAL,
        .invalidSession: ESTALE,
        .notMounted: ESTALE,
        .channelClosing: ESTALE,
        .consentDenied: EACCES,
        .policyViolation: EACCES,
    ]

    static func toPosixErrno(_ code: FileSystemErrorCode) -> Int32 {
        return posixMap[code] ?? EIO
    }

    /// `FileSystemErrorCode` + 진단 메시지 → `NSError` (대부분 `NSPOSIXErrorDomain`).
    /// 데몬 측 `NoctilucaNFSServer` 가 이 NSError 의 errno 를 그대로 `NFSError` 매핑에
    /// 사용한다.
    static func toNSError(_ code: FileSystemErrorCode, message: String? = nil) -> NSError {
        return .nocFSPosix(toPosixErrno(code), message: message)
    }

    /// fsaccess_mount 응답의 `ErrorInfo` → `NSError`. `code` 가 매핑 가능하면
    /// POSIX 도메인, 아니면 ``NocFSAccessXPCErrorDomain`` 을 사용한다.
    static func toNSError(_ info: ErrorInfo) -> NSError {
        let composed = info.message.isEmpty
            ? "FileSystemErrorCode \(info.code.rawValue)"
            : "\(info.message) [code=\(info.code.rawValue)]"
        return toNSError(info.code, message: composed)
    }
}
