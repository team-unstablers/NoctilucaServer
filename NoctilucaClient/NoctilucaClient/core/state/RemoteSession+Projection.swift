//
//  RemoteSession+Projection.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/1/26.
//

import Foundation
import Atomics

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
    
    /// 이 티켓은 다른 곳으로 복사할 수 없습니다
    class SessionReferenceTicket {
        let id: UUID
        let releaseAction: () -> Void
        
        fileprivate init(id: UUID, releaseAction: @escaping () -> Void) {
            self.id = id
            self.releaseAction = releaseAction
        }
        
        deinit {
            releaseAction()
        }
    }
    
    class Projection: ObservableObject {
        private let logger = NoctilucaLogger(category: "RemoteSession.Projection")
        
        private weak var parent: RemoteSession?
        private(set) var channel: ProjectionChannel
        
        let channelID: UUID
        
        private var eventSubscription: AnyCancellable? = nil

        @Published
        private(set) var projectionSessions: [UUID: ProjectionSession] = [:]
        private(set) var projectionSessionReferences: [UUID: ManagedAtomic<Int>] = [:]
        
        @Published
        private(set) var audioSessions: [UUID: AudioProjectionSession] = [:]

        /// 현재 활성화된 DegradationNotice. nil이면 notice를 받지 않았거나 회복된 상태.
        @Published
        private(set) var degradationNotice: DegradationNotice? = nil

        private var sessionEventSubscriptions: [UUID: AnyCancellable] = [:]

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
            sessionEventSubscriptions.values.forEach { $0.cancel() }
            sessionEventSubscriptions.removeAll()
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
                self.subscribeSessionEvents(session)
            case .sessionDestroyed(let sessionID, let reason):
                self.projectionSessions.removeValue(forKey: sessionID)
                self.unsubscribeSessionEvents(sessionID)
                if projectionSessions.isEmpty {
                    self.degradationNotice = nil
                }

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

        private func subscribeSessionEvents(_ session: ProjectionSession) {
            let sessionID = session.dataChannel.identifier

            let subscription = session.events
                .receive(on: RunLoop.main)
                .sink { [weak self] event in
                    self?.handleSessionEvent(event)
                }

            sessionEventSubscriptions[sessionID] = subscription
        }

        private func unsubscribeSessionEvents(_ sessionID: UUID) {
            sessionEventSubscriptions[sessionID]?.cancel()
            sessionEventSubscriptions.removeValue(forKey: sessionID)
        }

        private func handleSessionEvent(_ event: ProjectionSessionEvent) {
            switch event {
            case .degradationNoticeReceived(let notice):
                if notice.reason.rawValue == 0 && notice.type.rawValue == 0 && notice.additionalInfo.rawValue == 0 {
                    self.degradationNotice = nil
                } else {
                    self.degradationNotice = notice
                }
            default:
                break
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
        
        /// 프로젝션 세션을 '구독'합니다.
        ///
        /// # ABOUT 'REFERENCE TICKET'
        ///
        /// - 이 function을 호출하면, '레퍼런스 티켓'을 발급받습니다.
        /// - 레퍼런스 티켓은 '프로젝션 세션'으로의 레퍼런스입니다.
        /// - 각 프로젝션 세션은 자신을 레퍼런싱하는 '레퍼런스 티켓'이 사라지면 자동으로 종료됩니다.
        ///
        // TODO: 디스플레이마다 해상도 다른데 어떻게 할려고?
        // 디스플레이가 2대 이상이면 하드웨어 인코더가 터질텐데 어떻게 할려고???
        @MainActor
        func subscribeProjectionSession(for displayID: Int) async throws -> ProjectionSessionSubscription {
            if let sessionKey = projectionSessions.first(where: { $0.value.displayID == displayID })?.key {
                // 이미 해당 디스플레이에 대한 프로젝션 세션이 존재함
                logger.info("Projection session for displayID \(displayID) already exists.")
                guard let referenceCounter = projectionSessionReferences[sessionKey] else {
                    // ASSERTION: 레퍼런스 카운터는 반드시 존재해야만 한다
                    fatalError("ASSERTION FAILED: reference counter for existing projection session is missing.")
                }

                guard let session = projectionSessions[sessionKey] else {
                    fatalError("ASSERTION FAILED: projection session for key \(sessionKey) is missing.")
                }

                // += 1
                referenceCounter.wrappingIncrement(ordering: .relaxed)

                let ticket = SessionReferenceTicket(id: UUID()) {
                    referenceCounter.wrappingDecrement(ordering: .relaxed)

                    Task {
                        await self.handleSessionReferenceDecrement(for: sessionKey)
                    }
                }

                return ProjectionSessionSubscription(session: session, ticket: ticket)
            }

            guard let session = try await parent?.client.projectionChannel.createSession(
                for: displayID,
                projectionSettings: parent?.client.sessionSettings?.projection
            ) else {
                // TODO: throw error
                fatalError("Failed to create projection session for displayID \(displayID).")
            }

            let sessionID = session.id

            // 레퍼런스 카운터 초기화
            let referenceCounter = ManagedAtomic<Int>(1)
            projectionSessionReferences[sessionID] = referenceCounter

            let ticket = SessionReferenceTicket(id: UUID()) {
                referenceCounter.wrappingDecrement(ordering: .relaxed)

                Task {
                    await self.handleSessionReferenceDecrement(for: sessionID)
                }
            }

            return ProjectionSessionSubscription(session: session, ticket: ticket)
        }
        
        func startAudioProjection() async throws {
            // TODO: 마이크 세션같은게 있을 수도 있기 때문에
            guard audioSessions.values.isEmpty else {
                // 이미 오디오 프로젝션 세션이 존재함
                logger.info("Audio projection session already exists.")
                return
            }
            
            _ = try await parent?.client.projectionChannel.createAudioSession(for: .sessionAudio, projectionSettings: parent?.client.sessionSettings?.projection)
        }
        
    }
}

fileprivate extension RemoteSession.Projection {
    @MainActor
    func handleSessionReferenceDecrement(for sessionID: UUID) async {
        guard let referenceCounter = projectionSessionReferences[sessionID] else {
            return
        }
        
        let count = referenceCounter.load(ordering: .relaxed)
        
        if count == 0 {
            // 레퍼런스 카운터가 0이 되었으므로 세션 종료
            logger.info("Reference count for projection session \(sessionID) reached zero. Stopping session.")
            
            if let session = projectionSessions.removeValue(forKey: sessionID) {
                do {
                    try await session.stop()
                } catch {
                    logger.error("Failed to stop projection session \(sessionID): \(error)")
                }
            }
            
            // 레퍼런스 카운터 제거
            projectionSessionReferences.removeValue(forKey: sessionID)
        }
    }
}
