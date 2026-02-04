//
//  CursorStateHolderTests.swift
//  NoctilucaServerTests
//
//  Created by Codex on 2/4/26.
//

import CoreGraphics
import XCTest

@testable import NoctilucaServer

final class CursorStateHolderTests: XCTestCase {
    private struct MockScreen: NSScreenLike {
        let compatibleDisplayID: CGDirectDisplayID?
        let frame: CGRect
        let backingScaleFactor: CGFloat
    }
    
    func testFromNSEventConvertsToX11AndRelativeCoordinates() {
        let mainID: CGDirectDisplayID = 1
        let upperID: CGDirectDisplayID = 2
        
        let main = MockScreen(
            compatibleDisplayID: mainID,
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            backingScaleFactor: 1.0
        )
        let upper = MockScreen(
            compatibleDisplayID: upperID,
            frame: CGRect(x: 0, y: 100, width: 100, height: 100),
            backingScaleFactor: 1.0
        )
        
        let intermediate = NOCScreen.produceIntermediateGlobalFrame(from: [main, upper])
        let mainNOC = NOCScreen(from: main, intermediateGlobalFrame: intermediate)!
        let upperNOC = NOCScreen(from: upper, intermediateGlobalFrame: intermediate)!
        
        let layouts: [CGDirectDisplayID: NOCScreen] = [
            mainID: mainNOC,
            upperID: upperNOC
        ]
        
        // Cocoa Global: (0,0) bottom-left of main. Point in upper screen.
        let cocoaPoint = CGPoint(x: 10, y: 150)
        let state = CursorState.fromNSEvent(
            cocoaPoint,
            layouts: layouts,
            intermediateGlobalFrame: intermediate
        )
        
        // X11 Global: (0,0) top-left of full viewport.
        XCTAssertEqual(state.absolutePosition.x, 10, accuracy: 0.0001)
        XCTAssertEqual(state.absolutePosition.y, 50, accuracy: 0.0001)
        XCTAssertEqual(state.belongsTo, upperID)
        XCTAssertEqual(state.relativePosition.x, 10, accuracy: 0.0001)
        XCTAssertEqual(state.relativePosition.y, 50, accuracy: 0.0001)
        
        // Point in main screen.
        let cocoaPointMain = CGPoint(x: 10, y: 50)
        let mainState = CursorState.fromNSEvent(
            cocoaPointMain,
            layouts: layouts,
            intermediateGlobalFrame: intermediate
        )
        
        XCTAssertEqual(mainState.absolutePosition.x, 10, accuracy: 0.0001)
        XCTAssertEqual(mainState.absolutePosition.y, 150, accuracy: 0.0001)
        XCTAssertEqual(mainState.belongsTo, mainID)
        XCTAssertEqual(mainState.relativePosition.x, 10, accuracy: 0.0001)
        XCTAssertEqual(mainState.relativePosition.y, 50, accuracy: 0.0001)
    }

    func testX11ToCoreGraphicsConversionUsesMainScreenOrigin() {
        let mainScreen = NOCScreen(
            id: 1,
            frame: CGRect(x: 0, y: 100, width: 100, height: 100),
            scaleFactor: 1.0
        )

        let x11Point = CGPoint(x: 10, y: 150)
        let cgPoint = CursorState.toCoreGraphicsCoordinate(x11Point, mainScreen: mainScreen)

        XCTAssertEqual(cgPoint.x, 10, accuracy: 0.0001)
        XCTAssertEqual(cgPoint.y, 50, accuracy: 0.0001)
    }

    func testCoreGraphicsToX11ConversionUsesMainScreenOrigin() {
        let mainScreen = NOCScreen(
            id: 1,
            frame: CGRect(x: 0, y: 100, width: 100, height: 100),
            scaleFactor: 1.0
        )

        let cgPoint = CGPoint(x: 10, y: 50)
        let x11Point = CursorState.toX11Coordinate(cgPoint, mainScreen: mainScreen)

        XCTAssertEqual(x11Point.x, 10, accuracy: 0.0001)
        XCTAssertEqual(x11Point.y, 150, accuracy: 0.0001)
    }

    func testX11AndCoreGraphicsRoundTrip() {
        let mainScreen = NOCScreen(
            id: 1,
            frame: CGRect(x: -50, y: 80, width: 200, height: 150),
            scaleFactor: 1.0
        )

        let x11Point = CGPoint(x: 30, y: 120)
        let cgPoint = CursorState.toCoreGraphicsCoordinate(x11Point, mainScreen: mainScreen)
        let roundTripX11 = CursorState.toX11Coordinate(cgPoint, mainScreen: mainScreen)

        XCTAssertEqual(roundTripX11.x, x11Point.x, accuracy: 0.0001)
        XCTAssertEqual(roundTripX11.y, x11Point.y, accuracy: 0.0001)

        let cgPoint2 = CGPoint(x: 12, y: 34)
        let x11Point2 = CursorState.toX11Coordinate(cgPoint2, mainScreen: mainScreen)
        let roundTripCG = CursorState.toCoreGraphicsCoordinate(x11Point2, mainScreen: mainScreen)

        XCTAssertEqual(roundTripCG.x, cgPoint2.x, accuracy: 0.0001)
        XCTAssertEqual(roundTripCG.y, cgPoint2.y, accuracy: 0.0001)
    }
}
