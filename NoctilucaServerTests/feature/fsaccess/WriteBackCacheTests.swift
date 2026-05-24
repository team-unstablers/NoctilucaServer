//
//  WriteBackCacheTests.swift
//  NoctilucaServerTests
//
//  WriteBackCache 의 pure-logic 경로 (append / coalescing / threshold /
//  invalidate / inspect) 를 검증한다. flushAll 처럼 wire (FSAccessMountChannel
//  의 sendWrite) 에 의존하는 경로는 통합 환경에서 별도 검증한다 — 본 단위
//  테스트는 channel mock 없이 메모리상 상태 변화만 본다.
//

import XCTest
@testable import NoctilucaServerTestsHost

final class WriteBackCacheTests: XCTestCase {

    // MARK: - Append / coalescing

    /// 비어있는 buffer 에 새 write 를 append 하면 그 바이트 수만큼 누적된다.
    func testAppendIntoEmptyBufferAccumulatesBytes() async {
        let cache = WriteBackCache()
        let data = Data(repeating: 0xAB, count: 1024)
        let outcome = await cache.append(hostFileId: 1, navHandle: 100, offset: 0, data: data)
        XCTAssertEqual(outcome, .buffered)
        let dirty = await cache.dirtyBytes(hostFileId: 1)
        XCTAssertEqual(dirty, 1024)
        let total = await cache.totalDirtyBytes
        XCTAssertEqual(total, 1024)
        let has = await cache.hasDirty(hostFileId: 1)
        XCTAssertTrue(has)
    }

    /// 정확히 인접한 두 write (앞 write 의 end == 뒤 write 의 offset) 는 단일
    /// extent 로 merge 된다. 총 dirty 바이트는 두 write 의 합과 같다.
    func testAppendAdjacentExtentsCoalesceWithoutByteInflation() async {
        let cache = WriteBackCache()
        _ = await cache.append(hostFileId: 1, navHandle: 100, offset: 0, data: Data(repeating: 0x11, count: 100))
        _ = await cache.append(hostFileId: 1, navHandle: 100, offset: 100, data: Data(repeating: 0x22, count: 200))

        let dirty = await cache.dirtyBytes(hostFileId: 1)
        XCTAssertEqual(dirty, 300, "인접한 두 extent 는 정확히 합산되어야 한다")
    }

    /// overlap write 는 새 데이터가 우선 (last-writer-wins). 총 dirty 바이트는
    /// merge 후 영역 크기와 같다.
    func testOverlappingAppendIsLastWriterWins() async {
        let cache = WriteBackCache()
        _ = await cache.append(hostFileId: 1, navHandle: 100, offset: 0, data: Data(repeating: 0x11, count: 1000))
        // 500~999 영역을 덮어쓰고 999~1999 까지 확장
        _ = await cache.append(hostFileId: 1, navHandle: 100, offset: 500, data: Data(repeating: 0x22, count: 1500))

        let dirty = await cache.dirtyBytes(hostFileId: 1)
        XCTAssertEqual(dirty, 2000, "overlap merge 후 dirty 는 [0, 2000) 영역 크기와 동일해야 한다")
    }

    /// 떨어져 있는 두 write 는 별도 extent 로 보관되고, 합산 dirty 는 두 사이즈
    /// 의 단순 합이다.
    func testNonAdjacentAppendsKeepSeparateExtents() async {
        let cache = WriteBackCache()
        _ = await cache.append(hostFileId: 1, navHandle: 100, offset: 0, data: Data(repeating: 0x11, count: 100))
        _ = await cache.append(hostFileId: 1, navHandle: 100, offset: 10_000, data: Data(repeating: 0x22, count: 200))

        let dirty = await cache.dirtyBytes(hostFileId: 1)
        XCTAssertEqual(dirty, 300)
    }

    // MARK: - Threshold signalling

    /// per-file 임계값을 초과하는 단일 append 는 즉시 `.shouldFlushSoon` 시그널.
    func testAppendExceedingPerFileThresholdSignalsFlushSoon() async {
        let cache = WriteBackCache()
        let big = Data(repeating: 0xFF, count: WriteBackCache.perFileFlushThreshold + 1)
        let outcome = await cache.append(hostFileId: 1, navHandle: 100, offset: 0, data: big)
        XCTAssertEqual(outcome, .shouldFlushSoon)
    }

    /// 임계값 미만 append 는 `.buffered`.
    func testAppendBelowPerFileThresholdReturnsBuffered() async {
        let cache = WriteBackCache()
        let small = Data(repeating: 0xFF, count: 1024)
        let outcome = await cache.append(hostFileId: 1, navHandle: 100, offset: 0, data: small)
        XCTAssertEqual(outcome, .buffered)
    }

    // MARK: - Multi-file totals

    /// 여러 hostFile 에 동시에 append 하면 totalDirtyBytes 는 모든 buffer 의 합.
    func testTotalDirtyBytesSumsAcrossHostFiles() async {
        let cache = WriteBackCache()
        _ = await cache.append(hostFileId: 1, navHandle: 100, offset: 0, data: Data(count: 1000))
        _ = await cache.append(hostFileId: 2, navHandle: 200, offset: 0, data: Data(count: 2000))
        _ = await cache.append(hostFileId: 3, navHandle: 300, offset: 0, data: Data(count: 3000))

        let total = await cache.totalDirtyBytes
        XCTAssertEqual(total, 6000)
    }

    // MARK: - Invalidate

    /// invalidate 는 buffer 자체를 폐기하고 totalDirtyBytes 도 즉시 회수.
    func testInvalidateDropsBufferAndReclaimsTotalBytes() async {
        let cache = WriteBackCache()
        _ = await cache.append(hostFileId: 1, navHandle: 100, offset: 0, data: Data(count: 1000))
        _ = await cache.append(hostFileId: 2, navHandle: 200, offset: 0, data: Data(count: 2000))

        await cache.invalidate(hostFileId: 1)

        let total = await cache.totalDirtyBytes
        XCTAssertEqual(total, 2000)
        let has1 = await cache.hasDirty(hostFileId: 1)
        XCTAssertFalse(has1)
        let has2 = await cache.hasDirty(hostFileId: 2)
        XCTAssertTrue(has2)
    }

    /// 등록되지 않은 hostFile 에 대한 invalidate 는 무해한 noop.
    func testInvalidateOfMissingHostFileIsNoop() async {
        let cache = WriteBackCache()
        await cache.invalidate(hostFileId: 999)
        let total = await cache.totalDirtyBytes
        XCTAssertEqual(total, 0)
    }

    // MARK: - hasDirty empty case

    /// append 한 적 없는 hostFile 의 hasDirty 는 false.
    func testHasDirtyFalseForUnknownHostFile() async {
        let cache = WriteBackCache()
        let has = await cache.hasDirty(hostFileId: 999)
        XCTAssertFalse(has)
    }
}

extension WriteBackCache.AppendOutcome: Equatable {
    public static func == (lhs: WriteBackCache.AppendOutcome, rhs: WriteBackCache.AppendOutcome) -> Bool {
        switch (lhs, rhs) {
        case (.buffered, .buffered): return true
        case (.shouldFlushSoon, .shouldFlushSoon): return true
        default: return false
        }
    }
}
