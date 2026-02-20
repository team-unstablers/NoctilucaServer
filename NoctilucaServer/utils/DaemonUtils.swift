//
//  DaemonUtils.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 2/20/26.
//

import Foundation
import ServiceManagement

private let kDaemonPlistName = "pl.unstabler.noctiluca.server.noctilucad.plist"

struct DaemonUtils {
    private static var daemonService: SMAppService {
        SMAppService.daemon(plistName: kDaemonPlistName)
    }

    /// 데몬의 현재 등록 상태를 반환합니다.
    static var status: SMAppService.Status {
        daemonService.status
    }

    /// 데몬이 등록되어 실행 가능한 상태인지 확인합니다.
    static func isDaemonInstalled() -> Bool {
        daemonService.status == .enabled
    }

    /// 데몬을 시스템에 등록합니다.
    ///
    /// 등록 시 사용자에게 시스템 설정에서 승인을 요구하는 알림이 표시될 수 있습니다.
    /// 이미 등록된 상태에서 다시 호출하면 에러 없이 반환됩니다.
    static func installDaemon() throws {
        try daemonService.register()
    }

    /// 데몬 등록을 해제합니다.
    static func uninstallDaemon() async throws {
        try await daemonService.unregister()
    }

    /// 사용자가 데몬을 승인할 수 있도록 시스템 설정의 로그인 항목 패널을 엽니다.
    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
