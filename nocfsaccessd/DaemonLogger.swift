//
//  DaemonLogger.swift
//  nocfsaccessd
//
//  os.Logger wrapper. 데몬은 SiriusKit 의 SiriusLogger 인프라를 의존하지 않는다
//  (의존이 NocFSAccessXPC + NanoNFS 로 한정). 호스트 앱은 별도 subsystem 을
//  쓰며, 두 프로세스 로그를 함께 보려면 `subsystem BEGINSWITH
//  "pl.unstabler.noctiluca"` predicate 를 사용한다.
//

import Foundation
import OSLog

enum DaemonLogger {
    static let subsystem = "pl.unstabler.noctiluca.fsaccessd"

    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    static let xpc = Logger(subsystem: subsystem, category: "xpc")
    static let nfs = Logger(subsystem: subsystem, category: "nfs")
    static let mount = Logger(subsystem: subsystem, category: "mount")
    static let vtree = Logger(subsystem: subsystem, category: "vtree")
}
