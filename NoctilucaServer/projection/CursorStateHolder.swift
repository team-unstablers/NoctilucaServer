//
//  CursorStateHolder.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 1/19/26.
//

import Foundation

import AppKit

import SiriusKit

struct CursorState: Hashable, Equatable {
    let absolutePosition: CGPoint
    let relativePosition: CGPoint
    let belongsTo: CGDirectDisplayID
}

@MainActor
class CursorStateHolder {
    static let shared = CursorStateHolder()

    let logger = NoctilucaLogger(category: "CursorStateHolder")

    // 직접 접근용 프로퍼티
    private(set) var cursorHash: Int = 0
    private(set) var cursorImage: NSImage? = nil
    private(set) var cursorHotspot: NSPoint? = nil
    private(set) var cursorState: CursorState? = nil

    // 멀티캐스트를 위한 Continuation 목록
    private var stateContinuations: [UUID: AsyncStream<CursorState>.Continuation] = [:]
    private var hashContinuations: [UUID: AsyncStream<Int>.Continuation] = [:]

    private var observerToken: Any? = nil

    init() {
        do {
            try CoreGraphicsPrivate.open()
        } catch {
            logger.error("failed to load CoreGraphics library")
        }

        self.startObserveCursorEvent()
        self.updateCursorPosition()
        self.updateCursorHash()
    }
    
    @MainActor
    deinit {
        self.stopObserveCursorEvent()
        
        for continuation in stateContinuations.values {
            continuation.finish()
        }
        for continuation in hashContinuations.values {
            continuation.finish()
        }
    }
    
    /// 새로운 CursorState 스트림을 생성합니다. (Multicast 지원)
    func makeCursorStateStream() -> AsyncStream<CursorState> {
        return AsyncStream(CursorState.self, bufferingPolicy: .bufferingNewest(1)) { continuation in
            let id = UUID()
            self.stateContinuations[id] = continuation
            
            // 초기값 전송
            if let currentState = self.cursorState {
                continuation.yield(currentState)
            }
            
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.stateContinuations.removeValue(forKey: id)
                }
            }
        }
    }
    
    /// 새로운 CursorHash 스트림을 생성합니다. (Multicast 지원)
    func makeCursorHashStream() -> AsyncStream<Int> {
        return AsyncStream(Int.self, bufferingPolicy: .unbounded) { continuation in
            let id = UUID()
            self.hashContinuations[id] = continuation
            
            // 초기값 전송
            if self.cursorHash != 0 {
                continuation.yield(self.cursorHash)
            }
            
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.hashContinuations.removeValue(forKey: id)
                }
            }
        }
    }
    
    private func startObserveCursorEvent() {
        self.stopObserveCursorEvent()
        
        self.observerToken = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .cursorUpdate, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { event in
            self.updateCursorPosition()
            self.updateCursorHash()
        }
    }
    
    private func stopObserveCursorEvent() {
        guard let observerToken else {
            return
        }
        
        NSEvent.removeMonitor(observerToken)
    }
    
    func updateCursorPosition() {
        let position = NSEvent.mouseLocation as CGPoint
        let state = CursorState.fromNSEvent(position)

        if self.cursorState != state {
            self.cursorState = state
            for continuation in stateContinuations.values {
                continuation.yield(state)
            }
        }
    }
    
    func updateCursorHash() {
        guard let cursorHash = CoreGraphicsPrivate.CGSCurrentCursorSeed?() else {
            return
        }

        if cursorHash != self.cursorHash {
            self.cursorHash = cursorHash
            self.cursorImage = NSCursor.currentSystem?.image
            self.cursorHotspot = NSCursor.currentSystem?.hotSpot
            
            for continuation in hashContinuations.values {
                continuation.yield(cursorHash)
            }
        }
    }
}

extension CursorState {
    /// Cocoa Global 좌표계를 X11(Global Top-Left) 좌표계로 변환합니다.
    /// - Cocoa Global: 메인 디스플레이 좌측 하단이 (0, 0), y는 위로 증가
    /// - X11 Global: 전체 뷰포트 좌측 상단이 (0, 0), y는 아래로 증가
    static func toX11GlobalCoordinate(_ point: CGPoint, intermediateGlobalFrame: CGRect) -> CGPoint {
        CGPoint(
            x: point.x - intermediateGlobalFrame.minX,
            y: intermediateGlobalFrame.maxY - point.y
        )
    }

    /// X11(Global Top-Left) 좌표계를 CoreGraphics 좌표계로 변환합니다.
    /// - X11 Global: 전체 뷰포트 좌측 상단이 (0, 0), y는 아래로 증가
    /// - CoreGraphics: 메인 디스플레이 좌측 상단이 (0, 0), y는 아래로 증가
    static func toCoreGraphicsCoordinate(_ point: CGPoint, mainScreen: NOCScreen) -> CGPoint {
        CGPoint(
            x: point.x - mainScreen.frame.minX,
            y: point.y - mainScreen.frame.minY
        )
    }
    
    /// CoreGraphics 좌표계를 X11(Global Top-Left) 좌표계로 변환합니다.
    /// - CoreGraphics: 메인 디스플레이 좌측 상단이 (0, 0), y는 아래로 증가
    /// - X11 Global: 전체 뷰포트 좌측 상단이 (0, 0), y는 아래로 증가
    static func toX11Coordinate(_ point: CGPoint, mainScreen: NOCScreen) -> CGPoint {
        CGPoint(
            x: point.x + mainScreen.frame.minX,
            y: point.y + mainScreen.frame.minY
        )
    }
    
    static func clampToNearestScreen(_ point: CGPoint, layouts: [CGDirectDisplayID: NOCScreen]) -> CGPoint {
        for screen in layouts.values {
            if screen.frame.contains(point) {
                return clamp(point: point, to: screen.frame)
            }
        }
        
        var nearestScreen: NOCScreen?
        var minDistance = CGFloat.greatestFiniteMagnitude
        
        for screen in layouts.values {
            let distance = distanceToRect(point: point, rect: screen.frame)
            if distance < minDistance {
                minDistance = distance
                nearestScreen = screen
            }
        }
        
        guard let screen = nearestScreen else {
            return point
        }
        
        return clamp(point: point, to: screen.frame)
    }
    
    private static func clamp(point: CGPoint, to rect: CGRect) -> CGPoint {
        // user requirement: max x/y coordinates should be width - 0.1 / height - 0.1
        let minX = rect.minX
        let minY = rect.minY
        let maxX = rect.maxX - 0.1
        let maxY = rect.maxY - 0.1
        
        let x = max(minX, min(point.x, maxX))
        let y = max(minY, min(point.y, maxY))
        
        return CGPoint(x: x, y: y)
    }
    
    private static func distanceToRect(point: CGPoint, rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return sqrt(dx*dx + dy*dy)
    }
    
    static func fromNSEvent(
        _ position: CGPoint,
        layouts: [CGDirectDisplayID: NOCScreen],
        intermediateGlobalFrame: CGRect
    ) -> CursorState {
        /// GUI 세션의 전체 뷰포트의 좌상단을 (0, 0)으로 하는 절대 좌표계 (X11-like)
        let cgAbsolutePosition = toX11GlobalCoordinate(position, intermediateGlobalFrame: intermediateGlobalFrame)
        
        // 클램프 처리
        let clampedCGAbsolutePosition = clampToNearestScreen(cgAbsolutePosition, layouts: layouts)
        
        let relatedDisplayID = layouts.first { (_, screen) in
            screen.frame.contains(clampedCGAbsolutePosition)
        }?.key ?? CGMainDisplayID()
        
        let relatedDisplayFrame = layouts[relatedDisplayID]?.frame
        ?? CGRect(origin: .zero, size: intermediateGlobalFrame.size)
        
        /// relatedDisplay의 좌상단을 기준으로 둔 좌표계
        let displayRelativePosition = CGPoint(
            x: clampedCGAbsolutePosition.x - relatedDisplayFrame.minX,
            y: clampedCGAbsolutePosition.y - relatedDisplayFrame.minY
        )
        
        return CursorState(
            absolutePosition: clampedCGAbsolutePosition,
            relativePosition: displayRelativePosition,
            belongsTo: relatedDisplayID
        )
    }
    
    static func fromNSEvent(_ position: CGPoint) -> CursorState {
        let displayLayoutManager = DisplayLayoutManager.shared
        let layouts = displayLayoutManager.displayLayouts.snapshot()
        let intermediateGlobalFrame = displayLayoutManager.intermediateGlobalFrame
        let resolvedIntermediateFrame = (intermediateGlobalFrame.isNull || intermediateGlobalFrame.isEmpty)
            ? NOCScreen.produceIntermediateGlobalFrame(from: NSScreen.screens)
            : intermediateGlobalFrame
        
        return fromNSEvent(
            position,
            layouts: layouts,
            intermediateGlobalFrame: resolvedIntermediateFrame
        )
    }
}
