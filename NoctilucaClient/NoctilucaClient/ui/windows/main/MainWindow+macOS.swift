//
//  AppKitMainWindow.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/10/25.
//

#if os(macOS)
import AppKit
import SwiftUI

final class AppKitMainWindowController: NSWindowController, NSWindowDelegate {
    private let viewModel: MainWindowViewModel
    private let toolbarController: MainToolbar
    var onClose: ((AppKitMainWindowController) -> Void)?
    
    init(settingsStore: SettingsStore) {
        self.viewModel = MainWindowViewModel()
        self.toolbarController = MainToolbar(viewModel: viewModel, settingsStore: settingsStore)
        
        let contentView = MainWindowRootView(viewModel: viewModel)
            .environmentObject(settingsStore)
        
        let hostingView = NSHostingView(rootView: contentView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.contentView = hostingView
        window.title = NoctilucaMeta.productName
        window.minSize = NSSize(width: 640, height: 480)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("NoctilucaClient.MainWindow")
        window.center()
        
        super.init(window: window)
        
        window.delegate = self

        toolbarController.attach(to: window)
    }

    func windowWillClose(_ notification: Notification) {
        viewModel.setInputFocusActive(false)
        onClose?(self)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        viewModel.setInputFocusActive(true)
    }

    func windowDidResignKey(_ notification: Notification) {
        viewModel.setInputFocusActive(false)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct MainWindowRootView: View {
    @ObservedObject
    var viewModel: MainWindowViewModel

    @EnvironmentObject
    private var settingsStore: SettingsStore

    /*
    private var sessionSettingsActions: [SessionSettingsSheet.Action] {
        switch viewModel.sessionSettingsSheetMode {
        case .quickConnect:
            let canConnect = viewModel.canConnectFromDraft
            return [
                .init(kind: .cancel, title: "취소", role: .cancel) {
                    viewModel.dismissSessionSettingsSheet()
                },
                .init(kind: .secondary, title: "연락처에 저장하기", isEnabled: canConnect) {
                    viewModel.saveContactAndConnectFromSheet()
                },
                .init(kind: .primary, title: "연결만 하기", isEnabled: canConnect) {
                    viewModel.connectWithoutSavingFromSheet()
                }
            ]
        case .contactEditor:
            var actions: [SessionSettingsSheet.Action] = [
                .init(kind: .cancel, title: "취소", role: .cancel) {
                    viewModel.dismissSessionSettingsSheet()
                }
            ]
            if viewModel.isEditingContact {
                actions.append(
                    .init(kind: .secondary, title: "삭제", role: .destructive) {
                        viewModel.requestDeleteContactConfirmation()
                    }
                )
            }
            actions.append(
                .init(kind: .primary, title: viewModel.isEditingContact ? "저장" : "추가") {
                    viewModel.saveContactFromSheet()
                }
            )
            return actions
        }
    }
     */
    
    var body: some View {
        MainWindowContentView()
            .frame(minWidth: 640, minHeight: 480)
            .environmentObject(viewModel)
            .alert(isPresented: $viewModel.shouldDisplayErrorAlert) {
                let error = viewModel.errors.last
                
                return Alert(
                    title: Text("오류 발생"),
                    message: Text(error?.localizedDescription ?? "알 수 없는 오류가 발생했습니다."),
                    dismissButton: .default(Text("확인")) {
                        viewModel.dismissLastError()
                    }
                )
            }
            .sheet(isPresented: $viewModel.isSessionSettingsSheetPresented) {
                SessionSettingsSheet(
                    scope: .session,
                    sessionSettings: $viewModel.sessionSettingsDraft.settings,
                    contactId: viewModel.sessionSettingsSheetMode == .quickConnect ? nil : viewModel.sessionSettingsDraft.id,
                ) { action in
                    switch action {
                    case .cancel:
                        viewModel.dismissSessionSettingsSheet()
                    case .delete:
                        viewModel.cancelDeleteContactConfirmation()
                    case .connect:
                        viewModel.connectWithoutSavingFromSheet()
                    case .saveAndConnect:
                        viewModel.saveContactAndConnectFromSheet()
                    case .save:
                        viewModel.saveContactFromSheet()
                    }
                    
                    viewModel.dismissSessionSettingsSheet()
                }
            }

            .setupClientPhaseHandler(client: viewModel.client) { phase in
                viewModel.handleClientPhaseChanged(phase)
            }
            .setupClientErrorHandler(client: viewModel.client) { error in
                viewModel.handleClientError(error)
            }
            .setupAuthChallengeHandler(client: viewModel.client)
            .setupClientStatisticsHandler(client: viewModel.client, viewModel: viewModel)
            .onAppear {
                viewModel.bind(settingsStore: settingsStore)
                viewModel.startContactObservation()
            }
    }
}
#endif
