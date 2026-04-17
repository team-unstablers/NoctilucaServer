//
//  main.swift
//  nocvirtdisplay
//
//  Created by Gyuhwan Park on 4/17/26.
//

import Foundation
import ArgumentParser

private func die(_ message: String, code: Int32) -> Never {
    fputs("nocvirtdisplay: \(message)\n", stderr)
    exit(code)
}

struct NocVirtDisplay: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "nocvirtdisplay",
        abstract: "Spawns a virtual display using CoreGraphics / SkyLight private APIs.",
        discussion:
"""
So you found this binary! `nocvirtdisplay` spawns a virtual display using CoreGraphics / SkyLight private APIs.

OUTPUTS:
- On successful spawn, `nocvirtdisplay` prints the DISPLAY_ID as a single decimal integer line to STDOUT.
- If an error occurs during an API call, a message in the following format is written to STDERR.

    nocvirtdisplay: <reason>

SIGNALS:
`nocvirtdisplay` handles the following signals:

- SIGINT / SIGTERM: Terminates the process immediately. The spawned virtual display is cleaned up by WindowServer when it detects the XPC connection death. (retval = 0)

EXIT CODES (RETVALS):
- 0: Normal termination
- 1: Failed to initialize CGVirtualDisplay (descriptor rejected)
- 2: Failed to apply display settings (applySettings returned false)
- 3: Failed to acquire displayID (returned 0)
- 64: Argument parsing failure (ArgumentParser default)

NOTE:
This program is part of the Noctiluca Server product. Users holding a valid Noctiluca Server license may use it for personal scripting purposes, etc.
However, since it was originally written for use inside Noctiluca Server, correct behavior is not guaranteed when used outside its intended purpose.
"""
    )
    
    @Option(name: .long, help: "display identifier")
    var identifier: String? = nil
    
    @Option(name: .long, help: "display serial number")
    var serialNum: Int? = nil
    
    @Argument(help: "display specs, eg)\n640x480@59.94+1x,1280x720@60+1x,1280x720@60+2x,3840x2160@29.97")
    var specs: [String]
    
    mutating func run() throws {
        let specs: [NOCDisplaySpec] = try NOCDisplaySpec.parseList(specs)
        guard let maximumResolutionSpec = specs
            .sorted(by: { $0.resolution.width * $0.resolution.height > $1.resolution.width * $1.resolution.height })
            .first
        else {
            die("no valid display spec provided", code: 1)
        }

        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.name = if let identifier = identifier {
            "Noctiluca Virtual Display (\(identifier))"
        } else {
            "Noctiluca Virtual Display (\(UUID().uuidString))"
        }
        
        descriptor.vendorID  = 0xBAB0
        descriptor.productID = 0x0001
        
        descriptor.serialNum = if let serialNum {
            UInt32(serialNum)
        } else {
            /*
            let pid  = getpid()
            let mask = ???
            
            pid ^ mask
             */
            arc4random()
        }
        
        descriptor.sizeInMillimeters = CGSize(width: 597, height: 336)

        descriptor.maxPixelsWide = UInt32(maximumResolutionSpec.resolution.width)
        descriptor.maxPixelsHigh = UInt32(maximumResolutionSpec.resolution.height)
        
        descriptor.whitePoint = CGPointMake(0.3127, 0.3290)
        descriptor.redPrimary = CGPointMake(0.64, 0.33)
        descriptor.greenPrimary = CGPointMake(0.30, 0.60);
        descriptor.bluePrimary = CGPointMake(0.15, 0.06);
        
        descriptor.setDispatchQueue(DispatchQueue.global(qos: .userInteractive))
        descriptor.terminationHandler = { _, _ in
            NocVirtDisplay.exit()
        }
        
        let modes = Array(Set(specs.flatMap { $0.asCGVirtualDisplayModes() }))
        let settings = CGVirtualDisplaySettings()
        
        settings.hiDPI = 1
        settings.modes = modes
        
        guard let display = CGVirtualDisplay(descriptor: descriptor) else {
            die("failed to initialize CGVirtualDisplay (descriptor rejected)", code: 1)
        }

        guard display.apply(settings) else {
            die("failed to apply display settings", code: 2)
        }

        guard display.displayID != 0 else {
            die("virtual display spawned but displayID is 0", code: 3)
        }

        print(display.displayID)
        fflush(stdout)

        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)

        let sigQueue = DispatchQueue.global(qos: .userInitiated)
        let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: sigQueue)
        let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: sigQueue)
        let shutdown: @Sendable () -> Void = {
            // CGVirtualDisplay는 명시적 destroy API가 없으므로 프로세스 종료만 수행한다.
            // WindowServer가 XPC 연결 death를 감지해 가상 디스플레이를 정리한다.
            NocVirtDisplay.exit()
        }
        sigintSource.setEventHandler(handler: shutdown)
        sigtermSource.setEventHandler(handler: shutdown)
        sigintSource.resume()
        sigtermSource.resume()

        // CFRunLoopRun()은 attach된 source가 없으면 즉시 리턴하므로 빈 source로 run loop를 살려둔다.
        var keepAliveContext = CFRunLoopSourceContext()
        let keepAliveSource = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &keepAliveContext)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), keepAliveSource, .defaultMode)

        // 로컬 변수로 둔 DispatchSource / CGVirtualDisplay를 블로킹 직전에 명시적으로 참조해 해제를 방지.
        withExtendedLifetime((display, sigintSource, sigtermSource, keepAliveSource)) {
            CFRunLoopRun()
        }
    }
}

NocVirtDisplay.main()
