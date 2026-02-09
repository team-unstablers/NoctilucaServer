//
//  ProjectionChannel+displayman.swift
//  NoctilucaClient
//
//  Created by Codex on 1/28/26.
//

import Foundation
import Combine
import SiriusKitClient

// MARK: - Displayman Request/Response

extension ProjectionChannel {
    
    /// DisplayListRequest를 전송하고 응답을 기다립니다.
    func requestDisplayList(flags: DisplayListRequestFlags = []) async throws -> DisplayListResponse {
        let requestID = nextRequestID()

        return try await self.sendRequest(
            requestID: requestID,
            opcode: .displayListRequest,
            message: DisplayListRequest(
                requestID: requestID,
                flags: flags.rawValue
            )
        )
    }
    
    func updateDisplayLayout() async throws {
        let response = try await requestDisplayList()
        
        for displayInfo in response.displays {
            await displayLayoutManager.update(displayInfo)
        }
    }

    /// 서버로부터 디스플레이 변경 이벤트를 구독합니다.
    func subscribeDisplayChanges(eventMask: DisplayChangeEventType = []) async throws -> SubscribeDisplayChangesResponse {
        let requestID = nextRequestID()
        
        let response: SubscribeDisplayChangesResponse = try await self.sendRequest(
            requestID: requestID,
            opcode: .subscribeDisplayChangesRequest,
            message: SubscribeDisplayChangesRequest(
                requestID: requestID,
                eventMask: eventMask,
                flags: 0
            )
        )
        
        self.displayChangesSubscriptionID = response.subscriptionID
        return response
    }

    /// 디스플레이 변경 이벤트 구독을 해제합니다.
    func unsubscribeDisplayChanges() async throws {
        guard let subscriptionID = self.displayChangesSubscriptionID else {
            return
        }

        let requestID = nextRequestID()

        try await self.send(opcode: .unsubscribeDisplayChangesRequest, message: UnsubscribeDisplayChangesRequest(
            requestID: requestID,
            subscriptionID: subscriptionID
        ))

        self.displayChangesSubscriptionID = nil
    }

    /// DisplayChangedEvent를 처리합니다. 디바운스 Subject로 전달합니다.
    func handleDisplayChangedEvent(_ event: DisplayChangedEvent) async throws {
        self.logger.info("Received DisplayChangedEvent: eventType=\(event.eventType.rawValue), displayID=\(event.display.displayID)")
        await displayLayoutManager.consumeDisplayChangeEvent(event)
    }
    
    
    /// 서버에서 디스플레이 목록을 조회하고 메인 디스플레이 ID를 반환합니다.
    func fetchPrimaryDisplayID() async throws -> Int32 {
        // FIXME: 매번 새로 받지 말고, 캐싱 좀 하세요
        let response = try await requestDisplayList()

        // 메인 디스플레이 찾기
        if let primaryDisplay = response.displays.first(where: { $0.state.isPrimary }) {
            self.logger.info("Found primary display: id=\(primaryDisplay.displayID), name=\(primaryDisplay.displayName)")
            return Int32(primaryDisplay.displayID)
        }

        // 메인 디스플레이가 없으면 첫 번째 연결된 디스플레이 사용
        if let firstDisplay = response.displays.first(where: { $0.state.isConnected }) {
            self.logger.warning("No primary display found, using first connected display: id=\(firstDisplay.displayID)")
            return Int32(firstDisplay.displayID)
        }

        // 아무 디스플레이도 없으면 -1 반환 (서버가 기본 처리)
        self.logger.warning("No displays found, using default display ID -1")
        return -1
    }
    

    // TODO: 이거는 다른 곳에서 처리할 예정
    private func handleDebouncedDisplayChange(_ event: DisplayChangedEvent) async {
        // 메인 디스플레이 관련 변경만 처리
        let shouldRestartProjection = event.eventType.contains(.becamePrimary)
            || (event.eventType.contains(.disconnected) && event.display.state.isPrimary)
            || (event.eventType.contains(.modified) && event.display.state.isPrimary)

        guard shouldRestartProjection else {
            self.logger.info("Display change event does not require projection restart")
            return
        }

        self.logger.info("Main display changed, restarting projection...")

        // 기존 세션 중지
        for (_, session) in self.sessions {
            do {
                try await session.stop()
            } catch {
                self.logger.error("Failed to stop existing projection session: \(error)")
            }
        }
        self.sessions.removeAll()

        // 새로운 디스플레이 정보 조회 및 프로젝션 재시작
        do {
            // let _ = try await self.createSession(projectionSettings: self.currentProjectionSettings)
        } catch {
            self.logger.error("Failed to restart projection session: \(error)")
        }
    }
}
