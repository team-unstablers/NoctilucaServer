import Foundation

/// Error domain for ``NSError`` instances synthesised by either side of the
/// nocfsaccessd XPC bridge that cannot be expressed as a POSIX `errno`.
///
/// Receivers SHOULD prefer ``NSPOSIXErrorDomain`` whenever a sensible errno
/// applies (e.g. `ENOENT`, `EACCES`, `ESTALE`) — the daemon translates POSIX
/// errors into ``NFSError`` directly, which is the most natural mapping. This
/// domain exists for purely XPC-layer faults (e.g. mount session lookup
/// failures inside the host bridge) where there is no clean POSIX equivalent.
public let NocFSAccessXPCErrorDomain = "pl.unstabler.noctiluca.fsaccessd.xpc"

/// Custom error codes carried in ``NocFSAccessXPCErrorDomain``.
public enum NocFSAccessXPCErrorCode: Int {
    /// Generic catch-all when the host has nothing better to report. Daemon
    /// MUST treat this as an opaque server fault and surface `NFS4ERR_SERVERFAULT`.
    case internalError = 1
    /// The XPC connection's host side has shut down or is no longer accepting
    /// callbacks. Daemon SHOULD exit shortly after observing this.
    case hostUnavailable = 2
    /// Unknown / removed mount session. Daemon SHOULD invalidate the requesting
    /// NFS handle and reply with `NFS4ERR_STALE` to the NFS client.
    case unknownMountSession = 3
    /// Reply payload was malformed (unexpected nil, mismatched DTO version).
    case malformedReply = 4
}

extension NSError {
    /// Build an ``NSPOSIXErrorDomain`` error from a Darwin `errno` value.
    /// ``localizedDescription`` is set when ``message`` is provided to keep
    /// daemon log lines self-explanatory.
    public static func nocFSPosix(_ errno: Int32, message: String? = nil) -> NSError {
        var userInfo: [String: Any] = [:]
        if let message {
            userInfo[NSLocalizedDescriptionKey] = message
        }
        return NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: userInfo)
    }

    /// Build an ``NocFSAccessXPCErrorDomain`` error for cases that don't have
    /// a clean POSIX errno equivalent.
    public static func nocFSAccessXPC(_ code: NocFSAccessXPCErrorCode, message: String? = nil) -> NSError {
        var userInfo: [String: Any] = [:]
        if let message {
            userInfo[NSLocalizedDescriptionKey] = message
        }
        return NSError(domain: NocFSAccessXPCErrorDomain, code: code.rawValue, userInfo: userInfo)
    }
}
