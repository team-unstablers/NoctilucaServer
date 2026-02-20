//
//  SettingsStore.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 2/20/26.
//

import Foundation
import Combine

import SwiftUI

import SiriusKit

final class SettingsStore: ObservableObject {
    private static let logger = NoctilucaLogger(category: "SettingsStore")

    static let shared = SettingsStore()

    @Published
    var settings: AppSettings!

    // MARK: - Daemon Settings (XPC)

    /// noctilucad에서 가져온 데몬 설정. XPC 연결이 성공하기 전에는 nil.
    @Published
    var daemonSettings: DaemonSettings? = nil

    /// noctilucad 설정 XPC 클라이언트.
    let daemonSettingsClient = DaemonSettingsXPCClient()

    private var cancellables: Set<AnyCancellable> = []

    private init(settings: AppSettings = AppSettings(), loadFromDisk: Bool = true) {
        if loadFromDisk {
            self.settings = (try? AppSettings.load()) ?? settings
        } else {
            self.settings = settings
        }
        
        Task {
            await self.loadDaemonSettings()
        }

        setupAutosave()
    }

    func save() {
        DispatchQueue.main.async {
            do {
                try self.settings.save()
                NoctilucaLoggingConfigurator.apply(settings: self.settings.logging)
            } catch {
                Self.logger.error("Failed to save settings: \(error.localizedDescription)")
            }
        }
    }

    func reload() {
        DispatchQueue.main.async {
            self.settings = (try? AppSettings.load()) ?? AppSettings()
        }
    }

    // MARK: - Daemon Settings

    /// noctilucad에서 데몬 설정을 로드한다.
    func loadDaemonSettings() async {
        do {
            let ds = try await daemonSettingsClient.getSettings()
            await MainActor.run {
                self.daemonSettings = ds
            }
        } catch {
            Self.logger.error("Failed to load daemon settings: \(error.localizedDescription)")
        }
    }

    /// 현재 데몬 설정을 noctilucad에 저장한다.
    func saveDaemonSettings() async {
        guard let ds = daemonSettings else { return }
        do {
            try await daemonSettingsClient.updateSettings(ds)
        } catch {
            Self.logger.error("Failed to save daemon settings: \(error.localizedDescription)")
        }
    }

    private func setupAutosave() {
        $settings
            .dropFirst()
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.save()
            }
            .store(in: &cancellables)
        
        $daemonSettings
            .dropFirst(2)
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task {
                    print("saving daemon settings")
                    await self?.saveDaemonSettings()
                }
            }
            .store(in: &cancellables)
    }
}
