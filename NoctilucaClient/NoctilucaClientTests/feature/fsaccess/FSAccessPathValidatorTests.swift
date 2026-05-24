//
//  FSAccessPathValidatorTests.swift
//  NoctilucaClientTests
//
//  Created by Gyuhwan Park on 5/4/26.
//

import XCTest
import SiriusKitClient
@testable import Noctiluca_Navigator

final class FSAccessPathValidatorTests: XCTestCase {
    private let mountRoot = URL(fileURLWithPath: "/Users/test/share").standardizedFileURL

    // MARK: - Normalization

    func testResolvesPlainPath() throws {
        let url = try FSAccessPathValidator.resolve(path: "subdir/file.txt", mountRoot: mountRoot)
        XCTAssertEqual(url.path, "/Users/test/share/subdir/file.txt")
    }

    func testLeadingSlashIsTreatedAsMountRoot() throws {
        let url = try FSAccessPathValidator.resolve(path: "/subdir/file.txt", mountRoot: mountRoot)
        XCTAssertEqual(url.path, "/Users/test/share/subdir/file.txt")
    }

    func testEmptyPathReturnsMountRoot() throws {
        let url = try FSAccessPathValidator.resolve(path: "", mountRoot: mountRoot)
        XCTAssertEqual(url.path, mountRoot.path)
    }

    func testRepeatedSlashesAreCollapsed() throws {
        let url = try FSAccessPathValidator.resolve(path: "subdir//deep///file.txt", mountRoot: mountRoot)
        XCTAssertEqual(url.path, "/Users/test/share/subdir/deep/file.txt")
    }

    func testDotComponentsAreDropped() throws {
        let url = try FSAccessPathValidator.resolve(path: "./subdir/./file.txt", mountRoot: mountRoot)
        XCTAssertEqual(url.path, "/Users/test/share/subdir/file.txt")
    }

    func testDotDotResolvesWithinBounds() throws {
        let url = try FSAccessPathValidator.resolve(path: "subdir/../other/file.txt", mountRoot: mountRoot)
        XCTAssertEqual(url.path, "/Users/test/share/other/file.txt")
    }

    // MARK: - Escape rejection

    func testDirectDotDotEscapesRoot() {
        XCTAssertThrowsError(try FSAccessPathValidator.resolve(path: "..", mountRoot: mountRoot)) { error in
            guard let validation = error as? FSAccessPathValidator.ValidationError else {
                XCTFail("Expected ValidationError, got \(error)")
                return
            }
            if case .escapesRoot = validation {
                // ok
            } else {
                XCTFail("Expected .escapesRoot, got \(validation)")
            }
        }
    }

    func testNestedDotDotEscapesRoot() {
        XCTAssertThrowsError(try FSAccessPathValidator.resolve(path: "subdir/../../escape", mountRoot: mountRoot)) { error in
            guard let validation = error as? FSAccessPathValidator.ValidationError,
                  case .escapesRoot = validation else {
                XCTFail("Expected .escapesRoot, got \(error)")
                return
            }
        }
    }

    func testValidationErrorsMapToInvalidPath() {
        // FileSystemErrorCode 정수 값은 fsaccess.mdproto.md / fsaccess+Constants.swift 의 정본을 따른다.
        // SiriusKitCore 와 직접 link 하지 않기 위해 raw value 로 비교한다.
        let invalidPathRaw: UInt32 = 27
        do {
            _ = try FSAccessPathValidator.resolve(path: "..", mountRoot: mountRoot)
            XCTFail("Expected throw")
        } catch let err as FSAccessPathValidator.ValidationError {
            XCTAssertEqual(err.fileSystemErrorCode.rawValue, invalidPathRaw)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - NUL byte

    func testNULByteIsRejected() {
        let path = "subdir/\u{0000}file"
        XCTAssertThrowsError(try FSAccessPathValidator.resolve(path: path, mountRoot: mountRoot)) { error in
            guard let validation = error as? FSAccessPathValidator.ValidationError,
                  case .containsNUL = validation else {
                XCTFail("Expected .containsNUL, got \(error)")
                return
            }
        }
    }

    // MARK: - Length

    func testPathAtSpecLimitIsAccepted() throws {
        let component = String(repeating: "a", count: FSAccessPathValidator.pathSpecLimit)
        let url = try FSAccessPathValidator.resolve(path: component, mountRoot: mountRoot)
        XCTAssertEqual(url.lastPathComponent, component)
    }

    func testPathOverSpecButUnderHardThrowsPathTooLong() {
        let pathTooLongRaw: UInt32 = 25
        let component = String(repeating: "a", count: FSAccessPathValidator.pathSpecLimit + 1)
        do {
            _ = try FSAccessPathValidator.resolve(path: component, mountRoot: mountRoot)
            XCTFail("Expected throw")
        } catch let err as FSAccessPathValidator.ValidationError {
            switch err {
            case .pathTooLong(let observed, let limit):
                XCTAssertEqual(observed, FSAccessPathValidator.pathSpecLimit + 1)
                XCTAssertEqual(limit, FSAccessPathValidator.pathSpecLimit)
                XCTAssertEqual(err.fileSystemErrorCode.rawValue, pathTooLongRaw)
            default:
                XCTFail("Expected .pathTooLong, got \(err)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testPathOverHardLimitThrowsHardVariant() {
        let pathTooLongRaw: UInt32 = 25
        let component = String(repeating: "a", count: FSAccessPathValidator.pathHardLimit + 1)
        do {
            _ = try FSAccessPathValidator.resolve(path: component, mountRoot: mountRoot)
            XCTFail("Expected throw")
        } catch let err as FSAccessPathValidator.ValidationError {
            switch err {
            case .pathTooLongHard(let observed, let limit):
                XCTAssertEqual(observed, FSAccessPathValidator.pathHardLimit + 1)
                XCTAssertEqual(limit, FSAccessPathValidator.pathHardLimit)
                XCTAssertEqual(err.fileSystemErrorCode.rawValue, pathTooLongRaw)
            default:
                XCTFail("Expected .pathTooLongHard, got \(err)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - isWithin (subtree re-check)

    func testIsWithinAcceptsRootItself() {
        XCTAssertTrue(FSAccessPathValidator.isWithin(mountRoot, root: mountRoot))
    }

    func testIsWithinAcceptsSubdirectory() {
        let inside = mountRoot.appendingPathComponent("subdir/file.txt")
        XCTAssertTrue(FSAccessPathValidator.isWithin(inside, root: mountRoot))
    }

    func testIsWithinRejectsSibling() {
        // /Users/test/share-sibling 은 prefix 가 비슷하지만 별개의 디렉토리.
        let sibling = URL(fileURLWithPath: "/Users/test/share-sibling/file.txt")
        XCTAssertFalse(FSAccessPathValidator.isWithin(sibling, root: mountRoot))
    }

    func testIsWithinRejectsExternalPath() {
        let outside = URL(fileURLWithPath: "/etc/passwd")
        XCTAssertFalse(FSAccessPathValidator.isWithin(outside, root: mountRoot))
    }

    // MARK: - Symlink containment (mdproto §"Symlinks")

    /// 중간 component 가 mount root 밖으로 나가는 symlink 면 resolve 가
    /// `.escapesRoot` 로 거절해야 한다. mdproto 의 "outside-the-subtree symlink
    /// MUST NOT be followed" 강제.
    func testIntermediateSymlinkEscapingMountRootIsRejected() throws {
        let fm = FileManager.default
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("fsaccess-validator-symlink-\(UUID().uuidString)", isDirectory: true)
        let mount = tmp.appendingPathComponent("mount", isDirectory: true)
        let outside = tmp.appendingPathComponent("outside", isDirectory: true)
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        // mount/escape -> ../outside (밖으로 나가는 symlink)
        let escape = mount.appendingPathComponent("escape")
        try fm.createSymbolicLink(at: escape, withDestinationURL: outside)

        // 비밀 파일.
        let secret = outside.appendingPathComponent("secret.txt")
        try "TOP SECRET".write(to: secret, atomically: true, encoding: .utf8)

        // resolve 가 거절해야 한다.
        XCTAssertThrowsError(
            try FSAccessPathValidator.resolve(path: "escape/secret.txt", mountRoot: mount)
        ) { error in
            guard let validation = error as? FSAccessPathValidator.ValidationError,
                  case .escapesRoot = validation else {
                XCTFail("Expected .escapesRoot, got \(error)")
                return
            }
        }
    }

    /// mount root 안을 가리키는 symlink 는 통과해야 한다.
    func testInternalSymlinkInsideMountRootIsAccepted() throws {
        let fm = FileManager.default
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("fsaccess-validator-internal-\(UUID().uuidString)", isDirectory: true)
        let mount = tmp.appendingPathComponent("mount", isDirectory: true)
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let real = mount.appendingPathComponent("real", isDirectory: true)
        try fm.createDirectory(at: real, withIntermediateDirectories: true)
        let alias = mount.appendingPathComponent("alias")
        try fm.createSymbolicLink(at: alias, withDestinationURL: real)

        // alias/foo.txt 는 결국 real/foo.txt — 둘 다 mount 안.
        XCTAssertNoThrow(try FSAccessPathValidator.resolve(path: "alias/foo.txt", mountRoot: mount))
    }

    /// leaf 자체가 외부를 가리키는 symlink 일 때도 거절. (lstat 만 하는
    /// followSymlinks=false 분기에서도 mount root 밖 metadata 노출을 차단)
    func testLeafSymlinkPointingOutsideIsRejected() throws {
        let fm = FileManager.default
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("fsaccess-validator-leaf-\(UUID().uuidString)", isDirectory: true)
        let mount = tmp.appendingPathComponent("mount", isDirectory: true)
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let target = URL(fileURLWithPath: "/etc/hosts")
        let leaf = mount.appendingPathComponent("hosts")
        try fm.createSymbolicLink(at: leaf, withDestinationURL: target)

        XCTAssertThrowsError(
            try FSAccessPathValidator.resolve(path: "hosts", mountRoot: mount)
        ) { error in
            guard let validation = error as? FSAccessPathValidator.ValidationError,
                  case .escapesRoot = validation else {
                XCTFail("Expected .escapesRoot, got \(error)")
                return
            }
        }
    }
}
