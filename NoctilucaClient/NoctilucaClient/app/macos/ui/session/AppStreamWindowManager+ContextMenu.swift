//
//  AppStreamWindowManager+ContextMenu.swift
//  NoctilucaClient
//

#if os(macOS)

import Foundation
import AppKit
import CoreGraphics

import SiriusKitClient

extension AppStreamWindowManager {

    /// 호스트에서 popup(컨텍스트) 메뉴가 열렸음을 알리는 트리(`metadata.popup == "true"` 인
    /// AccessibilityTreeUpdateEvent .nodeAdded 의 updatedNode)를 처리한다.
    /// AccessibilityTreeBuilder 가 직렬화한 트리를 native NSMenu 로 재구성한 뒤,
    /// `triggerWindowId` 에 해당하는 AppStreamWindow 위에 호스트 popup 좌표 그대로 띄운다.
    @MainActor
    func handlePopupOpened(tree: AccessibilityNode) {
        guard let builder = self.menuBuilder else {
            logger.warning("Context menu opened but no AppStreamMenuBuilder; ignoring")
            return
        }

        let triggerWindowId: UInt32?
        if let raw = tree.metadata["app.noctiluca.server.popup.triggerWindowId"], let parsed = UInt32(raw) {
            triggerWindowId = parsed
        } else {
            triggerWindowId = nil
        }

        let target = resolveContextMenuTargetWindow(triggerWindowId: triggerWindowId)
        guard let target else {
            logger.warning("Context menu opened but no target AppStreamWindow")
            return
        }

        let menu = builder.buildMenu(from: tree)

        // 서버 AccessibilityTreeBuilder.readBounds 는 kAXPositionAttribute 기반이라 host 글로벌
        // (top-left origin) 좌표가 그대로 들어온다.
        let hostBounds = CGRect(
            x: tree.bounds.x,
            y: tree.bounds.y,
            width: tree.bounds.width,
            height: tree.bounds.height
        )

        // 호스트 글로벌(top-left) → 클라 NSScreen Cocoa 좌표
        /*
        guard let clientOrigin = translateServerFrameToClientOrigin(serverBounds: hostBounds) else {
            logger.warning("Context menu coord translation failed for bounds \(hostBounds.debugDescription)")
            return
        }

        let screenPoint = NSPoint(x: clientOrigin.x, y: clientOrigin.y)
         */
        let menuId = tree.id

        // popUp 은 메뉴 트래킹 동안 main run loop 를 modal 로 block 하지만, ProjectionChannel
        // 의 receive Task 는 별도 컨텍스트라 .nodeRemoved 가 도착하면 cancelTracking 으로
        // 우리 NSMenu 도 닫을 수 있다.
        let point = NSEvent.mouseLocation as CGPoint
        target.showContextMenu(menu, atScreenPoint: point, menuId: menuId)

        // popUp 이 return 했다는 건 트래킹 종료. 종료 사유에 따라 .cancel 송신 여부를 결정한다.
        //
        // - 항목 선택으로 닫힌 경우: didActivateRemoteMenuItem 가 .activate 를 송신했고,
        //   호스트 앱은 selection 결과로 popup 을 자동 dismiss 한다. 여기서 .cancel 을 또 보내면
        //   .activate 와 race 하면서 호스트 element 가 detach 된 후 .activate 가 도착해
        //   AXErrorInvalidUIElement (-25202) 를 만든다 (Firefox 처럼 popup item 이 dismiss 즉시
        //   invalidate 되는 앱에서 특히 자주 발생).
        // - ESC / 외부 클릭 등 selection 없이 닫힌 경우: 호스트 popup 이 아직 떠 있을 수 있으므로
        //   .cancel 로 명시 dismiss 한다 (이미 닫혀 있으면 success=false 나 element 미존재 에러가
        //   돌아오지만 noise 수준).
        if builder.consumeSelectionFlag() {
            return
        }

        Task { [weak self] in
            guard let self else { return }
            guard let projectionChannel = self.remoteSession.projection?.channel else { return }
            _ = try? await projectionChannel.dispatchAction(
                targetNodeId: menuId,
                actionType: .cancel,
                value: nil,
                args: [:]
            )
        }
    }

    /// 호스트가 popup 을 닫았다는 알림(.nodeRemoved). 매칭되는 NSMenu 를 cancelTracking 한다.
    /// menuId 가 어느 윈도우의 활성 popup 도 아니면 silently 무시한다 (정상적인 race).
    @MainActor
    func handlePopupClosed(menuId: UUID) {
        for state in windows.values {
            state.window.cancelContextMenu(matching: menuId)
        }
    }

    /// triggerWindowId → AppStreamWindow 매핑. 일치 항목이 없으면 현재 key 인 AppStreamWindow,
    /// 그것도 없으면 임의의 첫 번째 항목으로 폴백한다 (1차 ship 기준; 추후 정밀화 여지).
    @MainActor
    private func resolveContextMenuTargetWindow(triggerWindowId: UInt32?) -> AppStreamWindow? {
        if let triggerWindowId, let state = windows[UInt64(triggerWindowId)] {
            return state.window
        }
        if let keyState = windows.values.first(where: { $0.window.isKeyWindow }) {
            return keyState.window
        }
        return windows.values.first?.window
    }
}

#endif
