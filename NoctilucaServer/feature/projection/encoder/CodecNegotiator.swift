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
    open func negotiate(with theirs: [CodecSpecification]) -> CodecSpecification? {
        // to be overridden
        fatalError("Not implemented")
    }
}

class BalancedCodecNegotiator: CodecNegotiator {
    /// 두 스펙 셋의 엄격한 합집합을 구합니다.
    func unionStrict(_ ours: [CodecSpecification], _ theirs: [CodecSpecification]) -> [CodecSpecification] {
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
    
    /// 두 스펙 셋의 완화된 합집합을 구합니다.
    func union(_ ours: [CodecSpecification], _ theirs: [CodecSpecification]) -> [CodecSpecification] {
        var result: [CodecSpecification] = []
        
        // 최대한 클라이언트의 순서를 존중한다
        for theirsSpec in theirs {
            for oursSpec in ours {
                if oursSpec.isCompatible(with: theirsSpec) {
                    result.append(theirsSpec)
                }
            }
        }
        
        return result
    }
    
    func selectFallbackCodec(_ ours: [CodecSpecification],
        _ theirs: [CodecSpecification]
    ) -> CodecSpecification? {
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
    
    override func negotiate(with theirs: [CodecSpecification]) -> CodecSpecification? {
        // 1. 엄격한 합집합 우선 - exact match를 기반으로 결정을 시도한다
        let strictCandidates = unionStrict(self.ours, theirs)
        if let realizable = strictCandidates.first(where: { $0.isRealizable() }) {
            return realizable
        }
        
        // 2. 완화된 합집합 시도 - isCompatible() 기반으로 결정을 시도한다
        let candidates = union(self.ours, theirs)
        if let realizable = candidates.first(where: { $0.isRealizable() }) {
            return realizable
        }
       
        // 3. 호환되는 코덱 스펙이 없으므로 클라이언트와 서버 양쪽 다 처리 가능한 코덱 중 하나를 임의로 선택한다
        if let fallback = selectFallbackCodec(self.ours, theirs) {
            return fallback
        }
        
        // 4. 최종 실패
        return nil
    }
}

class ServerOverridenCodecNegotiator: CodecNegotiator {
    override func negotiate(with theirs: [CodecSpecification]) -> CodecSpecification? {
        // 서버 측 우선 정책: 서버 측 스펙 셋에서 실현 가능한 첫 번째 스펙을 반환한다
        return ours.first(where: { $0.isRealizable() } )
    }
}


extension CodecNegotiator {
    static func create(from policy: CodecNegotiationPolicy, specifications: [CodecSpecification]) -> CodecNegotiator {
        switch policy {
        case .balanced:
            return BalancedCodecNegotiator(specifications: specifications)
        case .overrideFromServer:
            return ServerOverridenCodecNegotiator(specifications: specifications)
        }
    }
}

extension CodecNegotiator {
    func negotiate(with siriusKitSpecs: [SiriusKit.Codec]) -> CodecSpecification? {
        let theirs = siriusKitSpecs.map { CodecSpecification(siriusKit: $0) }
        return negotiate(with: theirs)
    }
}
