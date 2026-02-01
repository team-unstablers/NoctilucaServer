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
final class NOCAudioEngine: @unchecked Sendable {
    static let shared = NOCAudioEngine()

    private let logger = SiriusLogger(category: "NOCAudioEngine", subsystem: "pl.unstabler.noctiluca.NoctilucaClient")
    
    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "pl.unstabler.noctiluca.NOCAudioEngine")
    
    private var activeNodes: Int = 0

    private init() {
        // Prepare the engine immediately? Or lazily?
        // AVAudioEngine usually doesn't need explicit prepare if we connect nodes,
        // but explicit prepare is good practice.
        engine.prepare()
        logger.info("NOCAudioEngine initialized")
    }

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
                    
                    // Always reconnect to ensure format matches (or check if already connected?)
                    // AVAudioEngine allows reconnecting.
                    self.engine.connect(node, to: self.engine.mainMixerNode, format: format)
                    
                    // 2. Manage lifecycle
                    self.activeNodes += 1
                    self.logger.debug("Node attached. Active nodes: \(self.activeNodes)")
                    
                    if self.activeNodes == 1 {
                        if !self.engine.isRunning {
                            self.logger.info("Starting AVAudioEngine...")
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
            
            logger.debug("Node detached. Active nodes: \(activeNodes)")
            
            if activeNodes == 0 && engine.isRunning {
                logger.info("No active nodes. Pausing AVAudioEngine to save resources.")
                engine.pause()
            }
        }
    }
}
