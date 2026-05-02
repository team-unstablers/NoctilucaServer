//
//  AuthenticatorTests.swift
//  NoctilucaServerTests
//
//  Created by Coding Assistant on 4/25/26.
//

import XCTest

import NoctilucaPluginKit
@testable import NoctilucaServerTestsHost

@MainActor
final class AuthenticatorTests: XCTestCase {

    // MARK: - supportedMethods / supports

    func testSupportedMethodsReturnsUnionOfAllRegisteredPlugins() async throws {
        let (sut, _, _) = makeSUT()

        let methods = sut.supportedMethods()

        XCTAssertEqual(methods, [AuthMethod.password, AuthMethod.sshKey])
    }

    func testSupportedMethodsReturnsEmptySetWhenNoPluginsRegistered() async throws {
        let registry = AuthPluginRegistry()
        let sut = Authenticator(registry: registry)

        XCTAssertEqual(sut.supportedMethods(), [])
    }

    func testSupportsReturnsTrueOnlyForMethodsCoveredByRegisteredPlugins() async throws {
        let registry = AuthPluginRegistry()
        let pluginA = FakeAuthPluginV1A()
        registry.register(plugin: pluginA)
        let sut = Authenticator(registry: registry)

        XCTAssertTrue(sut.supports(method: .password))
        XCTAssertFalse(sut.supports(method: .sshKey))
    }

    // MARK: - authenticate: 성공/실패 분기

    func testAuthenticateReturnsSuccessUidWhenPluginSucceeds() async throws {
        let (sut, pluginA, _) = makeSUT()
        let expectedUid: uid_t = 42
        await pluginA.setAuthenticateResult(.success(expectedUid))

        let result = await sut.authenticate(
            using: .password,
            payload: Data([0x01, 0x02]),
            nonce: Data([0x03, 0x04])
        )

        guard case .success(let uid) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(uid, expectedUid)
    }

    func testAuthenticateReturnsFailureWhenAllPluginsFail() async throws {
        let (sut, pluginA, _) = makeSUT()
        await pluginA.setAuthenticateResult(.failure(.invalidPayload))

        let result = await sut.authenticate(
            using: .password,
            payload: Data(),
            nonce: Data()
        )

        guard case .failure(let error) = result else {
            return XCTFail("expected failure, got \(result)")
        }
        // Authenticator는 개별 플러그인 실패를 집계하지 않고
        // 최종적으로 `.authenticationFailed(nil)`을 반환하는 것이 명세.
        guard case .authenticationFailed(let inner) = error else {
            return XCTFail("expected .authenticationFailed, got \(error)")
        }
        XCTAssertNil(inner)
    }

    func testAuthenticateReturnsFailureWhenNoPluginSupportsMethod() async throws {
        let registry = AuthPluginRegistry()
        let pluginB = FakeAuthPluginV1B()
        registry.register(plugin: pluginB)
        let sut = Authenticator(registry: registry)

        // .password를 지원하는 플러그인이 하나도 없는 상태
        let result = await sut.authenticate(
            using: .password,
            payload: Data([0xAA]),
            nonce: Data([0xBB])
        )

        guard case .failure(let error) = result else {
            return XCTFail("expected failure, got \(result)")
        }
        guard case .authenticationFailed(let inner) = error else {
            return XCTFail("expected .authenticationFailed, got \(error)")
        }
        XCTAssertNil(inner)

        // 루프가 아예 실행되지 않았어야 한다.
        let callsB = await pluginB.authenticateCalls
        XCTAssertTrue(callsB.isEmpty)
    }

    // MARK: - authenticate: 순차 디스패치

    func testAuthenticateStopsAtFirstSuccessfulPlugin() async throws {
        // 같은 메서드(.password)를 지원하는 플러그인 여러 개를 FakeA 인스턴스로 등록.
        // 첫 번째는 실패, 두 번째는 성공, 세 번째는 호출되지 않아야 한다.
        let registry = AuthPluginRegistry()
        let first = FakeAuthPluginV1A()
        let second = FakeAuthPluginV1A()
        let third = FakeAuthPluginV1A()
        registry.register(plugin: first)
        registry.register(plugin: second)
        registry.register(plugin: third)
        await first.setAuthenticateResult(.failure(.authenticationFailed(nil)))
        await second.setAuthenticateResult(.success(101))
        await third.setAuthenticateResult(.success(999))  // 호출되면 안 됨

        let sut = Authenticator(registry: registry)

        let result = await sut.authenticate(
            using: .password,
            payload: Data(),
            nonce: Data()
        )

        guard case .success(let uid) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(uid, 101)

        let firstCalls = await first.authenticateCalls
        let secondCalls = await second.authenticateCalls
        let thirdCalls = await third.authenticateCalls
        XCTAssertEqual(firstCalls.count, 1)
        XCTAssertEqual(secondCalls.count, 1)
        XCTAssertEqual(thirdCalls.count, 0)
    }

    func testAuthenticateSkipsPluginsWithUnsupportedMethod() async throws {
        let (sut, pluginA, pluginB) = makeSUT()
        await pluginA.setAuthenticateResult(.success(7))

        // .password로 호출: .sshKey 전용 pluginB는 호출되지 않아야 함
        _ = await sut.authenticate(using: .password, payload: Data(), nonce: Data())

        let callsA = await pluginA.authenticateCalls
        let callsB = await pluginB.authenticateCalls
        XCTAssertEqual(callsA.count, 1)
        XCTAssertEqual(callsB.count, 0)
    }

    // MARK: - authenticate: payload/nonce 전달

    func testAuthenticatePassesPayloadAndNonceToPlugin() async throws {
        let (sut, pluginA, _) = makeSUT()
        await pluginA.setAuthenticateResult(.failure(.authenticationFailed(nil)))

        let payload = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let nonce = Data([0x10, 0x20, 0x30, 0x40])

        _ = await sut.authenticate(using: .password, payload: payload, nonce: nonce)

        let calls = await pluginA.authenticateCalls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.method, .password)
        XCTAssertEqual(calls.first?.payload, payload)
        XCTAssertEqual(calls.first?.nonce, nonce)
    }

    // MARK: - setupAllowedEntires

    func testSetupAllowedEntiresRoutesEntriesByMethod() async throws {
        let (sut, pluginA, pluginB) = makeSUT()

        let pwEntry1 = AuthEntry(method: .password, identifier: "user1")
        let pwEntry2 = AuthEntry(method: .password, identifier: "user2")
        let sshEntry = AuthEntry(method: .sshKey, identifier: "user3")

        await sut.setupAllowedEntires([pwEntry1, sshEntry, pwEntry2])

        let allowedA = await pluginA.allowedEntries
        let allowedB = await pluginB.allowedEntries

        XCTAssertEqual(Set(allowedA), [pwEntry1, pwEntry2])
        XCTAssertEqual(Set(allowedB), [sshEntry])
    }

    func testSetupAllowedEntiresContinuesAfterPluginThrows() async throws {
        let (sut, pluginA, _) = makeSUT()
        await pluginA.setAllowError(FakeAuthPluginError.allowRejected)

        let entries = [
            AuthEntry(method: .password, identifier: "a"),
            AuthEntry(method: .password, identifier: "b")
        ]

        // 플러그인이 allow에서 throw하더라도 Authenticator가 처리를 계속해야 하며,
        // 호출자 쪽으로 에러가 전파되지 않는 것이 명세(try? 사용).
        await sut.setupAllowedEntires(entries)

        // throw 때문에 entries가 기록되지 않더라도 크래시 없이 완료되어야 한다.
        let allowedA = await pluginA.allowedEntries
        XCTAssertTrue(allowedA.isEmpty)
    }

    // MARK: - updateAllowedEntries (diff 계산)

    func testUpdateAllowedEntriesAppliesAddAndRemoveDiff() async throws {
        let (sut, pluginA, _) = makeSUT()

        let entryA = AuthEntry(method: .password, identifier: "alice")
        let entryB = AuthEntry(method: .password, identifier: "bob")
        let entryC = AuthEntry(method: .password, identifier: "carol")

        await sut.updateAllowedEntries(from: [entryA, entryB], to: [entryB, entryC])

        let allowed = await pluginA.allowedEntries
        let denied = await pluginA.deniedEntries

        XCTAssertEqual(allowed, [entryC])
        XCTAssertEqual(denied, [entryA])
    }

    func testUpdateAllowedEntriesIsNoOpWhenEntriesIdentical() async throws {
        let (sut, pluginA, _) = makeSUT()

        let entries = [
            AuthEntry(method: .password, identifier: "alice"),
            AuthEntry(method: .password, identifier: "bob")
        ]

        await sut.updateAllowedEntries(from: entries, to: entries)

        let allowed = await pluginA.allowedEntries
        let denied = await pluginA.deniedEntries
        XCTAssertTrue(allowed.isEmpty)
        XCTAssertTrue(denied.isEmpty)
    }

    func testUpdateAllowedEntriesRoutesByMethod() async throws {
        let (sut, pluginA, pluginB) = makeSUT()

        let pwEntry = AuthEntry(method: .password, identifier: "alice")
        let sshEntry = AuthEntry(method: .sshKey, identifier: "alice")

        // from: pwEntry만, to: sshEntry만 → pwEntry는 deny(.password 플러그인),
        //                                    sshEntry는 allow(.sshKey 플러그인)
        await sut.updateAllowedEntries(from: [pwEntry], to: [sshEntry])

        let allowedA = await pluginA.allowedEntries
        let deniedA = await pluginA.deniedEntries
        let allowedB = await pluginB.allowedEntries
        let deniedB = await pluginB.deniedEntries

        XCTAssertTrue(allowedA.isEmpty)
        XCTAssertEqual(deniedA, [pwEntry])
        XCTAssertEqual(allowedB, [sshEntry])
        XCTAssertTrue(deniedB.isEmpty)
    }
}

// MARK: - Helpers

private extension AuthenticatorTests {
    /// `.password` 플러그인(A) + `.sshKey` 플러그인(B)이 등록된 Authenticator를 만들어 돌려준다.
    func makeSUT() -> (Authenticator, FakeAuthPluginV1A, FakeAuthPluginV1B) {
        let registry = AuthPluginRegistry()
        let pluginA = FakeAuthPluginV1A()
        let pluginB = FakeAuthPluginV1B()
        registry.register(plugin: pluginA)
        registry.register(plugin: pluginB)
        let sut = Authenticator(registry: registry)
        return (sut, pluginA, pluginB)
    }
}
