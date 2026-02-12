//
//  ProjectionChannelStateTests.swift
//  NoctilucaServerTests
//
//  Created by Codex on 2/12/26.
//

import XCTest

@testable import NoctilucaServer

final class ProjectionChannelStateTests: XCTestCase {
    func testReserveSessionRejectsDuplicateIdentifier() async {
        let state = ProjectionChannelState()
        let identifier = UUID()

        XCTAssertTrue(await state.reserveSession(identifier: identifier, kind: .video))
        XCTAssertFalse(await state.reserveSession(identifier: identifier, kind: .video))
        XCTAssertFalse(await state.reserveSession(identifier: identifier, kind: .audio))
    }

    func testTerminateByControlMessageReleasesReservation() async {
        let state = ProjectionChannelState()
        let identifier = UUID()

        XCTAssertTrue(await state.reserveSession(identifier: identifier, kind: .video))

        _ = await state.terminateByControlMessage(identifier: identifier, kind: .video)

        XCTAssertTrue(await state.reserveSession(identifier: identifier, kind: .video))
    }

    func testBeginDestroyTransitionsLifecycleAndSnapshotsSubscriptions() async {
        let state = ProjectionChannelState()
        let cursorSubscription = CursorEventSubscription()
        let displaySubscription = DisplayEventSubscription(eventMask: .init(rawValue: 0))

        XCTAssertTrue(await state.addCursorSubscriptionIfAbsent(cursorSubscription))

        switch await state.replaceDisplaySubscription(displaySubscription) {
        case .rejected:
            XCTFail("display subscription should be accepted while active")
        case .installed:
            break
        }

        let reservedID = UUID()
        XCTAssertTrue(await state.reserveSession(identifier: reservedID, kind: .audio))

        guard let snapshot = await state.beginDestroy() else {
            XCTFail("beginDestroy should return snapshot once")
            return
        }

        XCTAssertTrue(snapshot.cursorSubscription === cursorSubscription)
        XCTAssertTrue(snapshot.displaySubscription === displaySubscription)
        XCTAssertFalse(await state.reserveSession(identifier: UUID(), kind: .video))
        XCTAssertNil(await state.beginDestroy())

        await state.completeDestroy()

        XCTAssertFalse(await state.reserveSession(identifier: UUID(), kind: .audio))
    }

    func testDisplaySubscriptionReplaceAndUnsubscribeFlow() async {
        let state = ProjectionChannelState()

        let first = DisplayEventSubscription(eventMask: .init(rawValue: 0))
        let second = DisplayEventSubscription(eventMask: .init(rawValue: 0))

        switch await state.replaceDisplaySubscription(first) {
        case .rejected:
            XCTFail("first display subscription should be accepted")
        case .installed(let previous):
            XCTAssertNil(previous)
        }

        switch await state.replaceDisplaySubscription(second) {
        case .rejected:
            XCTFail("second display subscription should replace first")
        case .installed(let previous):
            XCTAssertTrue(previous === first)
        }

        switch await state.unsubscribeDisplaySubscription(expectedID: first.id) {
        case .mismatchedSubscriptionID:
            break
        default:
            XCTFail("unsubscribe with mismatched ID should fail")
        }

        XCTAssertTrue(await state.isCurrentDisplaySubscription(second))

        switch await state.unsubscribeDisplaySubscription(expectedID: second.id) {
        case .unsubscribed(let removed):
            XCTAssertTrue(removed === second)
        default:
            XCTFail("unsubscribe with current ID should succeed")
        }

        switch await state.unsubscribeDisplaySubscription(expectedID: second.id) {
        case .notFound:
            break
        default:
            XCTFail("unsubscribe after removal should report notFound")
        }
    }

    func testDataChannelTerminationIsIdempotentWithoutResources() async {
        let state = ProjectionChannelState()
        let identifier = UUID()

        let first = await state.terminateByDataChannelClosure(identifier: identifier)
        XCTAssertNil(first.videoSession)
        XCTAssertNil(first.audioSession)
        XCTAssertNil(first.dataChannel)

        let second = await state.terminateByDataChannelClosure(identifier: identifier)
        XCTAssertNil(second.videoSession)
        XCTAssertNil(second.audioSession)
        XCTAssertNil(second.dataChannel)
    }
}
