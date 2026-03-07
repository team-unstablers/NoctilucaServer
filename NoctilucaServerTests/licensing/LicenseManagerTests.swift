//
//  LicenseManagerTests.swift
//  NoctilucaServerTests
//
//  Created by Coding Assistant on 3/8/26.
//

import XCTest
import Security
import Alamofire
@testable import NoctilucaServerTestsHost

import SiriusKit

// MARK: - Mock Implementations

private final class MockLicenseKeychainStore: LicenseKeychainStore, @unchecked Sendable {
    var seatProofData: Data?
    var licenseInfoData: Data?
    var getError: SRKeychainError?
    var setError: SRKeychainError?

    func getSeatProof() -> Result<Data?, SRKeychainError> {
        if let error = getError { return .failure(error) }
        return .success(seatProofData)
    }

    func setSeatProof(_ data: Data) -> Result<Void, SRKeychainError> {
        if let error = setError { return .failure(error) }
        seatProofData = data
        return .success(())
    }

    func removeSeatProof() -> Result<Void, SRKeychainError> {
        seatProofData = nil
        return .success(())
    }

    func getLicenseInfo() -> Result<Data?, SRKeychainError> {
        if let error = getError { return .failure(error) }
        return .success(licenseInfoData)
    }

    func setLicenseInfo(_ data: Data) -> Result<Void, SRKeychainError> {
        if let error = setError { return .failure(error) }
        licenseInfoData = data
        return .success(())
    }

    func removeLicenseInfo() -> Result<Void, SRKeychainError> {
        licenseInfoData = nil
        return .success(())
    }
}

private final class MockLicenseAPIClient: LicenseAPIClientProtocol, @unchecked Sendable {
    var activateResult: Result<ActivateLicenseResponse, Error> = .failure(MockError.notConfigured)
    var validateResult: Result<ValidateSeatResponse, Error> = .failure(MockError.notConfigured)
    var revokeError: Error?

    var activateCalls: [(licenseInfo: LicenseInfo, hwid: String, label: String)] = []
    var validateCalls: [String] = []
    var revokeCalls: [(licenseInfo: LicenseInfo, seatId: String)] = []

    func activate(licenseInfo: LicenseInfo, hwid: String, label: String) async throws -> ActivateLicenseResponse {
        activateCalls.append((licenseInfo, hwid, label))
        return try activateResult.get()
    }

    func validateSeat(seatProof: String) async throws -> ValidateSeatResponse {
        validateCalls.append(seatProof)
        return try validateResult.get()
    }

    func revokeSeat(licenseInfo: LicenseInfo, seatId: String) async throws {
        revokeCalls.append((licenseInfo, seatId))
        if let error = revokeError { throw error }
    }

    enum MockError: Error {
        case notConfigured
    }
}

private struct MockHardwareIdentifierProvider: HardwareIdentifierProvider {
    let hwid: String?
    func hardwareIdentifier() -> String? { hwid }
}

private struct MockHostNameProvider: HostNameProvider {
    let name: String?
    func localizedName() -> String? { name }
}

// MARK: - LicenseManagerTests

final class LicenseManagerTests: XCTestCase {

    // MARK: - JWT Helpers

    private static func generateRSAKeyPair() -> (publicKey: SecKey, privateKey: SecKey) {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 4096
        ]

        var error: Unmanaged<CFError>?
        let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error)!
        let publicKey = SecKeyCopyPublicKey(privateKey)!

        return (publicKey, privateKey)
    }

    private static func exportDER(_ key: SecKey) -> Data {
        var error: Unmanaged<CFError>?
        let data = SecKeyCopyExternalRepresentation(key, &error)! as Data
        return data
    }

    private static func base64urlEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func createJWT(
        header: [String: Any] = ["alg": "RS256", "typ": "JWT"],
        payload: [String: Any],
        privateKey: SecKey
    ) -> String {
        let headerData = try! JSONSerialization.data(withJSONObject: header)
        let payloadData = try! JSONSerialization.data(withJSONObject: payload)

        let headerB64 = base64urlEncode(headerData)
        let payloadB64 = base64urlEncode(payloadData)

        let signedInput = "\(headerB64).\(payloadB64)"
        let signedInputData = signedInput.data(using: .utf8)!

        var error: Unmanaged<CFError>?
        let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            signedInputData as CFData,
            &error
        )! as Data

        let signatureB64 = base64urlEncode(signature)
        return "\(headerB64).\(payloadB64).\(signatureB64)"
    }

    // MARK: - Shared Fixtures

    private static let keyPair = generateRSAKeyPair()
    private static let publicKeyDER = exportDER(keyPair.publicKey)
    private static let testHwid = "test-hwid-sha512-hash"

    /// 유효한 seat proof JWT를 생성한다.
    private static func makeSeatProofJWT(
        hwid: String = testHwid,
        seatId: String = "seat-001",
        licenseId: String = "lic-001"
    ) -> String {
        createJWT(
            payload: [
                "iss": "luvotomy",
                "sub": hwid,
                "aud": "noctiluca",
                "iat": Int(Date.now.timeIntervalSince1970),
                "jti": seatId,
                "x-noc-license-id": licenseId,
                "x-noc-seat-label": "Test Mac"
            ],
            privateKey: keyPair.privateKey
        )
    }

    /// 유효한 license key JWT (LicenseJWTClaim)를 생성한다.
    private static func makeLicenseKeyJWT(
        licenseType: String = "personal",
        licensedTo: String = "Test User",
        exp: Int? = nil,
        options: String = ""
    ) -> String {
        var payload: [String: Any] = [
            "iss": "luvotomy",
            "sub": "user@example.com",
            "aud": "noctiluca",
            "iat": Int(Date.now.timeIntervalSince1970),
            "x-noc-license-type": licenseType,
            "x-noc-licensed-to": licensedTo,
            "x-noc-options": options
        ]
        if let exp {
            payload["exp"] = exp
        }
        return createJWT(payload: payload, privateKey: keyPair.privateKey)
    }

    /// 테스트용 LicenseInfo를 Keychain에 저장할 수 있도록 JSON Data로 인코딩한다.
    private static func encodeLicenseInfo(licenseKey: String) -> Data {
        let info = LicenseInfo(name: "Test User", email: "user@example.com", licenseKey: licenseKey)
        return try! JSONEncoder().encode(info)
    }

    // MARK: - SUT Factory

    private func makeSUT(
        keychain: MockLicenseKeychainStore = .init(),
        api: MockLicenseAPIClient = .init(),
        hwid: String? = testHwid,
        publicKeyData: Data? = publicKeyDER
    ) -> (LicenseManager, MockLicenseKeychainStore, MockLicenseAPIClient) {
        let manager = LicenseManager(
            keychainStore: keychain,
            apiClient: api,
            hwidProvider: MockHardwareIdentifierProvider(hwid: hwid),
            hostNameProvider: MockHostNameProvider(name: "Test Mac"),
            publicKeyData: publicKeyData
        )
        return (manager, keychain, api)
    }

    // MARK: - loadLicense() 테스트

    func testLoadLicense_noSeatProof_setsUnlicensed() async {
        let (sut, _, _) = makeSUT()

        await sut.loadLicense()

        let state = await sut.validationState
        XCTAssertEqual(state, .unlicensed)
    }

    func testLoadLicense_noPublicKey_setsUnlicensed() async {
        let keychain = MockLicenseKeychainStore()
        keychain.seatProofData = Self.makeSeatProofJWT().data(using: .utf8)

        let (sut, _, _) = makeSUT(keychain: keychain, publicKeyData: nil)

        await sut.loadLicense()

        let state = await sut.validationState
        XCTAssertEqual(state, .unlicensed)
    }

    func testLoadLicense_validSeatProof_matchingHwid_setsValid() async {
        let keychain = MockLicenseKeychainStore()
        let seatProofJwt = Self.makeSeatProofJWT()
        keychain.seatProofData = seatProofJwt.data(using: .utf8)

        let (sut, _, _) = makeSUT(keychain: keychain)

        await sut.loadLicense()

        let state = await sut.validationState
        XCTAssertEqual(state, .valid)
    }

    func testLoadLicense_hwidMismatch_setsInvalid() async {
        let keychain = MockLicenseKeychainStore()
        keychain.seatProofData = Self.makeSeatProofJWT(hwid: "different-hwid").data(using: .utf8)

        let (sut, _, _) = makeSUT(keychain: keychain)

        await sut.loadLicense()

        let state = await sut.validationState
        XCTAssertEqual(state, .invalid)
    }

    func testLoadLicense_noHwid_setsInvalid() async {
        let keychain = MockLicenseKeychainStore()
        keychain.seatProofData = Self.makeSeatProofJWT().data(using: .utf8)

        let (sut, _, _) = makeSUT(keychain: keychain, hwid: nil)

        await sut.loadLicense()

        let state = await sut.validationState
        XCTAssertEqual(state, .invalid)
    }

    func testLoadLicense_invalidJWT_setsInvalid() async {
        let keychain = MockLicenseKeychainStore()
        // 다른 키로 서명된 JWT
        let otherKeyPair = Self.generateRSAKeyPair()
        let badJwt = Self.createJWT(
            payload: [
                "iss": "luvotomy", "sub": Self.testHwid, "aud": "noctiluca",
                "iat": Int(Date.now.timeIntervalSince1970),
                "jti": "seat-001", "x-noc-license-id": "lic-001"
            ],
            privateKey: otherKeyPair.privateKey
        )
        keychain.seatProofData = badJwt.data(using: .utf8)

        let (sut, _, _) = makeSUT(keychain: keychain)

        await sut.loadLicense()

        let state = await sut.validationState
        XCTAssertEqual(state, .invalid)
    }

    func testLoadLicense_expiredLicense_setsExpired() async {
        let keychain = MockLicenseKeychainStore()
        keychain.seatProofData = Self.makeSeatProofJWT().data(using: .utf8)

        // 만료된 licenseKey JWT
        let expiredLicenseKey = Self.makeLicenseKeyJWT(
            licenseType: "evaluation",
            exp: Int(Date.now.timeIntervalSince1970) - 3600
        )
        keychain.licenseInfoData = Self.encodeLicenseInfo(licenseKey: expiredLicenseKey)

        let (sut, _, _) = makeSUT(keychain: keychain)

        await sut.loadLicense()

        let state = await sut.validationState
        XCTAssertEqual(state, .expired)
    }

    func testLoadLicense_withLicenseInfo_setsLicenseClaim() async {
        let keychain = MockLicenseKeychainStore()
        keychain.seatProofData = Self.makeSeatProofJWT().data(using: .utf8)

        let licenseKey = Self.makeLicenseKeyJWT(licensedTo: "Cheese Kun")
        keychain.licenseInfoData = Self.encodeLicenseInfo(licenseKey: licenseKey)

        let (sut, _, _) = makeSUT(keychain: keychain)

        await sut.loadLicense()

        let claim = await sut.licenseClaim
        XCTAssertNotNil(claim)
        XCTAssertEqual(claim?.licensedTo, "Cheese Kun")
        XCTAssertEqual(claim?.licenseType, "personal")
    }

    // MARK: - performOnlineValidation() 테스트

    /// 온라인 검증을 테스트하려면 먼저 valid 상태로 만들어야 한다
    private func makeSUTInValidState(
        api: MockLicenseAPIClient = .init()
    ) async -> (LicenseManager, MockLicenseKeychainStore, MockLicenseAPIClient) {
        let keychain = MockLicenseKeychainStore()
        keychain.seatProofData = Self.makeSeatProofJWT().data(using: .utf8)

        let licenseKey = Self.makeLicenseKeyJWT()
        keychain.licenseInfoData = Self.encodeLicenseInfo(licenseKey: licenseKey)

        // loadLicense에서 validateLicenseOnline이 호출되지 않도록
        // api의 validateResult를 성공으로 설정
        api.validateResult = .success(ValidateSeatResponse(
            valid: true, reason: nil, seatId: nil,
            hwid: nil, label: nil, licenseId: nil, licenseValid: nil
        ))

        let (sut, _, _) = makeSUT(keychain: keychain, api: api)
        await sut.loadLicense()

        let state = await sut.validationState
        XCTAssertEqual(state, .valid, "precondition: should be valid after loadLicense")

        return (sut, keychain, api)
    }

    func testPerformOnlineValidation_validResponse_keepsValid() async {
        let api = MockLicenseAPIClient()
        let (sut, _, _) = await makeSUTInValidState(api: api)

        // 성공 응답 (makeSUTInValidState가 이미 설정했지만 명시적으로 재설정)
        api.validateResult = .success(ValidateSeatResponse(
            valid: true, reason: nil, seatId: nil,
            hwid: nil, label: nil, licenseId: nil, licenseValid: nil
        ))

        await sut.performOnlineValidation()

        let state = await sut.validationState
        XCTAssertEqual(state, .valid)
    }

    func testPerformOnlineValidation_seatNotFound_setsUnlicensed() async {
        let api = MockLicenseAPIClient()
        let (sut, _, _) = await makeSUTInValidState(api: api)

        // loadLicense 이후에 결과를 seat_not_found로 변경
        api.validateResult = .success(ValidateSeatResponse(
            valid: false, reason: "seat_not_found", seatId: nil,
            hwid: nil, label: nil, licenseId: nil, licenseValid: nil
        ))

        await sut.performOnlineValidation()

        let state = await sut.validationState
        XCTAssertEqual(state, .unlicensed)
    }

    func testPerformOnlineValidation_invalidReason_setsInvalid() async {
        let api = MockLicenseAPIClient()
        let (sut, _, _) = await makeSUTInValidState(api: api)

        // loadLicense 이후에 결과를 invalid reason으로 변경
        api.validateResult = .success(ValidateSeatResponse(
            valid: false, reason: "license_revoked", seatId: nil,
            hwid: nil, label: nil, licenseId: nil, licenseValid: nil
        ))

        await sut.performOnlineValidation()

        let state = await sut.validationState
        XCTAssertEqual(state, .invalid)
    }

    func testPerformOnlineValidation_serverError5xx_keepsValid() async {
        let api = MockLicenseAPIClient()
        let (sut, _, _) = await makeSUTInValidState(api: api)

        // 5xx 에러 주입
        api.validateResult = .failure(LicenseAPIClientError.serverError(statusCode: 503, detail: "Service Unavailable"))

        await sut.performOnlineValidation()

        let state = await sut.validationState
        XCTAssertEqual(state, .valid)
    }

    func testPerformOnlineValidation_networkError_keepsValid() async {
        let api = MockLicenseAPIClient()
        let (sut, _, _) = await makeSUTInValidState(api: api)

        // 네트워크 에러 주입
        api.validateResult = .failure(LicenseAPIClientError.networkError(.explicitlyCancelled))

        await sut.performOnlineValidation()

        let state = await sut.validationState
        XCTAssertEqual(state, .valid)
    }

    func testPerformOnlineValidation_clientError4xx_setsInvalid() async {
        let api = MockLicenseAPIClient()
        let (sut, _, _) = await makeSUTInValidState(api: api)

        // 4xx 에러 주입
        api.validateResult = .failure(LicenseAPIClientError.serverError(statusCode: 403, detail: "Forbidden"))

        await sut.performOnlineValidation()

        let state = await sut.validationState
        XCTAssertEqual(state, .invalid)
    }

    // MARK: - installLicense() 테스트

    func testInstallLicense_whenValid_throwsInvalidState() async {
        let (sut, _, _) = await makeSUTInValidState()

        do {
            try await sut.installLicense(LicenseInfo(name: "Test", email: "t@t.com", licenseKey: "key"))
            XCTFail("Expected invalidState error")
        } catch let error as LicenseManagerError {
            if case .invalidState = error {} else {
                XCTFail("Expected .invalidState, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testInstallLicense_noHwid_throwsNoHardwareIdentifier() async throws {
        let (sut, _, _) = makeSUT(hwid: nil)
        await sut.loadLicense() // nil → .unlicensed

        do {
            try await sut.installLicense(LicenseInfo(name: "Test", email: "t@t.com", licenseKey: "key"))
            XCTFail("Expected noHardwareIdentifier error")
        } catch let error as LicenseManagerError {
            if case .noHardwareIdentifier = error {} else {
                XCTFail("Expected .noHardwareIdentifier, got \(error)")
            }
        }
    }

    func testInstallLicense_success_savesSeatProofAndSetsValid() async throws {
        let keychain = MockLicenseKeychainStore()
        let api = MockLicenseAPIClient()

        let seatProofJwt = Self.makeSeatProofJWT()
        api.activateResult = .success(ActivateLicenseResponse(seatId: "seat-001", seatProof: seatProofJwt))

        let (sut, _, _) = makeSUT(keychain: keychain, api: api)
        await sut.loadLicense() // nil → .unlicensed

        let licenseInfo = LicenseInfo(name: "Test", email: "t@t.com", licenseKey: Self.makeLicenseKeyJWT())
        try await sut.installLicense(licenseInfo)

        let state = await sut.validationState
        XCTAssertEqual(state, .valid)

        // Keychain에 저장됐는지 확인
        XCTAssertNotNil(keychain.seatProofData)
        XCTAssertNotNil(keychain.licenseInfoData)

        // API가 올바른 인수로 호출됐는지 확인
        XCTAssertEqual(api.activateCalls.count, 1)
        XCTAssertEqual(api.activateCalls.first?.hwid, Self.testHwid)
        XCTAssertEqual(api.activateCalls.first?.label, "Test Mac")
    }

    func testInstallLicense_apiError_throwsInstallationFailed() async {
        let api = MockLicenseAPIClient()
        api.activateResult = .failure(LicenseAPIClientError.serverError(statusCode: 400, detail: "Invalid key"))

        let (sut, _, _) = makeSUT(api: api)
        await sut.loadLicense() // nil → .unlicensed

        do {
            try await sut.installLicense(LicenseInfo(name: "Test", email: "t@t.com", licenseKey: "key"))
            XCTFail("Expected installationFailed error")
        } catch let error as LicenseManagerError {
            if case .installationFailed = error {} else {
                XCTFail("Expected .installationFailed, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testInstallLicense_keychainSaveError_throwsInstallationFailed() async {
        let keychain = MockLicenseKeychainStore()

        let api = MockLicenseAPIClient()
        let seatProofJwt = Self.makeSeatProofJWT()
        api.activateResult = .success(ActivateLicenseResponse(seatId: "seat-001", seatProof: seatProofJwt))

        let (sut, _, _) = makeSUT(keychain: keychain, api: api)
        await sut.loadLicense() // nil → .unlicensed

        // loadLicense 이후에 setError를 주입 (loadLicense 중 keychain 읽기에 영향 안 주기 위해)
        keychain.setError = .unexpectedStatus(-25300)

        do {
            try await sut.installLicense(LicenseInfo(name: "Test", email: "t@t.com", licenseKey: "key"))
            XCTFail("Expected installationFailed error")
        } catch let error as LicenseManagerError {
            if case .installationFailed = error {} else {
                XCTFail("Expected .installationFailed, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testInstallLicense_success_setsLicenseClaim() async throws {
        let api = MockLicenseAPIClient()
        let seatProofJwt = Self.makeSeatProofJWT()
        api.activateResult = .success(ActivateLicenseResponse(seatId: "seat-001", seatProof: seatProofJwt))

        let (sut, _, _) = makeSUT(api: api)
        await sut.loadLicense() // nil → .unlicensed

        let licenseKey = Self.makeLicenseKeyJWT(licensedTo: "Premium User")
        try await sut.installLicense(LicenseInfo(name: "Premium User", email: "p@t.com", licenseKey: licenseKey))

        let claim = await sut.licenseClaim
        XCTAssertNotNil(claim)
        XCTAssertEqual(claim?.licensedTo, "Premium User")
    }

    func testInstallLicense_whenUnlicensed_succeeds() async throws {
        let api = MockLicenseAPIClient()
        let seatProofJwt = Self.makeSeatProofJWT()
        api.activateResult = .success(ActivateLicenseResponse(seatId: "seat-001", seatProof: seatProofJwt))

        let (sut, _, _) = makeSUT(api: api)

        // 초기 상태는 nil이므로 unlicensed로 전환 먼저
        await sut.loadLicense() // publicKey 있지만 keychain 비어있으므로 .unlicensed

        let stateBefore = await sut.validationState
        XCTAssertEqual(stateBefore, .unlicensed)

        try await sut.installLicense(LicenseInfo(name: "Test", email: "t@t.com", licenseKey: Self.makeLicenseKeyJWT()))

        let stateAfter = await sut.validationState
        XCTAssertEqual(stateAfter, .valid)
    }

    // MARK: - installTrialLicense() 테스트

    func testInstallTrialLicense_whenValid_throwsInvalidState() async {
        let (sut, _, _) = await makeSUTInValidState()

        do {
            try await sut.installTrialLicense(
                name: "Test", email: "t@t.com",
                licenseKey: "key", seatProof: "proof"
            )
            XCTFail("Expected invalidState error")
        } catch let error as LicenseManagerError {
            if case .invalidState = error {} else {
                XCTFail("Expected .invalidState, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testInstallTrialLicense_success_savesSeatProofAndSetsValid() async throws {
        let keychain = MockLicenseKeychainStore()
        let (sut, _, _) = makeSUT(keychain: keychain)

        // unlicensed로 전환
        await sut.loadLicense()

        let seatProofJwt = Self.makeSeatProofJWT()
        let licenseKey = Self.makeLicenseKeyJWT(licenseType: "evaluation")

        try await sut.installTrialLicense(
            name: "Trial User", email: "trial@t.com",
            licenseKey: licenseKey, seatProof: seatProofJwt
        )

        let state = await sut.validationState
        XCTAssertEqual(state, .valid)
        XCTAssertNotNil(keychain.seatProofData)
        XCTAssertNotNil(keychain.licenseInfoData)
    }

    func testInstallTrialLicense_success_setsLicenseClaim() async throws {
        let (sut, _, _) = makeSUT()
        await sut.loadLicense()

        let seatProofJwt = Self.makeSeatProofJWT()
        let licenseKey = Self.makeLicenseKeyJWT(licenseType: "evaluation", licensedTo: "Trial User")

        try await sut.installTrialLicense(
            name: "Trial User", email: "trial@t.com",
            licenseKey: licenseKey, seatProof: seatProofJwt
        )

        let claim = await sut.licenseClaim
        XCTAssertNotNil(claim)
        XCTAssertEqual(claim?.isEvaluation, true)
        XCTAssertEqual(claim?.licensedTo, "Trial User")
    }

    func testInstallTrialLicense_keychainSaveError_throwsInstallationFailed() async {
        let keychain = MockLicenseKeychainStore()
        keychain.setError = .unexpectedStatus(-25300)
        let (sut, _, _) = makeSUT(keychain: keychain)
        await sut.loadLicense()

        do {
            try await sut.installTrialLicense(
                name: "Test", email: "t@t.com",
                licenseKey: "key", seatProof: Self.makeSeatProofJWT()
            )
            XCTFail("Expected installationFailed error")
        } catch let error as LicenseManagerError {
            if case .installationFailed = error {} else {
                XCTFail("Expected .installationFailed, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - removeLicense() 테스트

    func testRemoveLicense_whenUnlicensed_throwsInvalidState() async {
        let (sut, _, _) = makeSUT()
        await sut.loadLicense() // .unlicensed

        do {
            try await sut.removeLicense()
            XCTFail("Expected invalidState error")
        } catch let error as LicenseManagerError {
            if case .invalidState = error {} else {
                XCTFail("Expected .invalidState, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRemoveLicense_success_clearsKeychainAndSetsUnlicensed() async throws {
        let api = MockLicenseAPIClient()
        let (sut, keychain, _) = await makeSUTInValidState(api: api)

        try await sut.removeLicense()

        let state = await sut.validationState
        XCTAssertEqual(state, .unlicensed)
        XCTAssertNil(keychain.seatProofData)
        XCTAssertNil(keychain.licenseInfoData)
    }

    func testRemoveLicense_clearsAllState() async throws {
        let api = MockLicenseAPIClient()
        let (sut, _, _) = await makeSUTInValidState(api: api)

        try await sut.removeLicense()

        let claim = await sut.licenseClaim
        XCTAssertNil(claim)

        let isLicensed = await sut.isLicensed
        XCTAssertFalse(isLicensed)
    }

    func testRemoveLicense_revokeApiError_stillRemovesLocally() async throws {
        let api = MockLicenseAPIClient()
        let (sut, keychain, _) = await makeSUTInValidState(api: api)

        // revoke 에러 주입
        api.revokeError = LicenseAPIClientError.serverError(statusCode: 500, detail: "Internal Server Error")

        try await sut.removeLicense()

        let state = await sut.validationState
        XCTAssertEqual(state, .unlicensed)
        XCTAssertNil(keychain.seatProofData)
    }

    func testRemoveLicense_callsRevokeWithCorrectSeatId() async throws {
        let api = MockLicenseAPIClient()
        api.validateResult = .success(ValidateSeatResponse(
            valid: true, reason: nil, seatId: nil,
            hwid: nil, label: nil, licenseId: nil, licenseValid: nil
        ))

        let keychain = MockLicenseKeychainStore()
        let seatProofJwt = Self.makeSeatProofJWT(seatId: "my-seat-42")
        keychain.seatProofData = seatProofJwt.data(using: .utf8)

        let licenseKey = Self.makeLicenseKeyJWT()
        keychain.licenseInfoData = Self.encodeLicenseInfo(licenseKey: licenseKey)

        let (sut, _, _) = makeSUT(keychain: keychain, api: api)
        await sut.loadLicense()

        try await sut.removeLicense()

        XCTAssertEqual(api.revokeCalls.count, 1)
        XCTAssertEqual(api.revokeCalls.first?.seatId, "my-seat-42")
    }

    // MARK: - isLicensed 프로퍼티 테스트

    func testIsLicensed_whenValid_returnsTrue() async {
        let (sut, _, _) = await makeSUTInValidState()

        let result = await sut.isLicensed
        XCTAssertTrue(result)
    }

    func testIsLicensed_whenUnlicensed_returnsFalse() async {
        let (sut, _, _) = makeSUT()
        await sut.loadLicense()

        let result = await sut.isLicensed
        XCTAssertFalse(result)
    }

    func testIsLicensed_whenInvalid_returnsFalse() async {
        let keychain = MockLicenseKeychainStore()
        // 다른 키로 서명된 JWT → invalid
        let otherKeyPair = Self.generateRSAKeyPair()
        let badJwt = Self.createJWT(
            payload: [
                "iss": "luvotomy", "sub": Self.testHwid, "aud": "noctiluca",
                "iat": Int(Date.now.timeIntervalSince1970),
                "jti": "seat-001", "x-noc-license-id": "lic-001"
            ],
            privateKey: otherKeyPair.privateKey
        )
        keychain.seatProofData = badJwt.data(using: .utf8)

        let (sut, _, _) = makeSUT(keychain: keychain)
        await sut.loadLicense()

        let result = await sut.isLicensed
        XCTAssertFalse(result)
    }

    func testIsLicensed_whenExpired_returnsFalse() async {
        let keychain = MockLicenseKeychainStore()
        keychain.seatProofData = Self.makeSeatProofJWT().data(using: .utf8)

        let expiredKey = Self.makeLicenseKeyJWT(
            licenseType: "evaluation",
            exp: Int(Date.now.timeIntervalSince1970) - 3600
        )
        keychain.licenseInfoData = Self.encodeLicenseInfo(licenseKey: expiredKey)

        let (sut, _, _) = makeSUT(keychain: keychain)
        await sut.loadLicense()

        let result = await sut.isLicensed
        XCTAssertFalse(result)
    }

    func testIsLicensed_whenNil_returnsFalse() async {
        let (sut, _, _) = makeSUT()

        let result = await sut.isLicensed
        XCTAssertFalse(result)
    }
}

// MARK: - LicenseValidationState Equatable

extension LicenseValidationState: @retroactive Equatable {}
