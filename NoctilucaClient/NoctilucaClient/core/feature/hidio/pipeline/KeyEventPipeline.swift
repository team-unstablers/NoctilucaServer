//
//  KeyEventPipeline.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/12/26.
//

import Foundation

import SiriusKitClient

@MainActor
protocol KeyEventPipeline {
    func process(_ keyEvent: KeyboardEvent) -> KeyboardEvent?
}

@MainActor
final class KeyEventPipelineChain: KeyEventPipeline {
    private var stages: [KeyEventPipeline] = []

    func append(_ stage: KeyEventPipeline) {
        stages.append(stage)
    }

    func process(_ keyEvent: KeyboardEvent) -> KeyboardEvent? {
        var current: KeyboardEvent? = keyEvent
        for stage in stages {
            guard let event = current else { return nil }
            current = stage.process(event)
        }
        return current
    }
}
