//
//  WriteBackCache.swift
//  NoctilucaServer
//
//  fsaccess NFS WRITE 의 host-side write-back cache. 작은 write 를 host 측
//  메모리에 누적했다가 COMMIT / close / 임계값 도달 시 wire 로 한 번에 flush
//  한다. Excel/Word 같은 office 앱 저장의 "수십~수백 개의 작은 write + fsync +
//  rename" 패턴에서 Sirius QUIC RTT 횟수를 크게 줄여 체감 저장 속도를 개선
//  한다.
//
//  Scope: 본 actor 는 단일 ``FSAccessMountChannel`` (= 하나의 mount session)
//  의 dirty 데이터만 보관한다. mount session teardown 시 ``drainAll`` 로
//  best-effort flush + 메모리 회수.
//
//  Semantics: NFSv4 의 UNSTABLE write + COMMIT 시멘틱 (RFC 7530 §18.32) 을
//  활용한다. 즉 우리는 WRITE 에 `stability=UNSTABLE` + `verifier=<server-
//  instance-id>` 로 응답하고, 진짜 wire 전송은 COMMIT 또는 close 시점에 한다.
//  이 경로에서 flush 가 실패하면 sticky error 가 다음 COMMIT 응답에 NFSERR_IO
//  로 전파되며, 클라이언트는 그 write 들을 재전송한다.
//

import Foundation

import NanoNFS

import SiriusKit

actor WriteBackCache {

    // MARK: - Tuning

    /// per-file flush threshold. 한 파일의 누적 dirty 바이트가 이 값을 넘으면
    /// 다음 background tick 또는 append 결과의 `shouldFlushSoon` 시그널을
    /// 통해 즉시 flush 가 트리거된다.
    static let perFileFlushThreshold: Int = 4 * 1024 * 1024

    /// 전역 dirty 메모리 budget. 초과하면 ``tickIdleFlush`` 가 oldest hostFile
    /// 부터 강제 flush 해 budget 안으로 회수한다.
    static let totalDirtyBudget: Int = 64 * 1024 * 1024

    /// `firstDirtyAt` 부터 이 시간이 지나면 idle flush 대상. write 가 한동안
    /// 들어오지 않은 파일이 메모리에 무한정 머무는 것을 막는다.
    static let idleFlushDuration: Duration = .milliseconds(500)

    /// background flusher 의 polling 주기.
    static let pollInterval: Duration = .milliseconds(250)

    /// 단일 ``FSAccessMountChannel/sendWrite`` 의 데이터 청크 최대 크기. 누적된
    /// extent 가 이보다 크면 split 해서 여러 wire 메시지로 분할 전송한다.
    /// (Sirius QUIC frame 크기 한도 + navigator 측 메모리 압박 회피.)
    static let wireChunkSize: Int = 1 * 1024 * 1024

    // MARK: - State

    /// 한 hostFile 당 누적된 dirty 데이터. ``extents`` 는 offset 기준 정렬 +
    /// non-overlapping 으로 유지된다 (append 시 자동 merge).
    private struct FileBuffer {
        let hostFileId: UInt64
        /// 가장 최근에 append 한 write 의 navigator-side handleId. flush 시
        /// 이 navHandle 로 sendWrite 한다. 동일 hostFile 에 여러 OPEN slot 의
        /// navHandle 이 있어도 어차피 navigator 측 같은 inode 로 모이므로
        /// 어느 것을 써도 결과는 동일하다.
        var navHandleHint: UInt64
        var extents: [DirtyExtent]
        var totalBytes: Int
        var firstDirtyAt: ContinuousClock.Instant
        /// flush 실패 시 sticky 로 남는 NFSError. 다음 ``flushAll`` 호출이
        /// 이 에러를 throw 하고 buffer entry 자체를 제거한다 (verifier 는
        /// 동일 유지되므로 클라이언트는 NFSERR_IO 를 받아 unstable write 를
        /// 재전송하는 정상 복구 경로로 흐른다).
        var stickyError: NFSError?
    }

    struct DirtyExtent: Sendable {
        var offset: UInt64
        var data: Data
        var end: UInt64 { offset + UInt64(data.count) }
    }

    private var buffers: [UInt64: FileBuffer] = [:]
    private(set) var totalDirtyBytes: Int = 0

    // MARK: - Append

    enum AppendOutcome: Sendable {
        case buffered
        /// per-file 또는 전역 임계값 초과. 호출자는 가급적 직후에 ``flushAll``
        /// 또는 background flusher 의 즉시 tick 을 트리거하는 것이 좋다.
        case shouldFlushSoon
    }

    func append(hostFileId: UInt64, navHandle: UInt64, offset: UInt64, data: Data) -> AppendOutcome {
        var buffer = buffers[hostFileId] ?? FileBuffer(
            hostFileId: hostFileId,
            navHandleHint: navHandle,
            extents: [],
            totalBytes: 0,
            firstDirtyAt: ContinuousClock.now,
            stickyError: nil
        )
        buffer.navHandleHint = navHandle

        let delta = Self.mergeExtent(
            into: &buffer.extents,
            new: DirtyExtent(offset: offset, data: data)
        )
        buffer.totalBytes &+= delta
        totalDirtyBytes &+= delta
        buffers[hostFileId] = buffer

        if buffer.totalBytes >= Self.perFileFlushThreshold
            || totalDirtyBytes >= Self.totalDirtyBudget {
            return .shouldFlushSoon
        }
        return .buffered
    }

    /// `new` 를 `extents` 에 삽입. overlap / 인접한 기존 extent 와 합쳐 단일
    /// extent 로 정규화. 이전 extent 와 byte-level overlap 이 있으면 새 데이터가
    /// 우선 (last-writer-wins). 반환값은 총 dirty 바이트 변화량.
    private static func mergeExtent(into extents: inout [DirtyExtent], new: DirtyExtent) -> Int {
        let newStart = new.offset
        let newEnd = new.end

        var mergedStart = newStart
        var mergedEnd = newEnd
        var prefixChunks: [(offset: UInt64, data: Data)] = []
        var suffixChunks: [(offset: UInt64, data: Data)] = []
        var removedTotalBytes = 0

        var i = 0
        while i < extents.count {
            let e = extents[i]
            if e.end < newStart {
                i += 1
                continue
            }
            if e.offset > newEnd {
                break
            }
            // overlap 또는 인접
            if e.offset < newStart {
                let prefixLen = Int(newStart - e.offset)
                prefixChunks.append((e.offset, e.data.prefix(prefixLen)))
            }
            if e.end > newEnd {
                let suffixOff = Int(newEnd - e.offset)
                suffixChunks.append((newEnd, e.data.suffix(from: suffixOff)))
            }
            mergedStart = min(mergedStart, e.offset)
            mergedEnd = max(mergedEnd, e.end)
            removedTotalBytes += e.data.count
            extents.remove(at: i)
            // i 그대로 — 요소가 한 칸 당겨졌다.
        }

        var mergedData = Data(count: Int(mergedEnd - mergedStart))
        mergedData.withUnsafeMutableBytes { _ = $0 }  // ensure backing storage

        for (off, d) in prefixChunks {
            let dstStart = Int(off - mergedStart)
            mergedData.replaceSubrange(dstStart..<(dstStart + d.count), with: d)
        }
        let newDstStart = Int(new.offset - mergedStart)
        mergedData.replaceSubrange(newDstStart..<(newDstStart + new.data.count), with: new.data)
        for (off, d) in suffixChunks {
            let dstStart = Int(off - mergedStart)
            mergedData.replaceSubrange(dstStart..<(dstStart + d.count), with: d)
        }

        let mergedExtent = DirtyExtent(offset: mergedStart, data: mergedData)
        let insertIdx = extents.firstIndex(where: { $0.offset > mergedExtent.offset }) ?? extents.count
        extents.insert(mergedExtent, at: insertIdx)

        return mergedExtent.data.count - removedTotalBytes
    }

    // MARK: - Flush

    /// 해당 hostFile 의 모든 dirty extent 를 wire 로 flush. sticky error 가
    /// 있으면 우선적으로 throw + buffer 폐기.
    ///
    /// 에러 처리: 송신 도중 실패 시 남은 extent 는 다시 buffer 에 적재되지
    /// 않는다 (재전송은 NFSv4 클라이언트의 책임 — verifier 도 그대로 유지
    /// 되지만 host 가 NFSERR_IO 를 던지면 클라이언트가 그 write 들을
    /// 재전송한다). 대신 sticky 에러를 마크해 다음 COMMIT 응답에 전파.
    func flushAll(hostFileId: UInt64, channel: FSAccessMountChannel) async throws {
        guard var buffer = buffers[hostFileId] else { return }
        if let sticky = buffer.stickyError {
            totalDirtyBytes -= buffer.totalBytes
            buffers.removeValue(forKey: hostFileId)
            throw sticky
        }
        if buffer.extents.isEmpty {
            return
        }

        let extentsSnapshot = buffer.extents
        let navHandle = buffer.navHandleHint
        let totalBefore = buffer.totalBytes

        // optimistic 비우기 — 송신 중 새로 append 되는 write 가 같은 buffer 에
        // 다시 쌓일 수 있도록. 실패 시 sticky 마킹만.
        buffer.extents.removeAll()
        buffer.totalBytes = 0
        buffers[hostFileId] = buffer
        totalDirtyBytes -= totalBefore

        do {
            for extent in extentsSnapshot {
                var sent = 0
                while sent < extent.data.count {
                    let chunkLen = min(Self.wireChunkSize, extent.data.count - sent)
                    let chunkData = extent.data.subdata(in: sent..<(sent + chunkLen))
                    let chunkOffset = extent.offset + UInt64(sent)
                    let response = try await channel.sendWrite(
                        handleId: navHandle, offset: chunkOffset, data: chunkData
                    )
                    guard response.success else {
                        throw NoctilucaNFSServer.nfsError(from: response.error)
                    }
                    sent += chunkLen
                }
            }
        } catch {
            let nfsErr = (error as? NFSError) ?? NFSError.io
            // buffer entry 가 (송신 중에 들어온 새 append 때문에) 살아있을
            // 수 있으니 in-place sticky 만 마크. 다음 commit/flush 가 throw +
            // buffer 폐기.
            var marked = buffers[hostFileId] ?? FileBuffer(
                hostFileId: hostFileId, navHandleHint: navHandle,
                extents: [], totalBytes: 0,
                firstDirtyAt: ContinuousClock.now, stickyError: nil
            )
            marked.stickyError = nfsErr
            buffers[hostFileId] = marked
            throw nfsErr
        }

        // 송신 중에 새 append 가 없었으면 entry 자체 제거 (메모리 정리).
        if let b = buffers[hostFileId], b.extents.isEmpty, b.stickyError == nil {
            buffers.removeValue(forKey: hostFileId)
        }
    }

    /// dirty 또는 sticky error 가 있을 때만 flushAll 위임.
    func flushIfDirty(hostFileId: UInt64, channel: FSAccessMountChannel) async throws {
        guard let b = buffers[hostFileId],
              !b.extents.isEmpty || b.stickyError != nil else { return }
        try await flushAll(hostFileId: hostFileId, channel: channel)
    }

    /// 등록된 모든 hostFile 을 flush 시도. 개별 hostFile 의 실패는 sticky 로
    /// 남고 swallow — 호출자(teardown / background flusher)는 결과를 신경 쓰지
    /// 않는다. sticky 가 마킹된 entry 는 다음 사용자-가시 commit/flush 에서
    /// 클라이언트로 전파된다.
    func drainAll(channel: FSAccessMountChannel) async {
        for id in Array(buffers.keys) {
            do { try await flushAll(hostFileId: id, channel: channel) } catch {}
        }
    }

    /// background flusher 의 주기 tick. per-file 임계값 / idle 임계값 / 전역
    /// budget 을 한 번에 평가하고 해당 entry 만 flush.
    func tickIdleFlush(channel: FSAccessMountChannel) async {
        let now = ContinuousClock.now

        let immediate = buffers.compactMap { (id, b) -> UInt64? in
            guard !b.extents.isEmpty else { return nil }
            if b.totalBytes >= Self.perFileFlushThreshold { return id }
            if now > b.firstDirtyAt.advanced(by: Self.idleFlushDuration) { return id }
            return nil
        }
        for id in immediate {
            do { try await flushAll(hostFileId: id, channel: channel) } catch {}
        }

        if totalDirtyBytes >= Self.totalDirtyBudget {
            let oldestFirst = buffers
                .filter { !$0.value.extents.isEmpty }
                .sorted { $0.value.firstDirtyAt < $1.value.firstDirtyAt }
                .map { $0.key }
            for id in oldestFirst {
                if totalDirtyBytes < Self.totalDirtyBudget { break }
                do { try await flushAll(hostFileId: id, channel: channel) } catch {}
            }
        }
    }

    // MARK: - Invalidate / Inspect

    /// truncate / unlink 등으로 buffer 가 무효화될 때 호출. 누적된 dirty 는
    /// 폐기 (wire 로 안 보냄).
    func invalidate(hostFileId: UInt64) {
        if let b = buffers.removeValue(forKey: hostFileId) {
            totalDirtyBytes -= b.totalBytes
        }
    }

    func hasDirty(hostFileId: UInt64) -> Bool {
        guard let b = buffers[hostFileId] else { return false }
        return !b.extents.isEmpty || b.stickyError != nil
    }

    /// 테스트/디버그용 inspector. 프로덕션 경로에서는 사용하지 않는다.
    func dirtyBytes(hostFileId: UInt64) -> Int {
        return buffers[hostFileId]?.totalBytes ?? 0
    }
}
