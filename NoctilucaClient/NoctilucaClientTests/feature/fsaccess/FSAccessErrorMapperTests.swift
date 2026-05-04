//
//  FSAccessErrorMapperTests.swift
//  NoctilucaClientTests
//
//  Created by Gyuhwan Park on 5/4/26.
//

import XCTest
import Darwin
@testable import Noctiluca_Navigator
import SiriusKitClient

final class FSAccessErrorMapperTests: XCTestCase {
    // MARK: - mapErrno

    // FileSystemErrorCode 의 static let 들은 SiriusKitCore binary 에 정의되어 있고 테스트 타깃은
    // 해당 framework 와 직접 link 되지 않는다 (현재 link 그래프 기준). raw value 비교로 우회한다.
    // 이 raw value 들은 fsaccess.mdproto.md / fsaccess+Constants.swift 에서 정본으로 확인 가능.
    private enum FSErr {
        static let `internal`: UInt32 = 1
        static let invalidArgument: UInt32 = 2
        static let notSupported: UInt32 = 3
        static let invalidHandle: UInt32 = 10
        static let notFound: UInt32 = 20
        static let alreadyExists: UInt32 = 21
        static let notDirectory: UInt32 = 22
        static let isDirectory: UInt32 = 23
        static let notEmpty: UInt32 = 24
        static let pathTooLong: UInt32 = 25
        static let loop: UInt32 = 26
        static let crossDevice: UInt32 = 28
        static let accessDenied: UInt32 = 40
        static let permissionDenied: UInt32 = 41
        static let readOnlyFilesystem: UInt32 = 42
        static let consentDenied: UInt32 = 44
        static let diskFull: UInt32 = 60
        static let fileTooLarge: UInt32 = 61
        static let quotaExceeded: UInt32 = 62
        static let tooManyHandles: UInt32 = 63
        static let busy: UInt32 = 80
        static let staleHandle: UInt32 = 81
        static let ioError: UInt32 = 90
    }

    func testMapsKnownErrnos() {
        let cases: [(Int32, UInt32)] = [
            (ENOENT, FSErr.notFound),
            (EEXIST, FSErr.alreadyExists),
            (ENOTDIR, FSErr.notDirectory),
            (EISDIR, FSErr.isDirectory),
            (ENOTEMPTY, FSErr.notEmpty),
            (ENAMETOOLONG, FSErr.pathTooLong),
            (ELOOP, FSErr.loop),
            (EXDEV, FSErr.crossDevice),
            (EACCES, FSErr.accessDenied),
            (EPERM, FSErr.permissionDenied),
            (EROFS, FSErr.readOnlyFilesystem),
            (ENOSPC, FSErr.diskFull),
            (EFBIG, FSErr.fileTooLarge),
            (EDQUOT, FSErr.quotaExceeded),
            (EBUSY, FSErr.busy),
            (ETXTBSY, FSErr.busy),
            (ESTALE, FSErr.staleHandle),
            (EIO, FSErr.ioError),
            (EBADF, FSErr.invalidHandle),
            (EINVAL, FSErr.invalidArgument),
            (ENOTSUP, FSErr.notSupported),
        ]

        for (errnoValue, expectedRaw) in cases {
            let actual = FSAccessErrorMapper.mapErrno(errnoValue)
            XCTAssertEqual(actual.rawValue, expectedRaw, "errno=\(errnoValue) expected \(expectedRaw), got \(actual.rawValue)")
        }
    }

    func testTooManyHandlesCoversBothEMFILEAndENFILE() {
        XCTAssertEqual(FSAccessErrorMapper.mapErrno(EMFILE).rawValue, FSErr.tooManyHandles)
        XCTAssertEqual(FSAccessErrorMapper.mapErrno(ENFILE).rawValue, FSErr.tooManyHandles)
    }

    func testEOPNOTSUPPMapsToNotSupported() {
        // ENOTSUP / EOPNOTSUPP 는 macOS 에서 같은 값을 가지지만, mapping 이 둘 다 .notSupported 인지 확인.
        XCTAssertEqual(FSAccessErrorMapper.mapErrno(EOPNOTSUPP).rawValue, FSErr.notSupported)
    }

    func testUnknownErrnoFallsBackToInternal() {
        // 99999 는 어떤 표준 errno 도 사용하지 않는 값.
        XCTAssertEqual(FSAccessErrorMapper.mapErrno(99999).rawValue, FSErr.internal)
        // 0 은 "no error" 이지만 mapping 표 어디에도 없으므로 internal.
        XCTAssertEqual(FSAccessErrorMapper.mapErrno(0).rawValue, FSErr.internal)
    }

    // MARK: - errorInfo (no-errno builder)

    func testErrorInfoWithoutErrnoSetsNilPlatformFields() {
        // SiriusKitCore.FileSystemErrorCode 의 init/static-let 들은 우리 test 타깃에서 link 되지 않으므로,
        // mapErrno 가 반환한 값을 그대로 재사용해 init 직접 호출을 피한다.
        let code = FSAccessErrorMapper.mapErrno(EACCES)  // → accessDenied
        let info = FSAccessErrorMapper.errorInfo(code, message: "Filesystem rejected the operation")
        XCTAssertEqual(info.code.rawValue, FSErr.accessDenied)
        XCTAssertEqual(info.message, "Filesystem rejected the operation")
        XCTAssertNil(info.platformCode)
        XCTAssertNil(info.platformName)
    }

    // MARK: - errorInfoFromErrno

    func testErrorInfoFromErrnoCapturesCurrentErrno() {
        // errno 를 명시적으로 세팅한 뒤 wrapper 호출.
        errno = ENOENT
        let info = FSAccessErrorMapper.errorInfoFromErrno(message: "open(/missing) failed")

        XCTAssertEqual(info.code.rawValue, FSErr.notFound)
        XCTAssertEqual(info.platformCode, ENOENT)
        // platformName 은 strerror 결과 — macOS 에서는 "No such file or directory".
        XCTAssertNotNil(info.platformName)
        // message 에는 우리가 넘긴 prefix + errno + platformName 이 포함되어야 한다.
        XCTAssertTrue(info.message.contains("open(/missing) failed"), "expected prefix in message: \(info.message)")
        XCTAssertTrue(info.message.contains("errno=\(ENOENT)"), "expected errno in message: \(info.message)")
    }

    func testErrorInfoFromErrnoWithUnknownErrnoUsesInternalCode() {
        errno = 99999
        let info = FSAccessErrorMapper.errorInfoFromErrno(message: "whatever")
        XCTAssertEqual(info.code.rawValue, FSErr.internal)
        XCTAssertEqual(info.platformCode, 99999)
    }
}
