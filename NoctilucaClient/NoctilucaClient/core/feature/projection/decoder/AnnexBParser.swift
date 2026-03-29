//
//  AnnexBParser.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 3/28/26.
//

import Foundation
import SiriusKitClient

/// Annex-B 형식의 H.264/HEVC 비트스트림을 파싱하여
/// 파라미터 셋(SPS/PPS/VPS)과 비디오 NALU를 분리하고,
/// 비디오 NALU를 AVCC 형식으로 변환하는 유틸리티.
enum AnnexBParser {

    struct Result {
        /// Annex-B에서 추출한 파라미터 셋 NALU 데이터 (start code 제거됨).
        /// CMFormatDescription 생성에 적합한 순서로 정렬됨:
        ///   H.264: [SPS, PPS]
        ///   HEVC:  [VPS, SPS, PPS]
        let parameterSets: [Data]

        /// 비디오 NALU를 AVCC 형식(4-byte big-endian length prefix)으로 재조립한 데이터.
        let videoData: Data
    }

    /// Annex-B 비트스트림을 파싱하여 파라미터 셋과 비디오 데이터를 분리합니다.
    ///
    /// - Parameters:
    ///   - data: Annex-B 형식의 프레임 데이터
    ///   - codec: 코덱 종류 (`.avc1` 또는 `.hvc1`)
    /// - Returns: 파라미터 셋과 AVCC 변환된 비디오 데이터
    static func parse(_ data: Data, codec: CodecFourCC) -> Result {
        let nalus = splitNALUs(data)

        var parameterSetNALUs: [(naluType: UInt8, data: Data)] = []
        var videoNALUs: [Data] = []

        for nalu in nalus {
            guard !nalu.isEmpty else { continue }

            if let naluType = parameterSetType(of: nalu, codec: codec) {
                parameterSetNALUs.append((naluType, nalu))
            } else {
                videoNALUs.append(nalu)
            }
        }

        // CMFormatDescription이 기대하는 순서로 정렬 (NALU type 오름차순)
        // H.264: SPS(7) → PPS(8), HEVC: VPS(32) → SPS(33) → PPS(34)
        parameterSetNALUs.sort { $0.naluType < $1.naluType }

        // AVCC 형식으로 변환: 각 NALU 앞에 4-byte big-endian length prefix
        var avccData = Data(capacity: data.count)
        for nalu in videoNALUs {
            var length = UInt32(nalu.count).bigEndian
            avccData.append(Data(bytes: &length, count: 4))
            avccData.append(nalu)
        }

        return Result(
            parameterSets: parameterSetNALUs.map(\.data),
            videoData: avccData
        )
    }

    // MARK: - Private

    /// Annex-B start code (`0x00000001` 또는 `0x000001`)를 기준으로 NALU를 분리합니다.
    private static func splitNALUs(_ data: Data) -> [Data] {
        var nalus: [Data] = []

        data.withUnsafeBytes { buffer in
            guard let ptr = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            let count = buffer.count

            var naluStart = -1
            var i = 0

            while i < count {
                if i + 2 < count && ptr[i] == 0x00 && ptr[i + 1] == 0x00 {
                    var startCodeLen = 0

                    if i + 3 < count && ptr[i + 2] == 0x00 && ptr[i + 3] == 0x01 {
                        // 4-byte start code: 00 00 00 01
                        startCodeLen = 4
                    } else if ptr[i + 2] == 0x01 {
                        // 3-byte start code: 00 00 01
                        startCodeLen = 3
                    }

                    if startCodeLen > 0 {
                        if naluStart >= 0 {
                            nalus.append(Data(bytes: ptr + naluStart, count: i - naluStart))
                        }
                        naluStart = i + startCodeLen
                        i += startCodeLen
                        continue
                    }
                }

                i += 1
            }

            // 마지막 NALU
            if naluStart >= 0 && naluStart < count {
                nalus.append(Data(bytes: ptr + naluStart, count: count - naluStart))
            }
        }

        return nalus
    }

    /// NALU가 파라미터 셋이면 NALU type을 반환하고, 아니면 nil을 반환합니다.
    private static func parameterSetType(of nalu: Data, codec: CodecFourCC) -> UInt8? {
        guard let firstByte = nalu.first else { return nil }

        switch codec {
        case .avc1:
            let naluType = firstByte & 0x1F
            // 7 = SPS, 8 = PPS
            return (naluType == 7 || naluType == 8) ? naluType : nil

        case .hvc1:
            let naluType = (firstByte >> 1) & 0x3F
            // 32 = VPS, 33 = SPS, 34 = PPS
            return (naluType == 32 || naluType == 33 || naluType == 34) ? naluType : nil

        default:
            return nil
        }
    }
}
