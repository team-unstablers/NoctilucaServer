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
    
    @State
    var referenceTicket: RemoteSession.SessionReferenceTicket?
    
    @State
    var sourceDescriptor: ProjectionSourceDescriptor = .displayID(-1)
    
    var body: some View {
        VStack {
            if case .displayID(let displayID) = sourceDescriptor, displayID != -1 {
                RemoteSessionProjectionView(
                    remoteSession: remoteSession,
                    projection: projection,
                    sourceDescriptor: $sourceDescriptor
                )
            } else {
                ProgressView("디스플레이 구성을 로드하고 있습니다")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task {
                        // 혹시 정보가 누락되었을 경우를 대비해 재요청
                        try? await remoteSession.client.projectionChannel.updateDisplayLayout()
                        try? await self.decideTargetDisplayID()
                    }
            }
        }
        .sheet(isPresented: $viewModel.shouldPresentDisplaySwitchSheet) {
            if case .displayID(let currentActive) = sourceDescriptor {
                let displayLayoutManager = projection.channel.displayLayoutManager
                let displays = Array(displayLayoutManager.displayLayouts.values)
                
                DisplaySwitcherSheet(displays: displays, currentActive: currentActive) { newSourceDisplayID in
                    Task {
                        do {
                            try await self.updateProjectionTarget(newSourceDisplayID)
                        } catch {
                            Self.logger.error("디스플레이 전환 실패: \(error.localizedDescription)")
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
        let ticket = try await projection.subscribeProjectionSession(for: displayID)
        
        await MainActor.run {
            self.referenceTicket = ticket
            self.sourceDescriptor = .displayID(displayID)
        }
    }
}
