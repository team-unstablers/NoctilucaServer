//
//  ZstdCodec.swift
//  NoctilucaServer
//

import Foundation
import libzstd

internal enum ZstdCodec {
    enum Error: Swift.Error, CustomStringConvertible {
        case compressionFailed(name: String)
        case unknownDecompressedSize
        case decompressionFailed(name: String)
        case sizeOverflow

        var description: String {
            switch self {
            case .compressionFailed(let name): return "zstd compression failed: \(name)"
            case .unknownDecompressedSize: return "zstd frame is missing decoded content size"
            case .decompressionFailed(let name): return "zstd decompression failed: \(name)"
            case .sizeOverflow: return "zstd payload size overflows host word size"
            }
        }
    }

    static func compress(_ data: Data) throws -> Data {
        let srcCount = data.count
        let dstCapacity = ZSTD_compressBound(srcCount)
        var output = Data(count: dstCapacity)

        let produced: Int = try output.withUnsafeMutableBytes { dstRaw in
            try data.withUnsafeBytes { srcRaw in
                let written = ZSTD_compress(
                    dstRaw.baseAddress,
                    dstCapacity,
                    srcRaw.baseAddress,
                    srcCount,
                    ZSTD_CLEVEL_DEFAULT
                )
                if ZSTD_isError(written) != 0 {
                    let cstr = ZSTD_getErrorName(written)
                    let name = cstr.flatMap { String(cString: $0) } ?? "unknown"
                    throw Error.compressionFailed(name: name)
                }
                return written
            }
        }

        output.removeSubrange(produced..<output.count)
        return output
    }

    static func decompress(_ data: Data) throws -> Data {
        let srcCount = data.count

        let decodedSize: UInt64 = data.withUnsafeBytes { srcRaw -> UInt64 in
            ZSTD_getFrameContentSize(srcRaw.baseAddress, srcCount)
        }

        if decodedSize == ZSTD_CONTENTSIZE_ERROR {
            throw Error.decompressionFailed(name: "ZSTD_CONTENTSIZE_ERROR")
        }
        if decodedSize == ZSTD_CONTENTSIZE_UNKNOWN {
            throw Error.unknownDecompressedSize
        }
        guard let dstCapacity = Int(exactly: decodedSize) else {
            throw Error.sizeOverflow
        }

        var output = Data(count: dstCapacity)
        let produced: Int = try output.withUnsafeMutableBytes { dstRaw in
            try data.withUnsafeBytes { srcRaw in
                let written = ZSTD_decompress(
                    dstRaw.baseAddress,
                    dstCapacity,
                    srcRaw.baseAddress,
                    srcCount
                )
                if ZSTD_isError(written) != 0 {
                    let cstr = ZSTD_getErrorName(written)
                    let name = cstr.flatMap { String(cString: $0) } ?? "unknown"
                    throw Error.decompressionFailed(name: name)
                }
                return written
            }
        }

        if produced != dstCapacity {
            output.removeSubrange(produced..<output.count)
        }
        return output
    }
}
