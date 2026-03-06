//
//  LicenseAPIClient.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 3/6/26.
//

import Foundation

import Alamofire

// MARK: - Response Models

struct ActivateLicenseResponse: Decodable {
    let seatId: String
    let seatProof: String

    enum CodingKeys: String, CodingKey {
        case seatId = "seat_id"
        case seatProof = "seat_proof"
    }
}

struct ValidateSeatResponse: Decodable {
    let valid: Bool
    let reason: String?
    let seatId: String?
    let hwid: String?
    let label: String?
    let licenseId: String?
    let licenseValid: Bool?

    enum CodingKeys: String, CodingKey {
        case valid, reason, hwid, label
        case seatId = "seat_id"
        case licenseId = "license_id"
        case licenseValid = "license_valid"
    }
}

// MARK: - Error

enum LicenseAPIClientError: Error {
    case networkError(AFError)
    case serverError(statusCode: Int, detail: String?)
}

private struct APIErrorResponse: Decodable {
    let detail: String?
}

// MARK: - LicenseAPIClient

actor LicenseAPIClient {
#if DEBUG
    private static let baseURL = "http://localhost:8000/api/v1"
#else
    private static let baseURL = "https://luvotomy.noctiluca.app/api/v1"
#endif

    private let logger = NoctilucaLogger(category: "LicenseAPIClient")

    private func authHeaders(for licenseInfo: LicenseInfo) -> HTTPHeaders {
        [
            "Authorization": "LicenseKey \(licenseInfo.licenseKey)",
            "X-License-Name": licenseInfo.name,
            "X-License-Email": licenseInfo.email,
        ]
    }

    /// 라이선스 활성화 (시트 할당)
    func activate(licenseInfo: LicenseInfo, hwid: String, label: String) async throws -> ActivateLicenseResponse {
        let parameters: [String: String] = [
            "hwid": hwid,
            "label": label,
        ]

        let response = await AF.request(
            "\(Self.baseURL)/license/activate/",
            method: .post,
            parameters: parameters,
            encoder: JSONParameterEncoder.default,
            headers: authHeaders(for: licenseInfo)
        )
        .serializingDecodable(ActivateLicenseResponse.self)
        .response

        switch response.result {
        case .success(let value):
            return value
        case .failure(let error):
            throw mapError(afError: error, response: response.response, data: response.data)
        }
    }

    /// 시트 할당 증명 검증 (인증 불필요)
    func validateSeat(seatProof: String) async throws -> ValidateSeatResponse {
        let parameters: [String: String] = [
            "seat_proof": seatProof,
        ]

        let response = await AF.request(
            "\(Self.baseURL)/license/seats/validate/",
            method: .post,
            parameters: parameters,
            encoder: JSONParameterEncoder.default
        )
        .serializingDecodable(ValidateSeatResponse.self)
        .response

        switch response.result {
        case .success(let value):
            return value
        case .failure(let error):
            throw mapError(afError: error, response: response.response, data: response.data)
        }
    }

    /// 시트 해제
    func revokeSeat(licenseInfo: LicenseInfo, seatId: String) async throws {
        let parameters: [String: String] = [
            "seat_id": seatId,
        ]

        let response = await AF.request(
            "\(Self.baseURL)/license/revoke-seat/",
            method: .post,
            parameters: parameters,
            encoder: JSONParameterEncoder.default,
            headers: authHeaders(for: licenseInfo)
        )
        .serializingData()
        .response

        if let statusCode = response.response?.statusCode, (200..<300).contains(statusCode) {
            return
        }

        if let error = response.error {
            throw mapError(afError: error, response: response.response, data: response.data)
        }
    }

    private func mapError(afError: AFError, response: HTTPURLResponse?, data: Data?) -> LicenseAPIClientError {
        if let statusCode = response?.statusCode,
           let data = data,
           let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
            return .serverError(statusCode: statusCode, detail: apiError.detail)
        }
        return .networkError(afError)
    }
}
