import Foundation

/// Factory helpers that build ``NSXPCInterface`` instances for the two
/// nocfsaccessd protocols, with every NSSecureCoding-conformant DTO position
/// pre-registered via ``NSXPCInterface/setClasses(_:for:argumentIndex:ofReply:)``.
///
/// Both peers MUST call these — passing an interface without `setClasses` for
/// a payload position causes NSXPC to silently drop the value during decode
/// and reply with `nil`.
public enum NocFSAccessXPCInterfaces {

    // MARK: - Daemon interface (host calls daemon)

    public static func makeDaemonInterface() -> NSXPCInterface {
        let interface = NSXPCInterface(with: NocFSAccessDaemonProtocol.self)

        // host → daemon: addMountSession(descriptor:)  — input arg 0
        interface.setClasses(
            NSSet(array: [NocFSMountSessionDescriptor.self]) as! Set<AnyHashable>,
            for: NSSelectorFromString("addMountSessionWithDescriptor:reply:"),
            argumentIndex: 0,
            ofReply: false
        )

        return interface
    }

    // MARK: - Host interface (daemon calls host)

    public static func makeHostInterface() -> NSXPCInterface {
        let interface = NSXPCInterface(with: NocFSAccessHostProtocol.self)

        let statClasses = NSSet(array: [NocFSFileStat.self]) as! Set<AnyHashable>
        let dirEntryClasses = NSSet(array: [
            NSArray.self,
            NocFSDirEntry.self,
            NocFSFileStat.self,
        ]) as! Set<AnyHashable>
        let patchClasses = NSSet(array: [NocFSAttributesPatch.self]) as! Set<AnyHashable>
        let attrsInitClasses = NSSet(array: [NocFSAttributesInit.self]) as! Set<AnyHashable>

        // lookup → reply (newHandleId, NocFSFileStat?, Error?)
        interface.setClasses(
            statClasses,
            for: NSSelectorFromString("lookupWithMountSessionId:parentHandleId:name:reply:"),
            argumentIndex: 1,
            ofReply: true
        )
        // lookupParent → reply (parentHandleId, NocFSFileStat?, Error?)
        interface.setClasses(
            statClasses,
            for: NSSelectorFromString("lookupParentWithMountSessionId:handleId:reply:"),
            argumentIndex: 1,
            ofReply: true
        )
        // getattr → reply (NocFSFileStat?, Error?)
        interface.setClasses(
            statClasses,
            for: NSSelectorFromString("getattrWithMountSessionId:handleId:reply:"),
            argumentIndex: 0,
            ofReply: true
        )
        // setattr → input arg 2 = NocFSAttributesPatch
        let setattrSel = NSSelectorFromString("setattrWithMountSessionId:handleId:patch:reply:")
        interface.setClasses(
            patchClasses,
            for: setattrSel,
            argumentIndex: 2,
            ofReply: false
        )
        // setattr → reply (NocFSFileStat?, Error?)
        interface.setClasses(
            statClasses,
            for: setattrSel,
            argumentIndex: 0,
            ofReply: true
        )
        // readdir → reply ([NocFSDirEntry]?, Bool, UInt64, UInt64, Error?)
        interface.setClasses(
            dirEntryClasses,
            for: NSSelectorFromString("readdirWithMountSessionId:handleId:cookie:cookieVerifier:maxEntries:reply:"),
            argumentIndex: 0,
            ofReply: true
        )
        // open → reply (handleId, NocFSFileStat?, Error?)
        interface.setClasses(
            statClasses,
            for: NSSelectorFromString("openWithMountSessionId:parentHandleId:name:shareAccess:shareDeny:createMode:reply:"),
            argumentIndex: 1,
            ofReply: true
        )
        // create → input arg 4 = NocFSAttributesInit
        let createSel = NSSelectorFromString("createWithMountSessionId:parentHandleId:name:type:attrs:reply:")
        interface.setClasses(
            attrsInitClasses,
            for: createSel,
            argumentIndex: 4,
            ofReply: false
        )
        // create → reply (handleId, NocFSFileStat?, Error?)
        interface.setClasses(
            statClasses,
            for: createSel,
            argumentIndex: 1,
            ofReply: true
        )

        return interface
    }
}
