//
//  main.swift
//  nocfsaccessd
//
//  fsaccess <-> NFS bridge daemon. 호스트 앱 (NoctilucaServer) 만이 이 데몬을
//  spawn 한다. 단독 실행은 의도적으로 막혀 있으며, 환경변수 ``NOC_FSACCESSD_XPC_ENDPOINT``
//  가 비어있으면 즉시 ``EX_USAGE`` 로 abort 한다.
//
//  See: docs/nocfsaccessd.md
//

import Foundation
import OSLog

import NocFSAccessXPC

private let endpointEnvKey = "NOC_FSACCESSD_XPC_ENDPOINT"

// MARK: - 환경변수 디코드

guard let endpointBase64 = ProcessInfo.processInfo.environment[endpointEnvKey],
      !endpointBase64.isEmpty else {
    DaemonLogger.lifecycle.fault("\(endpointEnvKey, privacy: .public) is not set; refusing to run standalone.")
    exit(EX_USAGE)
}

guard let endpointData = Data(base64Encoded: endpointBase64) else {
    DaemonLogger.lifecycle.fault("\(endpointEnvKey, privacy: .public) was not valid base64.")
    exit(EX_USAGE)
}

let endpoint: NSXPCListenerEndpoint
do {
    let unarchiver = try NSKeyedUnarchiver(forReadingFrom: endpointData)
    unarchiver.requiresSecureCoding = true
    guard let decoded = unarchiver.decodeObject(of: NSXPCListenerEndpoint.self, forKey: "endpoint") else {
        DaemonLogger.lifecycle.fault("Failed to decode NSXPCListenerEndpoint from \(endpointEnvKey, privacy: .public).")
        exit(EX_USAGE)
    }
    endpoint = decoded
} catch {
    DaemonLogger.lifecycle.fault("NSKeyedUnarchiver init failed: \(error.localizedDescription, privacy: .public)")
    exit(EX_USAGE)
}

// MARK: - actor / state 생성

let virtualTree = VirtualTree()
let handleTable = HandleTable()
let daemonImpl = NocFSAccessDaemonImpl(virtualTree: virtualTree, handleTable: handleTable)

// MARK: - reverse-XPC connect

let connection = NSXPCConnection(listenerEndpoint: endpoint)

// 호스트 앱이 우리에게 호출하는 인터페이스 (host → daemon).
connection.exportedInterface = NocFSAccessXPCInterfaces.makeDaemonInterface()
connection.exportedObject = daemonImpl

// 우리가 호스트에 호출하는 인터페이스 (daemon → host).
connection.remoteObjectInterface = NocFSAccessXPCInterfaces.makeHostInterface()

connection.invalidationHandler = {
    DaemonLogger.xpc.fault("XPC connection invalidated — exiting daemon (EX_UNAVAILABLE).")
    exit(EX_UNAVAILABLE)
}
connection.interruptionHandler = {
    DaemonLogger.xpc.error("XPC connection interrupted — daemon will exit if not restored.")
}

connection.resume()

DaemonLogger.lifecycle.info("nocfsaccessd: reverse-connected to host. Awaiting daemonReady().")

// MARK: - run loop

dispatchMain()
