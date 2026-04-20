//
//  DisplayLayoutManager+VirtualDisplay.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 4/17/26.
//

import Foundation

extension DisplayLayoutManager {
    /// 지정된 세션이 소유하는 새 가상 디스플레이를 생성한다.
    /// 내부적으로 `nocvirtdisplay` helper 프로세스를 spawn하고 stdout에서 DisplayID를 파싱한다.
    ///
    /// - Note: `AppSettings.projection.allowVirtualDisplay` 정책 검증과 상한 검증은 상위
    ///   계층(예: ProjectionChannel 라우팅) 책임이다. 이 API는 정책을 재검증하지 않는다.
    func acquireVirtualDisplay(
        ownedBy sessionID: UUID,
        purpose: NOCVirtualDisplayPurpose,
        specs: [NOCDisplaySpec]
    ) async throws -> NOCVirtualDisplayHandle {
        return try await virtualDisplayManager.spawn(
            ownedBy: sessionID,
            purpose: purpose,
            specs: specs
        )
    }

    /// 주어진 핸들의 가상 디스플레이를 파괴한다. 이미 파괴되었거나 알 수 없는 핸들이면 조용히 무시한다.
    func destroyVirtualDisplay(_ handle: NOCVirtualDisplayHandle) async {
        await virtualDisplayManager.destroy(handle)
    }

    /// 해당 세션이 소유한 모든 가상 디스플레이를 파괴한다. 세션 teardown 경로에서 호출한다.
    func destroyAllVirtualDisplays(ownedBy sessionID: UUID) async {
        await virtualDisplayManager.destroyAll(ownedBy: sessionID)
    }
}
