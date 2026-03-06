//
//  NOCScreenTests.swift
//  NoctilucaServerTests
//
//  Created by Codex on 2/4/26.
//

import CoreGraphics
import XCTest

@testable import NoctilucaServerTestsHost

final class NOCScreenTests: XCTestCase {
    private struct MockScreen: NSScreenLike {
        let compatibleDisplayID: CGDirectDisplayID?
        let frame: CGRect
        let backingScaleFactor: CGFloat
    }
    
    func testProduceIntermediateGlobalFrameUnionsScreens() {
        let left = MockScreen(
            compatibleDisplayID: 1,
            frame: CGRect(x: -100, y: 0, width: 100, height: 100),
            backingScaleFactor: 1.0
        )
        let main = MockScreen(
            compatibleDisplayID: 2,
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            backingScaleFactor: 1.0
        )
        
        let intermediate = NOCScreen.produceIntermediateGlobalFrame(from: [left, main])
        
        XCTAssertEqual(intermediate.origin.x, -100)
        XCTAssertEqual(intermediate.origin.y, 0)
        XCTAssertEqual(intermediate.size.width, 200)
        XCTAssertEqual(intermediate.size.height, 100)
    }
    
    func testProduceGlobalFrameNormalizesOrigin() {
        let left = MockScreen(
            compatibleDisplayID: 1,
            frame: CGRect(x: -100, y: 0, width: 100, height: 100),
            backingScaleFactor: 1.0
        )
        let main = MockScreen(
            compatibleDisplayID: 2,
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            backingScaleFactor: 1.0
        )
        
        let global = NOCScreen.produceGlobalFrame(from: [left, main])
        
        XCTAssertEqual(global.origin.x, 0)
        XCTAssertEqual(global.origin.y, 0)
        XCTAssertEqual(global.size.width, 200)
        XCTAssertEqual(global.size.height, 100)
    }
    
    func testNOCScreenInitConvertsToX11Coordinates() {
        let main = MockScreen(
            compatibleDisplayID: 1,
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            backingScaleFactor: 1.0
        )
        let upper = MockScreen(
            compatibleDisplayID: 2,
            frame: CGRect(x: 0, y: 100, width: 100, height: 100),
            backingScaleFactor: 1.0
        )
        
        let intermediate = NOCScreen.produceIntermediateGlobalFrame(from: [main, upper])
        let mainNOC = NOCScreen(from: main, intermediateGlobalFrame: intermediate)!
        let upperNOC = NOCScreen(from: upper, intermediateGlobalFrame: intermediate)!
        
        XCTAssertEqual(upperNOC.frame.origin.x, 0)
        XCTAssertEqual(upperNOC.frame.origin.y, 0)
        XCTAssertEqual(mainNOC.frame.origin.x, 0)
        XCTAssertEqual(mainNOC.frame.origin.y, 100)
    }
}
