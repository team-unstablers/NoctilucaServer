//
//  HIDIOInputRouter.swift
//  NoctilucaClient
//
//  Created by Codex on 12/27/25.
//

import Foundation
import CoreGraphics

import SiriusKitClient

final class HIDIOInputRouter {
    static let shared = HIDIOInputRouter()

    private enum Owner {
        case global
        case session(HIDIOInputSession)
    }

    private enum OwnerTag: Hashable {
        case global
        case session(ObjectIdentifier)
    }

    private struct DeviceKey: Hashable {
        let identifier: HIDIOVirtualDeviceIdentifier
        let ownerTag: OwnerTag
    }

    private struct DeviceEntry {
        let device: HIDIOVirtualDevice
        let owner: Owner
        let route: HIDIOInputRoute
    }

    private final class HIDIOInputRoute: HIDIOEventTarget {
        private weak var router: HIDIOInputRouter?
        private let owner: Owner

        init(router: HIDIOInputRouter, owner: Owner) {
            self.router = router
            self.owner = owner
        }

        func keyDown(keyCode: LinuxKeycode) {
            router?.route(owner: owner) { $0.keyDown(keyCode: keyCode) }
        }

        func keyUp(keyCode: LinuxKeycode) {
            router?.route(owner: owner) { $0.keyUp(keyCode: keyCode) }
        }

        func moveMouseAbsolutePercentage(to position: CGPoint) {
            router?.route(owner: owner) { $0.moveMouseAbsolutePercentage(to: position) }
        }

        func moveMouseRelative(to position: CGPoint) {
            router?.route(owner: owner) { $0.moveMouseRelative(to: position) }
        }

        func moveMouseRelativePercentage(to position: CGPoint) {
            router?.route(owner: owner) { $0.moveMouseRelativePercentage(to: position) }
        }

        func mouseButtonDown(button: MouseButtonType) {
            router?.route(owner: owner) { $0.mouseButtonDown(button: button) }
        }

        func mouseButtonUp(button: MouseButtonType) {
            router?.route(owner: owner) { $0.mouseButtonUp(button: button) }
        }

        func mouseWheel(delta: CGPoint) {
            router?.route(owner: owner) { $0.mouseWheel(delta: delta) }
        }
    }

    private let lock = NSLock()
    private var devices: [DeviceKey: DeviceEntry] = [:]
    private weak var activeSession: HIDIOInputSession?
#if os(macOS)
    private weak var eventTapDevice: HIDIOCocoaEventTapKeyboard?
#endif

    private init() {}

    func activate(_ session: HIDIOInputSession?) {
        let previous = swapActiveSession(session)
        if previous === session {
            return
        }

        previous?.handleInputDeactivated()
        applyCaptureLockState(for: nil)

        session?.handleInputActivated()
        applyCaptureLockState(for: session)
        updateEventTapErrorHandler()
    }

    func deactivate(_ session: HIDIOInputSession?) {
        guard let session else {
            return
        }

        lock.lock()
        let shouldDeactivate = (activeSession === session)
        lock.unlock()

        guard shouldDeactivate else {
            return
        }

        activate(nil)
    }

    func connect(_ device: HIDIOVirtualDevice, owner: HIDIOInputSession? = nil) {
        let identifier = type(of: device).identifier
        let ownerValue: Owner = owner.map { .session($0) } ?? .global
        let route = HIDIOInputRoute(router: self, owner: ownerValue)
        let key = deviceKey(identifier, owner: ownerValue)

        disconnect(key)

        lock.lock()
        devices[key] = DeviceEntry(device: device, owner: ownerValue, route: route)
        lock.unlock()

        device.connect(to: route)

        if let lockable = device as? HIDIOLockableVirtualDevice {
            applyCaptureLockIfNeeded(lockable, owner: ownerValue)
        }

#if os(macOS)
        if let eventTap = device as? HIDIOCocoaEventTapKeyboard {
            eventTapDevice = eventTap
            updateEventTapErrorHandler()
        }
#endif
    }

    func connectGlobal(_ device: HIDIOVirtualDevice) {
        connect(device, owner: nil)
    }

    func disconnect(_ identifier: HIDIOVirtualDeviceIdentifier, owner: HIDIOInputSession? = nil) {
        let key = deviceKey(identifier, owner: owner)
        disconnect(key)
    }

    func disconnectAll(kind: HIDIOVirtualDeviceKind, owner: HIDIOInputSession? = nil) {
        let keysToDisconnect: [DeviceKey] = {
            lock.lock()
            defer { lock.unlock() }

            return devices
                .filter { type(of: $0.value.device).kind == kind }
                .filter { ownerMatches($0.value.owner, owner: owner) }
                .map { $0.key }
        }()

        for key in keysToDisconnect {
            disconnect(key)
        }
    }

    func device(for identifier: HIDIOVirtualDeviceIdentifier, owner: HIDIOInputSession? = nil) -> HIDIOVirtualDevice? {
        let key = deviceKey(identifier, owner: owner)

        lock.lock()
        defer { lock.unlock() }

        return devices[key]?.device
    }

    func devices(for kind: HIDIOVirtualDeviceKind, owner: HIDIOInputSession? = nil) -> [HIDIOVirtualDevice] {
        lock.lock()
        defer { lock.unlock() }

        return devices.values
            .filter { type(of: $0.device).kind == kind }
            .filter { ownerMatches($0.owner, owner: owner) }
            .map { $0.device }
    }

    func captureLockDidChange(for session: HIDIOInputSession) {
        lock.lock()
        let isActive = (activeSession === session)
        lock.unlock()

        guard isActive else {
            return
        }

        applyCaptureLockState(for: session)
    }

    private func route(owner: Owner, _ action: (HIDIOInputSession) -> Void) {
        guard let active = currentActiveSession() else {
            return
        }

        switch owner {
        case .global:
            action(active)
        case .session(let session):
            guard session === active else {
                return
            }
            action(active)
        }
    }

    private func currentActiveSession() -> HIDIOInputSession? {
        lock.lock()
        defer { lock.unlock() }
        return activeSession
    }

    private func swapActiveSession(_ session: HIDIOInputSession?) -> HIDIOInputSession? {
        lock.lock()
        defer { lock.unlock() }

        let previous = activeSession
        activeSession = session
        return previous
    }

    private func ownerMatches(_ storedOwner: Owner, owner: HIDIOInputSession?) -> Bool {
        switch (storedOwner, owner) {
        case (.global, nil):
            return true
        case (.session(let stored), let owner?):
            return stored === owner
        default:
            return false
        }
    }

    private func deviceKey(_ identifier: HIDIOVirtualDeviceIdentifier, owner: Owner) -> DeviceKey {
        DeviceKey(identifier: identifier, ownerTag: ownerTag(for: owner))
    }

    private func deviceKey(_ identifier: HIDIOVirtualDeviceIdentifier, owner: HIDIOInputSession?) -> DeviceKey {
        let ownerValue: Owner = owner.map { .session($0) } ?? .global
        return deviceKey(identifier, owner: ownerValue)
    }

    private func ownerTag(for owner: Owner) -> OwnerTag {
        switch owner {
        case .global:
            return .global
        case .session(let session):
            return .session(ObjectIdentifier(session))
        }
    }

    private func applyCaptureLockState(for session: HIDIOInputSession?) {
        let shouldLock = session?.isCaptureLockEnabled ?? false
        let lockableDevices = currentLockableDevices(for: session)

        for device in lockableDevices {
            if shouldLock {
                try? device.lock()
            } else {
                try? device.unlock()
            }
        }
    }

    private func applyCaptureLockIfNeeded(_ device: HIDIOLockableVirtualDevice, owner: Owner) {
        let active = currentActiveSession()
        let shouldLock: Bool

        switch owner {
        case .global:
            shouldLock = active?.isCaptureLockEnabled ?? false
        case .session(let session):
            shouldLock = (active === session) && session.isCaptureLockEnabled
        }

        if shouldLock {
            try? device.lock()
        } else {
            try? device.unlock()
        }
    }

    private func currentLockableDevices(for session: HIDIOInputSession?) -> [HIDIOLockableVirtualDevice] {
        lock.lock()
        defer { lock.unlock() }

        return devices.values.compactMap { entry in
            guard let lockable = entry.device as? HIDIOLockableVirtualDevice else {
                return nil
            }

            guard let session else {
                return lockable
            }

            switch entry.owner {
            case .global:
                return lockable
            case .session(let ownerSession):
                return ownerSession === session ? lockable : nil
            }
        }
    }

    private func disconnect(_ key: DeviceKey) {
        let entry: DeviceEntry? = {
            lock.lock()
            defer { lock.unlock() }

            guard let entry = devices[key] else {
                return nil
            }
            devices.removeValue(forKey: key)
            return entry
        }()

        guard let entry else {
            return
        }

        if let lockable = entry.device as? HIDIOLockableVirtualDevice {
            try? lockable.unlock()
        }

        entry.device.disconnect()
    }

#if os(macOS)
    private func updateEventTapErrorHandler() {
        guard let eventTapDevice else {
            return
        }

        eventTapDevice.onError = { [weak self] error in
            guard let self else {
                return
            }

            let handler = self.currentActiveSession()?.onEventTapError
            handler?(error)
        }
    }
#else
    private func updateEventTapErrorHandler() {
    }
#endif
}
