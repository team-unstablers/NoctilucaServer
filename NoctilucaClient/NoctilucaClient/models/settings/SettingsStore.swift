//
//  SettingsStore.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/21/25.
//

import SwiftUI
import Combine

import SiriusKitClient

final class SettingsStore: ObservableObject {
    private static let logger = NoctilucaLogger(category: "SettingsStore")

    @Published
    var settings: AppSettings!
    
    private var cancellables: Set<AnyCancellable> = []

    init(settings: AppSettings = AppSettings(), loadFromDisk: Bool = true) {
        // TODO: ensure this runs on main thread
        
        if loadFromDisk {
            self.settings = (try? AppSettings.load()) ?? settings
        } else {
            self.settings = settings
        }
        
        setupAutosave()
    }

    func resetInputSettings() {
        settings.input = .init()
    }

    func save() {
        DispatchQueue.main.async {
            do {
                try self.settings.save()
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
