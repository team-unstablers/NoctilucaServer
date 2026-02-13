//
//  CodecNegotiator.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/13/25.
//

import Foundation
import SiriusKit

class CodecNegotiator {
    let ours: [CodecSpecification]
    
    init(specifications: [CodecSpecification]) {
        self.ours = specifications
    }
    
    /// 클라이언트(그들)의 스펙 셋과 협상하여 최종 코덱 스펙을 결정합니다.
    open func negotiate(with theirs: [SiriusKit.Codec]) -> SiriusKit.Codec? {
        // to be overridden
        fatalError("Not implemented")
    }
}

class BalancedCodecNegotiator: CodecNegotiator {
    /*
    /// 두 스펙 셋의 엄격한 합집합을 구합니다.
    func unionStrict(_ ours: [CodecSpecification], _ theirs: [SiriusKit.Codec]) -> [SiriusKit.Codec] {
        var result: [CodecSpecification] = []
        
        // 최대한 클라이언트의 순서를 존중한다
        for theirsSpec in theirs {
            for oursSpec in ours {
                if theirsSpec.hashValue == oursSpec.hashValue {
                    result.append(theirsSpec)
                }
            }
        }
        
        return result
    }
     */
    
    /// 두 스펙 셋의 완화된 합집합을 구합니다.
    func union(_ ours: [CodecSpecification], _ theirs: [SiriusKit.Codec]) -> [CodecSpecification] {
        var result: [CodecSpecification] = []
        
        // 최대한 클라이언트의 순서를 존중한다
        for theirsSpec in theirs {
            for oursSpec in ours {
                if oursSpec.isCompatible(with: theirsSpec) {
                    result.append(oursSpec)
                    break
                }
            }
        }
        
        return result
    }
    
    func selectFallbackCodec(_ ours: [CodecSpecification],
                             _ theirs: [SiriusKit.Codec]) -> CodecSpecification?
    {
        // 양쪽 다 지원하는 코덱 스펙 중 첫 번째 것을 선택한다
        for oursSpec in ours {
            for theirsSpec in theirs {
                if oursSpec.fourCC == theirsSpec.fourCC {
                    return oursSpec
                }
            }
        }
        
        return nil
    }
    
    override func negotiate(with theirs: [SiriusKit.Codec]) -> SiriusKit.Codec? {
        /*
        // 1. 엄격한 합집합 우선 - exact match를 기반으로 결정을 시도한다
        let strictCandidates = unionStrict(self.ours, theirs)
        if let realizable = strictCandidates.first(where: { $0.isRealizable() }) {
            return realizable
        }
         */

        // 2. 완화된 합집합 시도 - isCompatible() 기반으로 결정을 시도한다
        let candidates = union(self.ours, theirs)
        if let realizable = candidates.first(where: { $0.isRealizable() }) {
            var finalSpec = realizable

            // 매칭되는 클라이언트 코덱에서 quality를 가져온다
            if let clientCodec = theirs.first(where: { realizable.isCompatible(with: $0) }) {
                finalSpec.quality = applyClientQuality(from: clientCodec, to: realizable.fourCC)
            }

            return finalSpec.toSiriusKitCodec()
        }

        // 3. 호환되는 코덱 스펙이 없으므로 클라이언트와 서버 양쪽 다 처리 가능한 코덱 중 하나를 임의로 선택한다
        if let fallback = selectFallbackCodec(self.ours, theirs) {
            var finalSpec = fallback

            // 매칭되는 클라이언트 코덱에서 quality를 가져온다
            if let clientCodec = theirs.first(where: { $0.fourCC == fallback.fourCC }) {
                finalSpec.quality = applyClientQuality(from: clientCodec, to: fallback.fourCC)
            }

            return finalSpec.toSiriusKitCodec()
        }

        // 4. 최종 실패
        return nil
    }

    private func applyClientQuality(from clientCodec: SiriusKit.Codec, to fourCC: CodecFourCC) -> QualityMode {
        // Image 코덱(WebP/MJPG/ZRLE)은 auto 품질만 지원
        if fourCC == .webp || fourCC == .mjpg || fourCC == .zrle {
            switch clientCodec.quality {
            case .auto(let mode):
                return .auto(mode: mode.rawValue)
            default:
                // auto가 아닌 quality는 .auto(mode: .balancedPriority)로 폴백
                return .auto(mode: AutoQualityMode.balancedPriority.rawValue)
            }
        }

        // 비디오 코덱은 클라이언트 quality를 그대로 적용
        return convertQuality(from: clientCodec.quality)
    }

    private func convertQuality(from siriusQuality: SiriusKit.Codec.Quality) -> QualityMode {
        switch siriusQuality {
        case .auto(let mode):
            return .auto(mode: mode.rawValue)
        case .constantBitrate(let bitrateKbps):
            return .constantBitrate(bitrateKbps: bitrateKbps)
        case .variableBitrate(let targetBitrateKbps, let maxBitrateKbps):
            return .variableBitrate(targetBitrateKbps: targetBitrateKbps, maxBitrateKbps: maxBitrateKbps)
        case .fixedQuality(let factor):
            return .fixedQuality(factor: factor)
        case .lossless(let mode):
            return .lossless(mode: mode.rawValue)
        }
    }
}

class ServerOverriddenCodecNegotiator: CodecNegotiator {
    override func negotiate(with theirs: [SiriusKit.Codec]) -> SiriusKit.Codec? {
        // 서버 측 우선 정책: 서버 측 스펙 셋에서 실현 가능한 첫 번째 스펙을 반환한다
        return ours.first(where: { $0.isRealizable() } )?.toSiriusKitCodec()
    }
}


extension CodecNegotiator {
    static func create(from policy: CodecNegotiationPolicy, specifications: [CodecSpecification]) -> CodecNegotiator {
        switch policy {
        case .balanced:
            return BalancedCodecNegotiator(specifications: specifications)
        case .overrideFromServer:
            return ServerOverriddenCodecNegotiator(specifications: specifications)
        }
    }
}

