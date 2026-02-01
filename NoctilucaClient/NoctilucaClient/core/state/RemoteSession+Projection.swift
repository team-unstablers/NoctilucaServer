//
//  RemoteSession+Projection.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/1/26.
//

import Foundation
import Combine

import CoreGraphics

import SiriusKitClient

extension RemoteSession {
    typealias CursorHash = UInt64
    
    struct CursorImage: Identifiable {
        let id: CursorHash
        let image: CGImage
        let size: CGSize
        let hotspot: CGPoint
    }
    
    /// 커서 이미지를 캐싱합니다.
    fileprivate class CursorImageCacheManager {
        private(set) var cache: [CursorHash: CursorImage] = [:]
        
        @MainActor
        func updateCache(_ image: CursorImage) {
            self.cache[image.id] = image
        }
    }
    
    class CursorState: ObservableObject {
        @Published
        var image: CursorImage? = nil
        
        @Published
        var displayID: Int? = nil
        
        @Published
        var position: CGPoint = .zero
    }
    
    class Projection: ObservableObject {
        private weak var parent: RemoteSession?
        private var channel: ProjectionChannel
        
        let channelID: UUID
        
        private var eventSubscription: AnyCancellable? = nil

        @Published
        private(set) var projectionSessions: [UUID: ProjectionSession] = [:]
        
        @Published
        private(set) var audioSessions: [UUID: AudioProjectionSession] = [:]
        
        private let cursorImageCacheManager = CursorImageCacheManager()
        let cursorState = CursorState()
        
        init(_ parent: RemoteSession, channel: ProjectionChannel) {
            self.parent = parent
            self.channel = channel
            
            // cache the channel ID
            self.channelID = channel.identifier

            subscribeEvents()
        }

        deinit {
            unsubscribeEvents()
        }
        
        private func subscribeEvents() {
            self.eventSubscription = channel.events
                .receive(on: RunLoop.main)
                .sink { [weak self] event in
                    self?.handleEvent(event)
                }
        }
        
        
        private func unsubscribeEvents() {
            self.eventSubscription?.cancel()
            self.eventSubscription = nil
        }
        
        private func handleEvent(_ event: ProjectionChannelEvent) {
            switch event {
            case .sessionCreated(let session):
                self.projectionSessions.updateValue(session, forKey: session.dataChannel.identifier)
            case .sessionDestroyed(let sessionID, let reason):
                self.projectionSessions.removeValue(forKey: sessionID)
                
            case .audioSessionCreated(let audioSession):
                self.audioSessions.updateValue(audioSession, forKey: audioSession.dataChannel!.identifier)
            case .audioSessionDestroyed(let sessionID, let reason):
                self.audioSessions.removeValue(forKey: sessionID)
                
            case .cursorMoved(let moveEvent):
                self.handleCursorMoveEvent(moveEvent)
            case .cursorImageChanged(let imageEvent):
                Task { @MainActor in
                    self.handleCursorImageEvent(imageEvent)
                }
            }
        }
        
        private func handleCursorMoveEvent(_ moveEvent: CursorMoveEvent) {
            self.cursorState.displayID = Int(moveEvent.displayID)
            self.cursorState.position = moveEvent.position.cgPoint
        }
        
        @MainActor
        private func handleCursorImageEvent(_ imageEvent: CursorImageEvent) {
            let cursorHash = imageEvent.cursorType
            
            if let cursorImage = self.cursorImageCacheManager.cache[cursorHash] {
                // use cached image
                self.cursorState.image = cursorImage
                return
            }
            
            if let imageData = imageEvent.imageData,
               let dataProvider = CGDataProvider(data: imageData as CFData) {
                
                guard let image = CGImage(
                    pngDataProviderSource: dataProvider,
                    decode: nil,
                    shouldInterpolate: true,
                    intent: .defaultIntent
                ) else {
                    return
                }
                
                let cursorImage = CursorImage(
                    id: imageEvent.cursorType,
                    image: image,
                    size: imageEvent.size.cgSize,
                    hotspot: imageEvent.hotspot.cgPoint
                )
                
                // update cache
                self.cursorImageCacheManager.updateCache(cursorImage)
                
                // update state
                self.cursorState.image = cursorImage
            }
        }
    }
}
