//
//  MainWindowRemoteSessionView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/3/26.
//

import SwiftUI

import SiriusKitClient

struct MainWindowRemoteSessionView: View {
    static let logger = NoctilucaLogger(category: "MainWindowRemoteSessionView")
    
    @Environment(SessionWindowViewModel.self)
    var viewModel: SessionWindowViewModel

    let remoteSession: RemoteSession

    let projection: RemoteSession.Projection

    let hidio: RemoteSession.HIDIO

    @State
    var subscription: ProjectionSessionSubscription?

    @State
    var sourceDescriptor: ProjectionSourceDescriptor = .displayID(-1)

    /// 진행 중인 backoff 재시도 task. `updateProjectionTarget` 호출 시 cancel 된다.
    @State
    private var retryTask: Task<Void, Never>?

    /// 현재 sourceDescriptor 가 디스플레이를 가리키는 경우의 displayID. -1 (= 미선택) 은 nil.
    private var currentDisplayID: Int? {
        if case .displayID(let id) = sourceDescriptor, id != -1 {
            return id
        }
        return nil
    }

    var body: some View {
        // @Environment로 받은 viewModel을 Binding으로 사용하기 위해 @Bindable 지역 선언.
        @Bindable var viewModel = viewModel

        VStack {
            if case .displayID(let displayID) = sourceDescriptor, displayID != -1 {
                RemoteSessionProjectionView(
                    remoteSession: remoteSession,
                    projection: projection,
                    hidio: hidio,
                    sourceDescriptor: $sourceDescriptor,
                    subscription: subscription
                )
            } else {
                ProgressView(String(localized: "mainwindow.remote-session.loading-display-layout", defaultValue: "디스플레이 구성을 로드하고 있습니다"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task {
                        // 혹시 정보가 누락되었을 경우를 대비해 재요청
                        try? await remoteSession.client.projectionChannel.updateDisplayLayout()
                        try? await self.decideTargetDisplayID()
                    }
            }
        }
        #if os(iOS)
        .onReceive(AppStateHolder.shared.$state) { appState in
            if appState == .foreground {
                if subscription == nil,
                   case .displayID(let displayID) = sourceDescriptor,
                   displayID != -1 {
                    Task {
                        try? await self.updateProjectionTarget(displayID)
                    }
                }
            } else {
                subscription?.invalidate()
                subscription = nil
            }
        }
        #endif
        .sessionOverlay(isPresented: $viewModel.shouldPresentDisplaySwitchSheet) {
            if case .displayID(let currentActive) = sourceDescriptor {
                let displayLayoutManager = projection.channel.displayLayoutManager
                let displays = Array(displayLayoutManager.displayLayouts.values)
                
                DisplaySwitcherSheet(
                    displays: displays,
                    currentActive: currentActive,
                ) { action in
                    try await self.dispatchDisplaySwitcherAction(action)
                }
                .task {
                    // 시트 표시 시 thumbnail 포함 디스플레이 목록 재요청
                    guard let response = try? await remoteSession.client.projectionChannel.requestDisplayList(flags: .includeThumbnails) else {
                        return
                    }
                    
                    for display in response.displays {
                        await remoteSession.client.projectionChannel.displayLayoutManager.update(display)
                    }
                }
                /*
                    .presentationDragIndicator(.visible)
                    .if(DeviceKind.current == .iPhone) {
                        $0.presentationDetents([.height(260)])
                    }
                    .if(DeviceKind.current == .iPad) {
                        $0.presentationSizing(.fitted)
                    }
                 */
            }
        } subcontent: {
            if case .displayID(let currentActive) = sourceDescriptor {
                let displayLayoutManager = projection.channel.displayLayoutManager
                let displays = Array(displayLayoutManager.displayLayouts.values)

                DisplayLayoutModifierView(displays: displays) { operations, mainDisplayID in
                    _ = try await remoteSession.client.projectionChannel.requestDisplayTransaction(
                        operations: operations,
                        mainDisplayID: mainDisplayID
                    )
                }
            }
        }
        /*
        .sheet(isPresented: $viewModel.shouldPresentDisplaySwitchSheet) {
            if case .displayID(let currentActive) = sourceDescriptor {
                let displayLayoutManager = projection.channel.displayLayoutManager
                let displays = Array(displayLayoutManager.displayLayouts.values)
                
                DisplaySwitcherSheet(
                    displays: displays,
                    currentActive: currentActive,
                    action: { newSourceDisplayID in
                        Task {
                            do {
                                try await self.updateProjectionTarget(newSourceDisplayID)
                            } catch {
                                Self.logger.error("디스플레이 전환 실패: \(error.localizedDescription)")
                            }
                        }
                    },
                    onDetach: viewModel.onDetachDisplay
                )
                    .task {
                        // 시트 표시 시 thumbnail 포함 디스플레이 목록 재요청
                        guard let response = try? await remoteSession.client.projectionChannel.requestDisplayList(flags: .includeThumbnails) else {
                            return
                        }

                        for display in response.displays {
                            await remoteSession.client.projectionChannel.displayLayoutManager.update(display)
                        }
                    }
                    .presentationDragIndicator(.visible)
                    .if(DeviceKind.current == .iPhone) {
                        $0.presentationDetents([.height(260)])
                    }
                    .if(DeviceKind.current == .iPad) {
                        $0.presentationSizing(.fitted)
                    }
            }
        }
         */
        .onChange(of: currentDisplayID.flatMap { projection.sessionErrors[$0] }) { _, error in
            // sessionErrors 는 displayID 키 dict 이므로 현재 보고 있는 디스플레이의 에러만 관찰한다.
            guard let error, let displayID = currentDisplayID else { return }
            handleProjectionError(error, displayID: displayID)
        }
        .onChange(of: projection.channel.displayLayoutManager.displayLayouts.count) { oldCount, newCount in
            // 모든 디스플레이가 사라졌다가 새로 connect 되면 자동으로 subscribe.
            // (DisplayInfo 가 Equatable 이 아니라 dict 자체를 onChange 할 수 없으므로 count 로 감시)
            guard currentDisplayID == nil, oldCount == 0, newCount > 0 else { return }
            Task {
                try? await self.decideTargetDisplayID()
            }
        }
    }
    
    func dispatchDisplaySwitcherAction(_ action: DisplaySwitcherAction) async throws {
        switch action {
        case .switchDisplay(let displayID):
            viewModel.shouldPresentDisplaySwitchSheet = false
            do {
                try await self.updateProjectionTarget(displayID)
            } catch {
                Self.logger.error("디스플레이 전환 실패: \(error.localizedDescription)")
            }
        case .createDetachedDisplay(let displayID):
            viewModel.shouldPresentDisplaySwitchSheet = false
            try await viewModel.onDetachDisplay?(displayID)
        case .createVirtualDisplay(let spec):
            let siriusSpec = DisplaySpec(
                resolution: SRSize(width: Double(spec.width), height: Double(spec.height)),
                refreshRate: spec.refreshRate,
                scaleFactor: spec.isHiDPI ? 2.0 : 1.0,
                metadata: [:]
            )
            _ = try await viewModel.remoteSession?.client.projectionChannel.requestDisplayTransaction(operations: [
                .init(operation: .createVirtualDisplay(VirtualDisplayCreate(
                    identifier: UUID(),
                    desiredSpecs: [siriusSpec],
                    purpose: "virtual-display",
                    metadata: [:]
                )))
            ])
        case .destroyVirtualDisplay(let identifier):
            _ = try await viewModel.remoteSession?.client.projectionChannel.requestDisplayTransaction(operations: [
                .init(operation: .destroyVirtualDisplay(VirtualDisplayDestroy(identifier: identifier)))
            ])
        }
    }

    func decideTargetDisplayID() async throws {
        if let primaryDisplayID = remoteSession.client.projectionChannel.displayLayoutManager.primaryDisplayID {
            try await updateProjectionTarget(primaryDisplayID)
        }
    }
    
    func updateProjectionTarget(_ displayID: Int) async throws {
        // 이전 displayID 의 진행 중인 retry 와 stale 한 에러 상태를 정리한다.
        // (Q4 답변: currentProjectionTarget 변경 시 retry 즉시 cancel)
        let previousDisplayID = await MainActor.run { () -> Int? in
            retryTask?.cancel()
            retryTask = nil
            return currentDisplayID
        }
        if let previousDisplayID, previousDisplayID != displayID {
            projection.clearSessionError(for: previousDisplayID)
        }
        // 이행 대상 displayID 의 stale 에러도 클리어 (수동 재시도 케이스 포함)
        projection.clearSessionError(for: displayID)

        let newSubscription = try await projection.subscribeProjectionSession(for: displayID)

        let previousSubscription = await MainActor.run { () -> ProjectionSessionSubscription? in
            let previous = self.subscription
            self.subscription = newSubscription
            self.sourceDescriptor = .displayID(displayID)
            return previous
        }

        previousSubscription?.invalidate()
    }

    // MARK: - Projection error handling

    /// `sessionErrors[currentDisplayID]` 가 채워졌을 때의 정책 분기.
    ///
    /// - 디스플레이가 사라진 경우: primary 디스플레이로 fallback (없으면 placeholder 대기)
    /// - 비재시도 reason (e.g. `clientRequested`): 노출만, 추가 시도 없음
    /// - 재시도 가능 reason: 1s/2s/4s × 3회 backoff retry. 실패 시 sessionError 가 그대로 남음
    @MainActor
    private func handleProjectionError(_ error: RemoteSession.ProjectionSessionFailureInfo, displayID: Int) {
        Self.logger.warning("Projection error on display \(displayID): reason=\(error.reason.rawValue), message=\(error.message ?? "(nil)")")

        // 어떤 분기로 가든 기존 subscription 은 무효
        subscription?.invalidate()
        subscription = nil

        let layoutManager = projection.channel.displayLayoutManager

        // 디스플레이 자체가 사라졌으면 즉시 fallback
        if layoutManager.displayLayouts[displayID] == nil {
            Task { await fallbackToPrimaryOrWait() }
            return
        }

        // 비재시도 reason 은 노출만 (사용자 수동 재시도 대기)
        guard error.reason.isRetryable else {
            return
        }

        // backoff 재시도
        retryTask?.cancel()
        retryTask = Task { @MainActor in
            do {
                let newSubscription = try await projection.subscribeWithBackoff(for: displayID)
                // retry 도중 사용자가 다른 디스플레이로 이동했을 가능성 대비
                guard currentDisplayID == displayID else {
                    newSubscription.invalidate()
                    return
                }
                let previous = self.subscription
                self.subscription = newSubscription
                previous?.invalidate()
            } catch is CancellationError {
                // 사용자 전환 등으로 정상 cancel
            } catch ProjectionRetryError.displayDisappeared {
                await fallbackToPrimaryOrWait()
            } catch {
                Self.logger.error("Projection retry failed permanently for display \(displayID): \(error.localizedDescription)")
                // sessionErrors[displayID] 는 그대로 남아 사용자에게 노출됨
            }
        }
    }

    /// primary 디스플레이로 전환을 시도하고, primary 가 없으면 placeholder UI 로 돌아가
    /// 디스플레이가 다시 connect 될 때까지 대기한다.
    @MainActor
    private func fallbackToPrimaryOrWait() async {
        let layoutManager = projection.channel.displayLayoutManager
        if let primary = layoutManager.primaryDisplayID, primary != currentDisplayID {
            do {
                try await updateProjectionTarget(primary)
            } catch {
                Self.logger.error("Failed to fall back to primary display \(primary): \(error.localizedDescription)")
                sourceDescriptor = .displayID(-1)
            }
        } else {
            // primary 도 없는 상태 → placeholder 로 돌아가서 displayLayouts 변화를 기다림
            sourceDescriptor = .displayID(-1)
        }
    }
}
