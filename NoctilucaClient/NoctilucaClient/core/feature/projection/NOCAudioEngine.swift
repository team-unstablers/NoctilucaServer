//
//  NOCAudioEngine.swift
//  NoctilucaClient
//
//  Created by Gemini Agent on 2/1/26.
//

import Foundation
import AVFoundation
import SiriusKitClient

/// Shared audio engine manager for mixing multiple audio sessions.
/// Maintains a single `AVAudioEngine` instance and manages its lifecycle based on active connections.
/// Handles audio interruptions and route changes to automatically recover playback.
final class NOCAudioEngine: @unchecked Sendable {
    static let shared = NOCAudioEngine()

    private let logger = SiriusLogger(category: "NOCAudioEngine", subsystem: "app.noctiluca.client")

    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "app.noctiluca.client.audio-engine")

    private var activeNodes: Int = 0

    private init() {
        logger.info("NOCAudioEngine initialized")

        #if os(iOS)
        configureAudioSession()
        #endif

        setupNotificationObservers()
    }

    // MARK: - Audio Session Configuration

    #if os(iOS)
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            logger.info("AVAudioSession configured: category=playback, mixWithOthers")
        } catch {
            logger.error("Failed to configure AVAudioSession: \(error.localizedDescription)")
        }
    }
    #endif

    // MARK: - Notification Observers

    private func setupNotificationObservers() {
        // Engine configuration change (both platforms)
        // Fires when the audio hardware configuration changes (e.g. sample rate, channel count)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEngineConfigurationChange(_:)),
            name: .AVAudioEngineConfigurationChange,
            object: engine
        )

        #if os(iOS)
        // Audio session interruption (phone calls, alarms, Siri, etc.)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )

        // Audio route change (headphone plug/unplug, Bluetooth connect/disconnect)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )

        // Media services reset (rare, but requires full re-initialization)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMediaServicesWereReset(_:)),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: AVAudioSession.sharedInstance()
        )
        #endif
    }

    // MARK: - Notification Handlers

    @objc private func handleEngineConfigurationChange(_ notification: Notification) {
        logger.info("AVAudioEngine configuration changed, attempting restart...")
        restartEngineIfNeeded()
    }

    #if os(iOS)
    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            logger.info("Audio session interruption began")

        case .ended:
            logger.info("Audio session interruption ended")

            // Re-activate the audio session
            do {
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                logger.error("Failed to re-activate audio session: \(error.localizedDescription)")
            }

            restartEngineIfNeeded()

        @unknown default:
            break
        }
    }

    @objc private func handleAudioRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        switch reason {
        case .oldDeviceUnavailable:
            // Headphones/AirPods disconnected.
            // For a remote desktop app, continue playback through the speaker.
            logger.info("Audio output device disconnected, switching to available output...")
            restartEngineIfNeeded()

        case .newDeviceAvailable:
            logger.info("New audio output device available")
            restartEngineIfNeeded()

        default:
            break
        }
    }

    @objc private func handleMediaServicesWereReset(_ notification: Notification) {
        logger.warning("Media services were reset. Re-configuring audio session and engine...")

        // Re-configure the audio session from scratch
        configureAudioSession()
        restartEngineIfNeeded()
    }
    #endif

    // MARK: - Engine Recovery

    /// Restarts the engine if there are active nodes but the engine is not running.
    private func restartEngineIfNeeded() {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard self.activeNodes > 0, !self.engine.isRunning else { return }

            do {
                self.engine.prepare()
                try self.engine.start()
                self.logger.info("AVAudioEngine restarted successfully (active nodes: \(self.activeNodes))")
            } catch {
                self.logger.error("Failed to restart AVAudioEngine: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Node Management

    /// Attaches a node to the engine and starts the engine if it's the first node.
    /// - Parameters:
    ///   - node: The source node to attach.
    ///   - format: The audio format for the connection.
    func attach(_ node: AVAudioNode, format: AVAudioFormat) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: NSError(domain: "NOCAudioEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Engine deallocated"]))
                    return
                }

                do {
                    // 1. Attach and connect
                    if self.engine.attachedNodes.contains(node) {
                        self.logger.warning("Node already attached, skipping attach.")
                    } else {
                        self.engine.attach(node)
                    }

                    // Always reconnect to ensure format matches.
                    // AVAudioEngine allows reconnecting.
                    self.engine.connect(node, to: self.engine.mainMixerNode, format: format)

                    // 2. Manage lifecycle
                    self.activeNodes += 1
                    self.logger.debug("Node attached. Active nodes: \(self.activeNodes)")

                    if self.activeNodes == 1 {
                        if !self.engine.isRunning {
                            self.logger.info("Starting AVAudioEngine...")
                            self.engine.prepare()
                            try self.engine.start()
                            self.logger.info("AVAudioEngine started.")
                        }
                    }

                    continuation.resume()
                } catch {
                    self.logger.error("Failed to start engine: \(error.localizedDescription)")

                    // Rollback
                    self.activeNodes -= 1
                    self.engine.detach(node)

                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Detaches a node from the engine and pauses the engine if no nodes remain.
    /// This method is synchronous to be safely called from `deinit`.
    /// - Parameter node: The source node to detach.
    func detach(_ node: AVAudioNode) {
        queue.sync {
            // Check if node is actually attached to avoid errors
            guard engine.attachedNodes.contains(node) else {
                return
            }

            engine.disconnectNodeOutput(node)
            engine.detach(node)

            if activeNodes > 0 {
                activeNodes -= 1
            }

            logger.debug("Node detached. Active nodes: \(self.activeNodes)")

            if activeNodes == 0 && engine.isRunning {
                logger.info("No active nodes. Pausing AVAudioEngine to save resources.")
                engine.pause()
            }
        }
    }
}
