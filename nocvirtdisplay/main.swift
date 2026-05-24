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
- 4: Display spec rejected by guard policy (resolution/scale/refresh/aspect out of range)
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

        // 가드 정책 검증. 서버에서도 동일 검증을 수행하지만, helper를 독립 실행하는 경우에도
        // 이상 해상도(1x1, 262144x2 등)로 인해 WindowServer가 이상 상태에 빠지는 걸 막는다.
        for spec in specs {
            do {
                try spec.validateForVirtualDisplay()
            } catch {
                die("spec '\(spec)' rejected: \(error)", code: 4)
            }
        }

        // maxPixelsWide/High는 픽셀 단위 상한이므로 scaleFactor를 곱한 네이티브 해상도 기준으로 비교해야 한다.
        // 그렇지 않으면 HiDPI 모드(예: 1280x720+2x → 2560x1440)가 상한을 초과해 WindowServer가 거부한다.
        guard let maximumResolutionSpec = specs
            .sorted(by: {
                let lhs = $0.resolution.width * $0.scaleFactor * $0.resolution.height * $0.scaleFactor
                let rhs = $1.resolution.width * $1.scaleFactor * $1.resolution.height * $1.scaleFactor
                return lhs > rhs
            })
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

        descriptor.maxPixelsWide = UInt32(maximumResolutionSpec.resolution.width * maximumResolutionSpec.scaleFactor)
        descriptor.maxPixelsHigh = UInt32(maximumResolutionSpec.resolution.height * maximumResolutionSpec.scaleFactor)
        
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
        
        guard let cfModes = CGDisplayCopyAllDisplayModes(
                display.displayID,
                [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
              ),
              let cgModes = cfModes as? [CGDisplayMode]
        else {
            die("no display modes available", code: 4)
        }
        
        
        let compatibleSpecs = cgModes.filter { NOCDisplaySpec.from(cgDisplayMode: $0).compatible(with: maximumResolutionSpec) }
        
        guard let mostCompatibleSpec = compatibleSpecs.first else {
            die("no compatible display modes available", code: 4)
        }
        
        let error = CGDisplaySetDisplayMode(display.displayID, mostCompatibleSpec, nil)
        
        guard error == .success else {
            die("failed to apply spec to display", code: 4)
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

        // 부모 프로세스 사망 감지 — stdin을 부모-자식 lifetime pipe로 사용.
        // 부모가 write end를 보유하다가 사망하면 자식 stdin이 EOF를 받는다.
        // 터미널에서 직접 실행한 경우엔 stdin이 tty에 붙어있으므로 EOF가 오지 않아 정상.
        let stdinSource = DispatchSource.makeReadSource(
            fileDescriptor: STDIN_FILENO,
            queue: sigQueue
        )
        stdinSource.setEventHandler {
            var buf = [UInt8](repeating: 0, count: 64)
            let n = read(STDIN_FILENO, &buf, buf.count)
            if n <= 0 {
                // n == 0: EOF (부모가 write end를 닫음, 즉 부모 사망)
                // n  < 0: read error — 이 경로도 부모 사망과 동등 취급
                NocVirtDisplay.exit()
            }
            // n > 0: 부모가 실수로 데이터를 보낸 경우. 버리고 계속 대기한다.
        }
        stdinSource.resume()

        // CFRunLoopRun()은 attach된 source가 없으면 즉시 리턴하므로 빈 source로 run loop를 살려둔다.
        var keepAliveContext = CFRunLoopSourceContext()
        let keepAliveSource = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &keepAliveContext)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), keepAliveSource, .defaultMode)

        // 로컬 변수로 둔 DispatchSource / CGVirtualDisplay를 블로킹 직전에 명시적으로 참조해 해제를 방지.
        withExtendedLifetime((display, sigintSource, sigtermSource, stdinSource, keepAliveSource)) {
            CFRunLoopRun()
        }
    }
}

NocVirtDisplay.main()
