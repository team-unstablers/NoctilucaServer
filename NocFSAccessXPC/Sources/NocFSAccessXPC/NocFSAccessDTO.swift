import Foundation

// MARK: - Mount session descriptor

/// Push payload for ``NocFSAccessDaemonProtocol/addMountSession(descriptor:reply:)``.
@objc(NocFSMountSessionDescriptor)
@objcMembers
public final class NocFSMountSessionDescriptor: NSObject, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { true }

    /// 1st-level namespace this mount session belongs to (e.g. `0001-cheesekun`).
    public let connectionLabel: String

    /// SRUUID string from ``FileSystemMountResponse.sessionId``.
    public let mountSessionId: String

    /// `FileSystemEntry.name` post-sanitization (`/` and NUL → `_`, dedupe with
    /// ` (2)` suffix). Used directly as the NFS directory entry name.
    public let displayName: String

    /// `AccessMode` raw value (`0 = read`, `1 = write`, `2 = readWrite`).
    public let grantedAccess: UInt32

    public init(connectionLabel: String,
                mountSessionId: String,
                displayName: String,
                grantedAccess: UInt32) {
        self.connectionLabel = connectionLabel
        self.mountSessionId = mountSessionId
        self.displayName = displayName
        self.grantedAccess = grantedAccess
        super.init()
    }

    private enum Key {
        static let connectionLabel = "connectionLabel"
        static let mountSessionId = "mountSessionId"
        static let displayName = "displayName"
        static let grantedAccess = "grantedAccess"
    }

    public func encode(with coder: NSCoder) {
        coder.encode(connectionLabel as NSString, forKey: Key.connectionLabel)
        coder.encode(mountSessionId as NSString, forKey: Key.mountSessionId)
        coder.encode(displayName as NSString, forKey: Key.displayName)
        coder.encode(Int64(grantedAccess), forKey: Key.grantedAccess)
    }

    public required init?(coder: NSCoder) {
        guard let connectionLabel = coder.decodeObject(of: NSString.self, forKey: Key.connectionLabel) as String?,
              let mountSessionId = coder.decodeObject(of: NSString.self, forKey: Key.mountSessionId) as String?,
              let displayName = coder.decodeObject(of: NSString.self, forKey: Key.displayName) as String?
        else { return nil }
        self.connectionLabel = connectionLabel
        self.mountSessionId = mountSessionId
        self.displayName = displayName
        self.grantedAccess = UInt32(truncatingIfNeeded: coder.decodeInt64(forKey: Key.grantedAccess))
        super.init()
    }
}

// MARK: - File stat snapshot

/// Mirrors ``FileStat`` in ``fsaccess_mount.mdproto``. All time fields are in
/// Unix epoch milliseconds; conversion to NFSv4 `nfstime4` (seconds + nseconds)
/// is lossy — `nseconds` is always set to 0.
@objc(NocFSFileStat)
@objcMembers
public final class NocFSFileStat: NSObject, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { true }

    /// ``NocFSObjectType`` raw value.
    public let type: UInt32
    /// Size in bytes. Directories MAY report 0.
    public let size: UInt64
    /// POSIX permission bits (mode_t-style).
    public let mode: UInt32
    public let mtimeMs: Int64
    public let atimeMs: Int64
    public let btimeMs: Int64
    /// ``FileAttributes`` optionset raw value.
    public let attributes: UInt32
    /// Non-nil only for symlinks resolved with `followSymlinks == false`.
    public let symlinkTarget: String?

    public init(type: UInt32,
                size: UInt64,
                mode: UInt32,
                mtimeMs: Int64,
                atimeMs: Int64,
                btimeMs: Int64,
                attributes: UInt32,
                symlinkTarget: String?) {
        self.type = type
        self.size = size
        self.mode = mode
        self.mtimeMs = mtimeMs
        self.atimeMs = atimeMs
        self.btimeMs = btimeMs
        self.attributes = attributes
        self.symlinkTarget = symlinkTarget
        super.init()
    }

    private enum Key {
        static let type = "type"
        static let size = "size"
        static let mode = "mode"
        static let mtimeMs = "mtimeMs"
        static let atimeMs = "atimeMs"
        static let btimeMs = "btimeMs"
        static let attributes = "attributes"
        static let symlinkTarget = "symlinkTarget"
    }

    public func encode(with coder: NSCoder) {
        coder.encode(Int64(type), forKey: Key.type)
        coder.encode(Int64(bitPattern: size), forKey: Key.size)
        coder.encode(Int64(mode), forKey: Key.mode)
        coder.encode(mtimeMs, forKey: Key.mtimeMs)
        coder.encode(atimeMs, forKey: Key.atimeMs)
        coder.encode(btimeMs, forKey: Key.btimeMs)
        coder.encode(Int64(attributes), forKey: Key.attributes)
        if let symlinkTarget {
            coder.encode(symlinkTarget as NSString, forKey: Key.symlinkTarget)
        }
    }

    public required init?(coder: NSCoder) {
        self.type = UInt32(truncatingIfNeeded: coder.decodeInt64(forKey: Key.type))
        self.size = UInt64(bitPattern: coder.decodeInt64(forKey: Key.size))
        self.mode = UInt32(truncatingIfNeeded: coder.decodeInt64(forKey: Key.mode))
        self.mtimeMs = coder.decodeInt64(forKey: Key.mtimeMs)
        self.atimeMs = coder.decodeInt64(forKey: Key.atimeMs)
        self.btimeMs = coder.decodeInt64(forKey: Key.btimeMs)
        self.attributes = UInt32(truncatingIfNeeded: coder.decodeInt64(forKey: Key.attributes))
        self.symlinkTarget = coder.decodeObject(of: NSString.self, forKey: Key.symlinkTarget) as String?
        super.init()
    }
}

// MARK: - Attributes patch (setattr input)

/// Optional fields for `setattr`. Nil-valued fields are not modified.
@objc(NocFSAttributesPatch)
@objcMembers
public final class NocFSAttributesPatch: NSObject, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { true }

    /// New POSIX mode bits, or nil to leave unchanged.
    public let mode: NSNumber?
    /// New size (truncate or extend), or nil.
    public let size: NSNumber?
    /// New mtime in epoch ms, or nil.
    public let mtimeMs: NSNumber?
    /// New atime in epoch ms, or nil.
    public let atimeMs: NSNumber?

    public init(mode: NSNumber? = nil,
                size: NSNumber? = nil,
                mtimeMs: NSNumber? = nil,
                atimeMs: NSNumber? = nil) {
        self.mode = mode
        self.size = size
        self.mtimeMs = mtimeMs
        self.atimeMs = atimeMs
        super.init()
    }

    private enum Key {
        static let mode = "mode"
        static let size = "size"
        static let mtimeMs = "mtimeMs"
        static let atimeMs = "atimeMs"
    }

    public func encode(with coder: NSCoder) {
        if let mode { coder.encode(mode, forKey: Key.mode) }
        if let size { coder.encode(size, forKey: Key.size) }
        if let mtimeMs { coder.encode(mtimeMs, forKey: Key.mtimeMs) }
        if let atimeMs { coder.encode(atimeMs, forKey: Key.atimeMs) }
    }

    public required init?(coder: NSCoder) {
        self.mode = coder.decodeObject(of: NSNumber.self, forKey: Key.mode)
        self.size = coder.decodeObject(of: NSNumber.self, forKey: Key.size)
        self.mtimeMs = coder.decodeObject(of: NSNumber.self, forKey: Key.mtimeMs)
        self.atimeMs = coder.decodeObject(of: NSNumber.self, forKey: Key.atimeMs)
        super.init()
    }
}

// MARK: - Attributes init (create input)

/// Initial attributes for `create`. Currently only `mode` is honored; future
/// extensions MAY add timestamps.
@objc(NocFSAttributesInit)
@objcMembers
public final class NocFSAttributesInit: NSObject, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { true }

    public let mode: UInt32

    public init(mode: UInt32) {
        self.mode = mode
        super.init()
    }

    private enum Key {
        static let mode = "mode"
    }

    public func encode(with coder: NSCoder) {
        coder.encode(Int64(mode), forKey: Key.mode)
    }

    public required init?(coder: NSCoder) {
        self.mode = UInt32(truncatingIfNeeded: coder.decodeInt64(forKey: Key.mode))
        super.init()
    }
}

// MARK: - Directory entry

/// Single entry in a `readdir` reply. `cookie` is the per-handle cursor that
/// the next continuation MUST pass back.
@objc(NocFSDirEntry)
@objcMembers
public final class NocFSDirEntry: NSObject, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { true }

    public let name: String
    public let stat: NocFSFileStat
    public let cookie: UInt64
    /// Host-issued handle id usable in subsequent `getattr` / `open` calls
    /// without a separate `lookup` round-trip.
    public let handleId: UInt64

    public init(name: String, stat: NocFSFileStat, cookie: UInt64, handleId: UInt64) {
        self.name = name
        self.stat = stat
        self.cookie = cookie
        self.handleId = handleId
        super.init()
    }

    private enum Key {
        static let name = "name"
        static let stat = "stat"
        static let cookie = "cookie"
        static let handleId = "handleId"
    }

    public func encode(with coder: NSCoder) {
        coder.encode(name as NSString, forKey: Key.name)
        coder.encode(stat, forKey: Key.stat)
        coder.encode(Int64(bitPattern: cookie), forKey: Key.cookie)
        coder.encode(Int64(bitPattern: handleId), forKey: Key.handleId)
    }

    public required init?(coder: NSCoder) {
        guard let name = coder.decodeObject(of: NSString.self, forKey: Key.name) as String?,
              let stat = coder.decodeObject(of: NocFSFileStat.self, forKey: Key.stat)
        else { return nil }
        self.name = name
        self.stat = stat
        self.cookie = UInt64(bitPattern: coder.decodeInt64(forKey: Key.cookie))
        self.handleId = UInt64(bitPattern: coder.decodeInt64(forKey: Key.handleId))
        super.init()
    }
}
