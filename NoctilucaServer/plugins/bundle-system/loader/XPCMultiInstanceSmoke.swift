//
//  XPCMultiInstanceSmoke.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 5/18/26.
//
//  NoctilucaPluginKitHost.xpc 의 `_MultipleInstances=YES` 동작을 검증하는
//  진단 helper. 같은 mach service name 으로 connection 두 개를 띄우고
//  각각의 ping 응답 (host pid 포함) 을 server log 에 출력한다.
//
//  서로 다른 pid 가 보이면 launchd 가 connection 마다 새 host process
//  instance 를 spawn 하는 것이 확인된 것이다. 같은 pid 가 두 번 보이면
//  multi-instance 설정이 잘못된 상태.
//
//  활성화: 환경변수 `NOC_PLUGIN_HOST_SMOKE=1`. T7 검증이 끝나면 본 파일과
//  call site 를 함께 제거할 것.
//

import Foundation
import NoctilucaPluginKitHostCore
import Shotoku
import SiriusKit

enum XPCMultiInstanceSmoke {

    /// 환경변수 가드를 통해 진단을 실행한다.
    /// `NOC_PLUGIN_HOST_SMOKE` 가 "1" 또는 "yes" / "true" 일 때만 동작.
    static func runIfEnabled() async {
        let envValue = ProcessInfo.processInfo.environment["NOC_PLUGIN_HOST_SMOKE"]?.lowercased()
        guard envValue == "1" || envValue == "yes" || envValue == "true" else {
            return
        }
        await run()
    }

    static func run() async {
        let logger = NoctilucaLogger(category: "XPCMultiInstanceSmoke")
        let machServiceName = "app.noctiluca.server.NoctilucaPluginKitHost"

        logger.info("=== Plugin host multi-instance smoke test (start) ===")

        let client1 = RPCClient<HostControlInterface>(endpoint: .xpc(machServiceName))
        let client2 = RPCClient<HostControlInterface>(endpoint: .xpc(machServiceName))

        defer {
            Task {
                await client1.disconnect()
                await client2.disconnect()
            }
        }

        do {
            try await client1.connect()
            try await client2.connect()
        } catch {
            logger.error("smoke: failed to connect: \(error)")
            return
        }

        let pong1: String
        let pong2: String
        do {
            let proxy1 = try await client1.proxy(HostControlInterface.Proxy.self)
            let proxy2 = try await client2.proxy(HostControlInterface.Proxy.self)
            pong1 = try await proxy1.ping()
            pong2 = try await proxy2.ping()
        } catch {
            logger.error("smoke: ping failed: \(error)")
            return
        }

        logger.info("smoke: connection #1 → \(pong1)")
        logger.info("smoke: connection #2 → \(pong2)")

        if pong1 == pong2 {
            logger.error(
                "smoke: VERDICT = FAIL — two connections returned the same pong message,"
                + " which means launchd routed both to the same host instance."
                + " Check NoctilucaPluginKitHost/Info.plist XPCService._MultipleInstances."
            )
        } else {
            logger.info(
                "smoke: VERDICT = PASS — distinct pong messages observed,"
                + " host process is spawned per-connection."
            )
        }

        logger.info("=== Plugin host multi-instance smoke test (end) ===")
    }
}
