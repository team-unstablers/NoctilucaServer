//
//  main.swift
//  noctilucad
//
//  Created by Gyuhwan Park on 2/20/26.
//

import Foundation
import ArgumentParser

import SiriusKit

// FIXME: @cheesekun - PEM 파일 경로
let kDefaultCertPath = "/Library/Application Support/noctilucad/server.cert.pem"
let kDefaultKeyPath = "/Library/Application Support/noctilucad/server.key.pem"

/// noctilucad: Noctiluca 시스템 데몬
///
/// - QUIC 연결을 수락하고 MainChannel 핸드셰이크/인증을 처리한다.
/// - 인증 완료 후 UID 기반으로 적절한 NoctilucaServer(Agent)에 XPC 프록시 연결을 수립한다.
/// - 각 NoctilucaServer는 가동 시 announce, 종료 시 depart한다.

let logger = SiriusLogger(category: "noctilucad")

// MARK: - Agent Registry & XPC Service

@available(macOS 10.15, *)
struct NoctilucaDaemonCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "noctilucad",
        abstract: "Noctiluca system daemon"
    )

    @Option(name: .long, help: "데몬의 실행 스코프. (미지정 시 auto determine을 수행한다)")
    var scope: DaemonScope = .determine()

    @Option(name: .long, help: "데몬의 설정 파일 위치. (미지정 시 적절한 위치를 자동으로 결정한다)")
    var settingsFile: String? = nil

    mutating func run() throws {
        let daemon = NoctilucaDaemon(scope: scope)
        _ = MsQuicLoader.shared.success

        Task {
            await daemon.prepare()
            
            do {
                try await daemon.start()
            } catch {
                logger.error("Failed to start daemon: \(error)")
                throw error
            }
            
            logger.info("noctilucad is running. Waiting for connections...")
        }
        
        RunLoop.main.run()
    }
}

NoctilucaDaemonCLI.main()
