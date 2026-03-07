//
//  LicenseManager.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 3/6/26.
//

import Foundation

import SiriusKit

enum LicenseType {
    /// 평가용 라이선스
    case evaluation

    /// 개인용 라이선스
    case personal
}

enum LicenseValidationState {
    /// 라이선스가 등록되지 않았습니다.
    case unlicensed

    /// 라이선스가 이 컴퓨터에 등록되어 있지만, 올바르지 않은 것으로 보입니다.
    case invalid

    /// 라이선스가 만료되었습니다.
    case expired

    /// 라이선스가 이 컴퓨터에 등록되어 있고, 올바른 라이선스로 확인되었습니다.
    case valid
}


@_silgen_name("AAAA__please_dont_disassemble_this_app_im_begging_you__")
@inline(never)
func pleaseDontDisassembleThisAppImBeggingYou(
    _ a: UnsafePointer<CChar>,
    _ b: UnsafePointer<CChar>,
    _ c: UnsafePointer<CChar>
) {
    _ = a.hashValue
    _ = b.hashValue
    _ = c.hashValue
}

struct LicenseInfo: Codable {
    let name: String
    let email: String
    let licenseKey: String
}

struct LicenseJWTClaim: Decodable {
    let iss: String
    let sub: String
    let aud: String
    let iat: Int
    let nbf: Int?
    /// personal인 경우 신경쓰지 않는다 (2099-12-31 쯤으로 되어있음)
    let exp: Int?
    /// personal, enterprise, evaluation
    let licenseType: String
    let licensedTo: String
    let metadataJson: String?
    let options: String
    
    var remainingDays: Int? {
        guard let exp else { return nil }
        let expDate = Date(timeIntervalSince1970: TimeInterval(exp))
        return Calendar.current.dateComponents([.day], from: .now, to: expDate).day
    }

    var isEvaluation: Bool { licenseType == "evaluation" }

    var isExpired: Bool {
        guard let exp else { return false }
        let expDate = Date(timeIntervalSince1970: TimeInterval(exp))
        return expDate < Date.now
    }

    enum CodingKeys: String, CodingKey {
        case iss, sub, aud, iat, nbf, exp
        case licenseType = "x-noc-license-type"
        case licensedTo = "x-noc-licensed-to"
        case metadataJson = "x-noc-metadata"
        case options = "x-noc-options"
    }
}

/// 라이선스의 시트 할당 증명.
struct LicenseSeatProof: Decodable {
    let iss: String
    let sub: String
    let aud: String
    let iat: Int
    let jti: String
    let licenseId: String
    let seatLabel: String?

    /// `sub` 클레임이 곧 hwid
    var hwid: String { sub }

    enum CodingKeys: String, CodingKey {
        case iss, sub, aud, iat, jti
        case licenseId = "x-noc-license-id"
        case seatLabel = "x-noc-seat-label"
    }
}

extension Notification.Name {
    static let licenseValidationStateDidChange = Notification.Name("app.noctiluca.server.licenseValidationStateDidChange")
}

enum LicenseManagerError: Error {
    /// 현재 상태에서 이 동작은 허용되지 않습니다
    case invalidState

    /// 하드웨어 식별자를 취득할 수 없었습니다
    case noHardwareIdentifier

    /// 라이선스 설치에 실패하였습니다.
    case installationFailed(Error?)
}

/// Noctiluca Server의 라이선스 상황을 관리합니다.
actor LicenseManager {
    static let shared = LicenseManager()

    private static let keychainSeatProofKey = "app.noctiluca.server.installed_license"
    private static let keychainLicenseInfoKey = "app.noctiluca.server.license_info"

    private let logger = NoctilucaLogger(category: "LicenseManager")
    private let apiClient = LicenseAPIClient()

    private var seatProof: LicenseSeatProof?
    private var seatProofJwt: String?

    private(set) var licenseClaim: LicenseJWTClaim?

    private(set) var validationState: LicenseValidationState? {
        didSet {
            guard validationState != oldValue else { return }

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .licenseValidationStateDidChange, object: nil)

                if self.validationState == .invalid {
                    Task {
                        try? await Task.sleep(for: .seconds(5))
                        await AppNotification.invalidLicense.post()
                    }
                }

                if self.validationState == .expired {
                    Task {
                        try? await Task.sleep(for: .seconds(5))
                        await AppNotification.licenseExpired.post()
                    }
                }
            }
        }
    }

    var isLicensed: Bool { validationState == .valid }

    // MARK: - Load

    func loadLicense() async {
        let seatProofJwtResult = SRKeychain.shared.getSecureData(key: Self.keychainSeatProofKey)

        guard let publicKey = LuvotomyKey.publicKey,
              let jwtDecoder = try? JWTDecoder(publicKey),
              let seatProofJwt = try? seatProofJwtResult.get(),
              let seatProofJwtString = String(data: seatProofJwt, encoding: .utf8)
        else {
            validationState = .unlicensed
            return
        }

        guard let seatProof = try? jwtDecoder.decode(seatProofJwtString, as: LicenseSeatProof.self).get() else {
            validationState = .invalid
            return
        }

        self.seatProof = seatProof
        self.seatProofJwt = seatProofJwtString

        if let licenseInfo = loadLicenseInfo() {
            self.licenseClaim = try? jwtDecoder.decode(
                licenseInfo.licenseKey,
                as: LicenseJWTClaim.self,
                skipExpirationCheck: true
            ).get()
        }

        guard let hardwareIdentifier = SystemCapability.hardwareIdentifier(),
              seatProof.hwid == hardwareIdentifier
        else {
            validationState = .invalid
            return
        }

        if let claim = licenseClaim, claim.isExpired {
            validationState = .expired
            return
        }

        validationState = .valid
        await validateLicenseOnline()
    }

    // MARK: - Online Validation

    /// Noctiluca의 라이선스 서버를 통해 라이선스를 추가로 검증받는다
    func validateLicenseOnline() async {
        guard let seatProofJwt = self.seatProofJwt else { return }

        // 운을 시험한다
        let randomValue = Int.random(in: 1..<10)
        guard randomValue % 2 != 0 else {
            // 운이 좋군! 이번엔 봐주도록 하지.
            return
        }

        do {
            let result = try await apiClient.validateSeat(seatProof: seatProofJwt)

            if result.valid {
                logger.info("Online license validation succeeded")
            } else {
                if result.reason == "seat_not_found" {
                    logger.warning("Online license validation failed: seat not found (possibly revoked or invalidated)")
                    
                    // uninstall license
                    _ = try? await removeLicense()
                    validationState = .unlicensed
                } else {
                    logger.warning("Online license validation failed: \(result.reason ?? "unknown")")
                    validationState = .invalid
                }
            }
        } catch let error as LicenseAPIClientError {
            switch error {
            case .serverError(let statusCode, _) where statusCode >= 500:
                // 서버 장애 시 관대하게 처리
                logger.warning("License server returned \(statusCode), keeping offline validation state")
            case .networkError:
                // 네트워크 장애 시 관대하게 처리
                logger.info("Cannot reach license server, keeping offline validation state")
            case .serverError(let statusCode, let detail):
                // 4xx: 명확한 검증 실패
                logger.warning("License validation rejected: \(statusCode) - \(detail ?? "")")
                validationState = .invalid
            }
        } catch {
            logger.warning("Unexpected error during online validation: \(error)")
        }
    }

    // MARK: - Install

    /// 라이선스를 설치합니다.
    func installLicense(_ licenseInfo: LicenseInfo) async throws {
        guard validationState == .unlicensed || validationState == .invalid || validationState == .expired else {
            throw LicenseManagerError.invalidState
        }

        guard let hardwareIdentifier = SystemCapability.hardwareIdentifier() else {
            throw LicenseManagerError.noHardwareIdentifier
        }

        do {
            let response = try await apiClient.activate(
                licenseInfo: licenseInfo,
                hwid: hardwareIdentifier,
                label: Host.current().localizedName ?? "Mac"
            )

            // Seat proof JWT를 Keychain에 저장
            guard let seatProofData = response.seatProof.data(using: .utf8) else {
                throw LicenseManagerError.installationFailed(nil)
            }

            let keychainResult = SRKeychain.shared.setSecureData(seatProofData, key: Self.keychainSeatProofKey)
            if case .failure(let error) = keychainResult {
                throw LicenseManagerError.installationFailed(error)
            }

            // 라이선스 정보(name/email/key)도 저장 (revoke 시 인증 헤더에 필요)
            let infoData = try JSONEncoder().encode(licenseInfo)
            _ = SRKeychain.shared.setSecureData(infoData, key: Self.keychainLicenseInfoKey)

            // 로컬 상태 갱신
            guard let publicKey = LuvotomyKey.publicKey,
                  let jwtDecoder = try? JWTDecoder(publicKey),
                  let proof = try? jwtDecoder.decode(response.seatProof, as: LicenseSeatProof.self).get()
            else {
                // JWT 디코딩 실패해도 Keychain에는 이미 저장됨 — 다음 loadLicense()에서 복구 가능
                validationState = .valid
                return
            }

            self.seatProof = proof
            self.seatProofJwt = response.seatProof
            self.licenseClaim = try? jwtDecoder.decode(licenseInfo.licenseKey, as: LicenseJWTClaim.self).get()
            validationState = .valid

            logger.info("License installed successfully (seat: \(response.seatId))")
            startPeriodicExpirationCheck()
        } catch let error as LicenseAPIClientError {
            logger.error("License activation failed: \(error)")
            throw LicenseManagerError.installationFailed(error)
        }
    }

    // MARK: - Install (Trial)

    /// 체험판 발급 결과를 로컬에 설치합니다.
    func installTrialLicense(name: String, email: String, licenseKey: String, seatProof seatProofJwt: String) async throws {
        guard validationState == .unlicensed || validationState == .invalid || validationState == .expired else {
            throw LicenseManagerError.invalidState
        }

        // Seat proof JWT를 Keychain에 저장
        guard let seatProofData = seatProofJwt.data(using: .utf8) else {
            throw LicenseManagerError.installationFailed(nil)
        }

        let keychainResult = SRKeychain.shared.setSecureData(seatProofData, key: Self.keychainSeatProofKey)
        if case .failure(let error) = keychainResult {
            throw LicenseManagerError.installationFailed(error)
        }

        // 라이선스 정보 저장
        let licenseInfo = LicenseInfo(name: name, email: email, licenseKey: licenseKey)
        let infoData = try JSONEncoder().encode(licenseInfo)
        _ = SRKeychain.shared.setSecureData(infoData, key: Self.keychainLicenseInfoKey)

        // 로컬 상태 갱신
        if let publicKey = LuvotomyKey.publicKey,
           let jwtDecoder = try? JWTDecoder(publicKey),
           let proof = try? jwtDecoder.decode(seatProofJwt, as: LicenseSeatProof.self).get()
        {
            self.seatProof = proof
            self.seatProofJwt = seatProofJwt
            self.licenseClaim = try? jwtDecoder.decode(licenseKey, as: LicenseJWTClaim.self).get()
        }

        validationState = .valid
        logger.info("Trial license installed successfully")
        startPeriodicExpirationCheck()
    }

    // MARK: - Remove

    /// 라이선스를 제거합니다.
    func removeLicense() async throws {
        guard validationState != .unlicensed else {
            throw LicenseManagerError.invalidState
        }

        // 서버에 시트 해제 시도 (실패해도 로컬 제거는 진행)
        if let seatProof = self.seatProof, let licenseInfo = loadLicenseInfo() {
            do {
                try await apiClient.revokeSeat(licenseInfo: licenseInfo, seatId: seatProof.jti)
                logger.info("Seat revoked on server successfully")
            } catch {
                logger.warning("Failed to revoke seat on server (proceeding with local removal): \(error)")
            }
        }

        stopPeriodicExpirationCheck()

        // Keychain에서 제거
        _ = SRKeychain.shared.removeSecureData(key: Self.keychainSeatProofKey)
        _ = SRKeychain.shared.removeSecureData(key: Self.keychainLicenseInfoKey)

        // 로컬 상태 초기화
        self.seatProof = nil
        self.seatProofJwt = nil
        self.licenseClaim = nil
        validationState = .unlicensed

        logger.info("License removed locally")
    }

    // MARK: - Periodic Expiration Check

    private var expirationCheckTask: Task<Void, Never>?

    /// 체험판 라이선스의 주기적 만료 확인을 시작합니다.
    func startPeriodicExpirationCheck() {
        expirationCheckTask?.cancel()

        guard let claim = licenseClaim, claim.isEvaluation else {
            return
        }

        expirationCheckTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6 * 60 * 60))
                guard !Task.isCancelled else { break }

                guard let claim = self.licenseClaim else { break }

                if claim.isExpired {
                    if self.validationState == .valid {
                        self.validationState = .expired
                    }
                    break
                }

                if let remaining = claim.remainingDays, remaining <= 3, remaining > 0 {
                    await AppNotification.licenseExpiringSoon(remainingDays: remaining).post()
                }
            }
        }
    }

    func stopPeriodicExpirationCheck() {
        expirationCheckTask?.cancel()
        expirationCheckTask = nil
    }

    // MARK: - Private

    private func loadLicenseInfo() -> LicenseInfo? {
        guard let data = try? SRKeychain.shared.getSecureData(key: Self.keychainLicenseInfoKey).get(),
              let info = try? JSONDecoder().decode(LicenseInfo.self, from: data)
        else {
            return nil
        }
        return info
    }
}
