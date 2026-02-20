//
//  SettingsStore.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 2/20/26.
//

import Foundation
import Combine

import SiriusKit

final class SettingsStore: ObservableObject {
    private static let logger = NoctilucaLogger(category: "SettingsStore")

    static let shared = SettingsStore()

    @Published
    var settings: AppSettings!

    private var cancellables: Set<AnyCancellable> = []

    private init(settings: AppSettings = AppSettings(), loadFromDisk: Bool = true) {
        if loadFromDisk {
            self.settings = (try? AppSettings.load()) ?? settings
        } else {
            self.settings = settings
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

    private func setupAutosave() {
        $settings
            .dropFirst()
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.save()
            }
            .store(in: &cancellables)
    }
}
