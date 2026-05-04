//
//  NocFSAccessHostXPCExport.swift
//  NoctilucaServer
//
//  ``NocFSAccessHostProtocol`` 의 NSObject 구현체. 데몬이 NFS callback 처리 중
//  reverse-XPC 로 호출하면 본 객체가 받아서 ``FSAccessRequestRouter`` 를 거쳐
//  적절한 ``FSAccessMountChannel`` 로 forward 한다.
//
//  Stage D 의 본 stub 은 모든 메서드를 ``ESTALE`` (mount session not found) 로
//  reply 한다. 실제 dispatch / Sirius msgdef 변환 로직은 Stage F 에서 채워진다.
//

import Foundation

import SiriusKit

import NocFSAccessXPC

@objc final class NocFSAccessHostXPCExport: NSObject, NocFSAccessHostProtocol {
    private let logger = NoctilucaLogger(category: "NocFSAccessHostXPCExport")

    override init() {
        super.init()
    }

    // MARK: - NocFSAccessHostProtocol (Stage D stub — Stage F 가 채움)

    func lookup(mountSessionId: String,
                parentHandleId: UInt64,
                name: String,
                reply: @escaping (UInt64, NocFSFileStat?, Error?) -> Void) {
        logger.warning("lookup stub: session=\(mountSessionId) parent=\(parentHandleId) name=\(name) — replying ESTALE")
        reply(0, nil, NSError.nocFSPosix(ESTALE))
    }

    func lookupParent(mountSessionId: String,
                      handleId: UInt64,
                      reply: @escaping (UInt64, NocFSFileStat?, Error?) -> Void) {
        logger.warning("lookupParent stub: session=\(mountSessionId) handle=\(handleId)")
        reply(0, nil, NSError.nocFSPosix(ESTALE))
    }

    func getattr(mountSessionId: String,
                 handleId: UInt64,
                 reply: @escaping (NocFSFileStat?, Error?) -> Void) {
        logger.warning("getattr stub: session=\(mountSessionId) handle=\(handleId)")
        reply(nil, NSError.nocFSPosix(ESTALE))
    }

    func setattr(mountSessionId: String,
                 handleId: UInt64,
                 patch: NocFSAttributesPatch,
                 reply: @escaping (NocFSFileStat?, Error?) -> Void) {
        _ = patch
        logger.warning("setattr stub: session=\(mountSessionId) handle=\(handleId)")
        reply(nil, NSError.nocFSPosix(ESTALE))
    }

    func access(mountSessionId: String,
                handleId: UInt64,
                mask: UInt32,
                reply: @escaping (UInt32, Error?) -> Void) {
        logger.warning("access stub: session=\(mountSessionId) handle=\(handleId) mask=\(mask)")
        reply(0, NSError.nocFSPosix(ESTALE))
    }

    func readdir(mountSessionId: String,
                 handleId: UInt64,
                 cookie: UInt64,
                 cookieVerifier: UInt64,
                 maxEntries: Int,
                 reply: @escaping ([NocFSDirEntry]?, Bool, UInt64, UInt64, Error?) -> Void) {
        _ = (cookie, cookieVerifier, maxEntries)
        logger.warning("readdir stub: session=\(mountSessionId) handle=\(handleId)")
        reply(nil, true, 0, 0, NSError.nocFSPosix(ESTALE))
    }

    func readlink(mountSessionId: String,
                  handleId: UInt64,
                  reply: @escaping (String?, Error?) -> Void) {
        logger.warning("readlink stub: session=\(mountSessionId) handle=\(handleId)")
        reply(nil, NSError.nocFSPosix(ESTALE))
    }

    func open(mountSessionId: String,
              parentHandleId: UInt64,
              name: String,
              shareAccess: UInt32,
              shareDeny: UInt32,
              createMode: UInt32,
              reply: @escaping (UInt64, NocFSFileStat?, Error?) -> Void) {
        _ = (shareAccess, shareDeny, createMode)
        logger.warning("open stub: session=\(mountSessionId) parent=\(parentHandleId) name=\(name)")
        reply(0, nil, NSError.nocFSPosix(ESTALE))
    }

    func close(mountSessionId: String,
               handleId: UInt64,
               reply: @escaping (Error?) -> Void) {
        logger.warning("close stub: session=\(mountSessionId) handle=\(handleId)")
        reply(NSError.nocFSPosix(ESTALE))
    }

    func read(mountSessionId: String,
              handleId: UInt64,
              offset: UInt64,
              length: UInt32,
              reply: @escaping (Data?, Bool, Error?) -> Void) {
        _ = (offset, length)
        logger.warning("read stub: session=\(mountSessionId) handle=\(handleId)")
        reply(nil, true, NSError.nocFSPosix(ESTALE))
    }

    func write(mountSessionId: String,
               handleId: UInt64,
               offset: UInt64,
               data: Data,
               stability: UInt32,
               reply: @escaping (UInt32, Error?) -> Void) {
        _ = (offset, data, stability)
        logger.warning("write stub: session=\(mountSessionId) handle=\(handleId)")
        reply(0, NSError.nocFSPosix(ESTALE))
    }

    func commit(mountSessionId: String,
                handleId: UInt64,
                offset: UInt64,
                length: UInt32,
                reply: @escaping (Error?) -> Void) {
        _ = (offset, length)
        logger.warning("commit stub: session=\(mountSessionId) handle=\(handleId)")
        reply(NSError.nocFSPosix(ESTALE))
    }

    func create(mountSessionId: String,
                parentHandleId: UInt64,
                name: String,
                type: UInt32,
                attrs: NocFSAttributesInit,
                reply: @escaping (UInt64, NocFSFileStat?, Error?) -> Void) {
        _ = (type, attrs)
        logger.warning("create stub: session=\(mountSessionId) parent=\(parentHandleId) name=\(name)")
        reply(0, nil, NSError.nocFSPosix(ESTALE))
    }

    func remove(mountSessionId: String,
                parentHandleId: UInt64,
                name: String,
                reply: @escaping (Error?) -> Void) {
        logger.warning("remove stub: session=\(mountSessionId) parent=\(parentHandleId) name=\(name)")
        reply(NSError.nocFSPosix(ESTALE))
    }

    func rename(mountSessionId: String,
                srcParentHandleId: UInt64,
                srcName: String,
                dstParentHandleId: UInt64,
                dstName: String,
                reply: @escaping (Error?) -> Void) {
        _ = (srcParentHandleId, srcName, dstParentHandleId, dstName)
        logger.warning("rename stub: session=\(mountSessionId)")
        reply(NSError.nocFSPosix(ESTALE))
    }

    func link(mountSessionId: String,
              targetHandleId: UInt64,
              parentHandleId: UInt64,
              name: String,
              reply: @escaping (Error?) -> Void) {
        _ = (targetHandleId, parentHandleId, name)
        logger.warning("link stub: session=\(mountSessionId)")
        reply(NSError.nocFSPosix(ESTALE))
    }
}
