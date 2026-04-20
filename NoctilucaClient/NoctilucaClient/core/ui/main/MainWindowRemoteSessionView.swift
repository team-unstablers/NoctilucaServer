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

    var body: some View {
        // @Environment로 받은 viewModel을 Binding으로 사용하기 위해 @Bindable 지역 선언.
        @Bindable var viewModel = viewModel

        VStack {
            if case .active(_) =  viewModel.appStreamState {
                Text("AppStream 활성화됨")
                    .onAppear {
                        subscription = nil
                    }
            } else {
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
                            await Task.detached {
                                try? await remoteSession.client.projectionChannel.updateDisplayLayout()
                            }.value
                            try? await self.decideTargetDisplayID()
                        }
                }
            }
        }
        #if os(iOS)
        .onReceive(AppStateHolder.shared.$state) { appState in
            if appState == .foreground {
                if subscription == nil,
                   case .displayID(let displayID) = sourceDescriptor,
                   displayID != -1 {
                    Task.detached {
                        try? await self.updateProjectionTarget(.displayID(displayID))
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
                                try await self.updateProjectionTarget(.displayID(newSourceDisplayID))
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
#if os(macOS)
        .sessionOverlay(isPresented: $viewModel.isAppStreamAppSelectorPresented) {
            AppStreamPickerSheet(
                listLoader: {
                    guard let session = viewModel.remoteSession else {
                        return []
                    }
                    let response = try await session.client.projectionChannel.getApplicationList(
                        flags: [.includeIcons]
                    )
                    return response.applications
                },
                actionHandler: { action in
                    await self.dispatchAppStreamPickerAction(action)
                }
            )
        } subcontent: {
            EmptyView()
        }
#endif
        /*
         // TODO: 어떤 세션에 대한 에러인지 구분이 안되니까, 다른 디스플레이로 전환했을 때 그냥 꺼짐
        .onReceive(projection.$sessionError) { error in
            if error != nil {
                // 세션이 서버에 의해 종료되었으므로 기존 subscription을 정리
                subscription?.invalidate()
                subscription = nil
            }
        }
         */
    }
    
    func dispatchDisplaySwitcherAction(_ action: DisplaySwitcherAction) async throws {
        switch action {
        case .switchDisplay(let displayID):
            do {
                try await self.updateProjectionTarget(.displayID(displayID))
            } catch {
                Self.logger.error("디스플레이 전환 실패: \(error.localizedDescription)")
            }
        case .createDetachedDisplay(let displayID):
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

#if os(macOS)
    @MainActor
    func dispatchAppStreamPickerAction(_ action: AppStreamPickerAction) async {
        switch action {
        case .selectApp(let bundleId):
            viewModel.isAppStreamAppSelectorPresented = false
            viewModel.appStreamState = .active(bundleIdentifier: bundleId)
        }
    }
#endif

    func decideTargetDisplayID() async throws {
        if let primaryDisplayID = remoteSession.client.projectionChannel.displayLayoutManager.primaryDisplayID {
            try await updateProjectionTarget(.displayID(primaryDisplayID))
        }
    }

    func updateProjectionTarget(_ source: ProjectionSourceDescriptor) async throws {
        let newSubscription = try await projection.subscribeProjectionSession(for: source)

        let previousSubscription = await MainActor.run { () -> ProjectionSessionSubscription? in
            let previous = self.subscription
            self.subscription = newSubscription
            self.sourceDescriptor = source
            return previous
        }

        previousSubscription?.invalidate()
    }
}
