//
//  ProjectionChannel+displayman_manip.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 4/20/26.
//

import Foundation
import CoreGraphics

import SiriusKit

extension ProjectionChannel {
    func handleDisplayTransactionRequest(_ request: DisplayTransactionRequest) async throws {
        let txID = request.transactionID

        guard let sessionID = clientSession?.id else {
            try await sendDisplayTransactionResponse(transactionID: txID, isSuccess: false, reason: "client session is not available")
            return
        }

        guard await state.lifecycleState == .active else {
            try await sendDisplayTransactionResponse(transactionID: txID, isSuccess: false, reason: "channel is not active")
            return
        }

        // ── Operation 분류
        var creates: [VirtualDisplayCreate] = []
        var destroys: [VirtualDisplayDestroy] = []
        var changes: [DisplayLayoutChange] = []
        var setEnables: [DisplaySetEnable] = []

        for op in request.operations {
            switch op.operation {
            case .createVirtualDisplay(let v): creates.append(v)
            case .destroyVirtualDisplay(let v): destroys.append(v)
            case .change(let v): changes.append(v)
            case .setEnable(let v): setEnables.append(v)
            case .none: break
            }
        }

        let projectionSettings = await NoctilucaServer.shared.settings.projection

        // ── Phase 1: Validation
        if !creates.isEmpty || !destroys.isEmpty {
            guard projectionSettings.allowVirtualDisplay else {
                try await sendDisplayTransactionResponse(transactionID: txID, isSuccess: false, reason: "virtual display is not allowed by server policy")
                return
            }
        }

        if !changes.isEmpty || !setEnables.isEmpty || request.mainDisplayID != nil {
            guard projectionSettings.allowModifyDisplayLayout else {
                try await sendDisplayTransactionResponse(transactionID: txID, isSuccess: false, reason: "display layout modification is not allowed by server policy")
                return
            }
        }

        if let conflict = await state.virtualDisplayIdentifierConflict(in: creates.map { $0.identifier }) {
            try await sendDisplayTransactionResponse(transactionID: txID, isSuccess: false, reason: "duplicate virtual display identifier: \(conflict)")
            return
        }

        let layoutManager = await DisplayLayoutManager.shared
        let knownDisplayIDs = await MainActor.run {
            Set(layoutManager.displayLayouts.snapshot().keys)
        }

        let layoutTargetIDs = (changes.map { $0.displayID } + setEnables.map { $0.displayID }).map { CGDirectDisplayID($0) }
        for displayID in layoutTargetIDs {
            guard knownDisplayIDs.contains(displayID) else {
                try await sendDisplayTransactionResponse(transactionID: txID, isSuccess: false, reason: "unknown displayID: \(displayID)")
                return
            }
        }

        // ── Phase 2: Virtual Display Create (실패 시 rollback)
        var spawned: [(externalID: UUID, handle: NOCVirtualDisplayHandle)] = []

        for create in creates {
            let purpose = NOCVirtualDisplayPurpose.fromWire(create.purpose)
            let specs = create.desiredSpecs.map { NOCDisplaySpec(from: $0) }

            do {
                let handle = try await layoutManager.acquireVirtualDisplay(
                    ownedBy: sessionID,
                    purpose: purpose,
                    specs: specs
                )

                guard await state.registerVirtualDisplay(externalID: create.identifier, handle: handle) else {
                    await layoutManager.destroyVirtualDisplay(handle)
                    await rollbackSpawned(spawned)
                    try await sendDisplayTransactionResponse(transactionID: txID, isSuccess: false, reason: "failed to register virtual display \(create.identifier)")
                    return
                }

                spawned.append((create.identifier, handle))
            } catch {
                await rollbackSpawned(spawned)
                try await sendDisplayTransactionResponse(transactionID: txID, isSuccess: false, reason: "virtual display create failed: \(error)")
                return
            }
        }

        // ── Phase 3a: Spec 변경 (개별 호출, atomic하지 않음 — best-effort)
        for change in changes {
            let displayID = CGDirectDisplayID(change.displayID)

            if let siriusSpec = change.spec {
                let spec = NOCDisplaySpec(from: siriusSpec)
                do {
                    try await MainActor.run {
                        try layoutManager.applySpec(to: displayID, spec: spec)
                    }
                } catch {
                    await rollbackSpawned(spawned)
                    try await sendDisplayTransactionResponse(transactionID: txID, isSuccess: false, reason: "applySpec failed for display \(displayID): \(error)")
                    return
                }
            }

            // TODO: change.rotation 적용 (NOC 측 회전 인프라 부재)
        }

        // ── Phase 3b: Layout/SetEnable/Position + mainDisplayID (단일 atomic apply)
        let hasPositionChange = changes.contains { $0.position != nil }
        if !setEnables.isEmpty || request.mainDisplayID != nil || hasPositionChange {
            do {
                try await MainActor.run {
                    var layoutMap: [CGDirectDisplayID: CGRect?] = [:]
                    for (displayID, screen) in layoutManager.displayLayouts.snapshot() {
                        layoutMap[displayID] = screen.frame
                    }

                    for se in setEnables {
                        let id = CGDirectDisplayID(se.displayID)
                        if se.isEnabled {
                            if layoutMap[id] == .some(nil) {
                                layoutMap[id] = .zero
                            }
                            // 이미 non-nil이면 현재 frame 유지
                        } else {
                            layoutMap[id] = .some(nil)
                        }
                    }

                    // position 변경 반영: 기존 size는 유지하고 origin만 교체
                    for change in changes {
                        guard let position = change.position else { continue }
                        let id = CGDirectDisplayID(change.displayID)
                        if let existing = layoutMap[id], let frame = existing {
                            layoutMap[id] = CGRect(
                                origin: CGPoint(x: position.x, y: position.y),
                                size: frame.size
                            )
                        }
                        // 비활성화 상태(frame == nil)인 디스플레이에는 position 적용하지 않음
                    }

                    let mainID = request.mainDisplayID.map { CGDirectDisplayID($0) }
                    try layoutManager.applyLayout(layout: layoutMap, mainDisplayID: mainID)
                }
            } catch {
                logger.error("failed to apply layout in transaction \(txID): \(error)")
                await rollbackSpawned(spawned)
                try await sendDisplayTransactionResponse(transactionID: txID, isSuccess: false, reason: "applyLayout failed: \(error)")
                return
            }
        }

        // ── Phase 4: Virtual Display Destroy (best-effort, 미존재 시 silent ignore)
        for d in destroys {
            if let handle = await state.takeVirtualDisplay(externalID: d.identifier) {
                await layoutManager.destroyVirtualDisplay(handle)
            }
        }

        try await sendDisplayTransactionResponse(transactionID: txID, isSuccess: true, reason: nil)
    }

    private func rollbackSpawned(_ spawned: [(externalID: UUID, handle: NOCVirtualDisplayHandle)]) async {
        let layoutManager = await DisplayLayoutManager.shared
        for entry in spawned {
            _ = await state.takeVirtualDisplay(externalID: entry.externalID)
            await layoutManager.destroyVirtualDisplay(entry.handle)
        }
    }

    private func sendDisplayTransactionResponse(transactionID: UUID, isSuccess: Bool, reason: String?) async throws {
        try await handle.send(opcode: .displayTransactionResponse, message: DisplayTransactionResponse(
            transactionID: transactionID,
            isSuccess: isSuccess,
            reason: reason
        ))
    }
}
