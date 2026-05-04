import Foundation

// MARK: - host → daemon

/// Methods that the host application invokes on the running ``nocfsaccessd`` daemon.
///
/// The host process owns the ``NSXPCListener`` and the daemon connects back over an
/// anonymous endpoint passed via the ``NOC_FSACCESSD_XPC_ENDPOINT`` environment
/// variable. All replies are delivered asynchronously on an unspecified thread.
@objc(NocFSAccessDaemonProtocol)
public protocol NocFSAccessDaemonProtocol {
    /// Tell the daemon to start the loopback NFSv4 listener on an OS-assigned
    /// port. The daemon replies with the actual bound port (or an error).
    ///
    /// MUST be called exactly once. Subsequent calls reply with `EALREADY`.
    func daemonReady(reply: @Sendable @escaping (UInt16, Error?) -> Void)

    /// Add a 1st-level namespace entry (e.g. `0001-cheesekun`) to the virtual
    /// tree. After this call returns, NFS clients can `readdir` the new
    /// directory.
    func addConnection(connectionLabel: String,
                       displayName: String,
                       reply: @Sendable @escaping (Error?) -> Void)

    /// Remove a connection and cascade-invalidate every mount session under it.
    /// All NFS file handles owned by removed mount sessions become stale.
    func removeConnection(connectionLabel: String,
                          reply: @Sendable @escaping (Error?) -> Void)

    /// Add a 2nd-level mount session entry under its parent connection's
    /// namespace. The descriptor's ``connectionLabel`` MUST already exist (added
    /// via ``addConnection(connectionLabel:displayName:reply:)``).
    func addMountSession(descriptor: NocFSMountSessionDescriptor,
                         reply: @Sendable @escaping (Error?) -> Void)

    /// Remove a mount session and invalidate all of its NFS file handles.
    func removeMountSession(mountSessionId: String,
                            reply: @Sendable @escaping (Error?) -> Void)

    /// Cooperative shutdown. The daemon stops the NFS listener, drains in-flight
    /// requests with `serverFault`, and exits the process after the reply is
    /// delivered.
    func shutdownGracefully(reply: @Sendable @escaping () -> Void)
}

// MARK: - daemon → host

/// Methods that the daemon invokes on the host application as part of NFS
/// callback fulfilment. Every reply MUST eventually be called — either with a
/// success payload or with an `NSError` whose domain is `NSPOSIXErrorDomain`
/// (preferred) or ``NocFSAccessXPCErrorDomain``.
///
/// `mountSessionId` is the SRUUID string the host originally passed via
/// ``NocFSAccessDaemonProtocol/addMountSession(descriptor:reply:)``. If the
/// session no longer exists, reply with `NSError(domain: NSPOSIXErrorDomain,
/// code: ESTALE)`.
///
/// `handleId` / `parentHandleId` values originate from prior reply payloads of
/// ``open(mountSessionId:parentHandleId:name:shareAccess:shareDeny:createMode:reply:)``,
/// ``lookup(mountSessionId:parentHandleId:name:reply:)`` or
/// ``create(mountSessionId:parentHandleId:name:type:attrs:reply:)``. They are
/// opaque on the host side; the host only owns a `[handleId: path]` mapping.
@objc(NocFSAccessHostProtocol)
public protocol NocFSAccessHostProtocol {
    /// Resolve a child entry of `parentHandleId` named `name`. The reply
    /// includes the child's stat snapshot and the host-issued `handleId` that
    /// should be used in subsequent calls.
    func lookup(mountSessionId: String,
                parentHandleId: UInt64,
                name: String,
                reply: @Sendable @escaping (UInt64, NocFSFileStat?, Error?) -> Void)

    /// Resolve the parent of `handleId`. Used for NFSv4 `LOOKUPP`.
    func lookupParent(mountSessionId: String,
                      handleId: UInt64,
                      reply: @Sendable @escaping (UInt64, NocFSFileStat?, Error?) -> Void)

    /// Stat by handle.
    func getattr(mountSessionId: String,
                 handleId: UInt64,
                 reply: @Sendable @escaping (NocFSFileStat?, Error?) -> Void)

    /// Mutate attributes by handle. Returns the post-mutation stat.
    func setattr(mountSessionId: String,
                 handleId: UInt64,
                 patch: NocFSAttributesPatch,
                 reply: @Sendable @escaping (NocFSFileStat?, Error?) -> Void)

    /// POSIX-style permission probe. `mask` carries `R_OK | W_OK | X_OK` flags
    /// in the lower 3 bits; the reply mirrors the granted subset.
    func access(mountSessionId: String,
                handleId: UInt64,
                mask: UInt32,
                reply: @Sendable @escaping (UInt32, Error?) -> Void)

    /// Read directory contents. `cookie` / `cookieVerifier` follow NFSv4
    /// READDIR semantics. The reply's `nextCookie` is what the next READDIR
    /// continuation should pass back as `cookie`. `isEnd == true` means the
    /// cursor is exhausted.
    func readdir(mountSessionId: String,
                 handleId: UInt64,
                 cookie: UInt64,
                 cookieVerifier: UInt64,
                 maxEntries: Int,
                 reply: @Sendable @escaping ([NocFSDirEntry]?, Bool, UInt64, UInt64, Error?) -> Void)

    /// Read symbolic link target.
    func readlink(mountSessionId: String,
                  handleId: UInt64,
                  reply: @Sendable @escaping (String?, Error?) -> Void)

    /// Open (or create) a child of `parentHandleId`. The host translates this
    /// into a `FileSystemOpenRequest` over the fsaccess_mount channel. The
    /// reply's `handleId` is the host's identifier for the opened file (NFSv4
    /// stateids stay inside the daemon and are not exposed here).
    func open(mountSessionId: String,
              parentHandleId: UInt64,
              name: String,
              shareAccess: UInt32,
              shareDeny: UInt32,
              createMode: UInt32,
              reply: @Sendable @escaping (UInt64, NocFSFileStat?, Error?) -> Void)

    /// Close a previously opened handle (implicit fsync for write handles).
    func close(mountSessionId: String,
               handleId: UInt64,
               reply: @Sendable @escaping (Error?) -> Void)

    /// Read up to `length` bytes from `offset`. The reply MAY return fewer
    /// bytes than requested; callers MUST check `data.count`. `isEof == true`
    /// signals end-of-file at or before `offset + data.count`.
    func read(mountSessionId: String,
              handleId: UInt64,
              offset: UInt64,
              length: UInt32,
              reply: @Sendable @escaping (Data?, Bool, Error?) -> Void)

    /// Write `data` at `offset`. The reply's `bytesWritten` MAY be smaller
    /// than `data.count` for partial writes. `stability` mirrors NFSv4
    /// stability flags (`UNSTABLE4 = 0`, `DATA_SYNC4 = 1`, `FILE_SYNC4 = 2`).
    func write(mountSessionId: String,
               handleId: UInt64,
               offset: UInt64,
               data: Data,
               stability: UInt32,
               reply: @Sendable @escaping (UInt32, Error?) -> Void)

    /// Force durable persistence of `[offset, offset+length)`. Maps to
    /// `FileSystemFlushRequest` on the wire (length granularity is best-effort
    /// — most fsaccess implementations flush the whole file).
    func commit(mountSessionId: String,
                handleId: UInt64,
                offset: UInt64,
                length: UInt32,
                reply: @Sendable @escaping (Error?) -> Void)

    /// Create a new entry under `parentHandleId`. `type` mirrors
    /// ``NocFSObjectType``; `attrs` carries the initial mode and (later)
    /// timestamps.
    func create(mountSessionId: String,
                parentHandleId: UInt64,
                name: String,
                type: UInt32,
                attrs: NocFSAttributesInit,
                reply: @Sendable @escaping (UInt64, NocFSFileStat?, Error?) -> Void)

    /// Remove a non-directory entry under `parentHandleId`.
    func remove(mountSessionId: String,
                parentHandleId: UInt64,
                name: String,
                reply: @Sendable @escaping (Error?) -> Void)

    /// Rename an entry (POSIX `rename(2)` semantics, atomic on the same fs).
    func rename(mountSessionId: String,
                srcParentHandleId: UInt64,
                srcName: String,
                dstParentHandleId: UInt64,
                dstName: String,
                reply: @Sendable @escaping (Error?) -> Void)

    /// Hard-link `targetHandleId` into `parentHandleId/name`.
    func link(mountSessionId: String,
              targetHandleId: UInt64,
              parentHandleId: UInt64,
              name: String,
              reply: @Sendable @escaping (Error?) -> Void)
}

// MARK: - Object type constants

/// Mirrors ``FileType`` in ``fsaccess_mount.mdproto`` for use across the XPC
/// boundary. Stable wire identifiers; do not reorder.
@objc(NocFSObjectType)
public enum NocFSObjectType: Int {
    case unknown = 0
    case file = 1
    case directory = 2
    case symlink = 3
    case other = 99
}
