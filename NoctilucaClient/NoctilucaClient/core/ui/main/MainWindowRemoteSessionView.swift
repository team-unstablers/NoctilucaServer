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
    
    @EnvironmentObject
    var viewModel: SessionWindowViewModel

    @ObservedObject
    var remoteSession: RemoteSession
    
    @ObservedObject
    var projection: RemoteSession.Projection
    
    @ObservedObject
    var hidio: RemoteSession.HIDIO

    @State
    var subscription: ProjectionSessionSubscription?
    
    @State
    var sourceDescriptor: ProjectionSourceDescriptor = .displayID(-1)
    
    var body: some View {
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
                        await Task.detached {
                            try? await remoteSession.client.projectionChannel.updateDisplayLayout()
                        }.value
                        try? await self.decideTargetDisplayID()
                    }
            }
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            subscription = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            if subscription == nil,
               case .displayID(let displayID) = sourceDescriptor,
               displayID != -1 {
                Task.detached {
                    try? await self.updateProjectionTarget(displayID)
                }
            }
        }
        #endif
        .sheet(isPresented: $viewModel.shouldPresentDisplaySwitchSheet) {
            if case .displayID(let currentActive) = sourceDescriptor {
                let displayLayoutManager = projection.channel.displayLayoutManager
                let displays = Array(displayLayoutManager.displayLayouts.values)
                
                DisplaySwitcherSheet(
                    displays: displays,
                    currentActive: currentActive,
                    action: { newSourceDisplayID in
                        Task.detached {
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
                        let response = await Task.detached {
                            try? await remoteSession.client.projectionChannel.requestDisplayList(flags: .includeThumbnails)
                        }.value

                        if let response {
                            for display in response.displays {
                                await remoteSession.client.projectionChannel.displayLayoutManager.update(display)
                            }
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
    }
    
    func decideTargetDisplayID() async throws {
        if let primaryDisplayID = remoteSession.client.projectionChannel.displayLayoutManager.primaryDisplayID {
            try await updateProjectionTarget(primaryDisplayID)
        }
    }
    
    func updateProjectionTarget(_ displayID: Int) async throws {
        let subscription = try await projection.subscribeProjectionSession(for: displayID)

        await MainActor.run {
            self.subscription = subscription
            self.sourceDescriptor = .displayID(displayID)
        }
    }
}
