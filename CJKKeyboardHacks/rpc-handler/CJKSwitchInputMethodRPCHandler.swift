//
//  CJKSwitchInputMethodRPCHandler.swift
//  CJKKeyboardHacks
//
//  Created by Gyuhwan Park on 5/18/26.
//

import Foundation
import NoctilucaPluginKit

/// `app.noctiluca.rpc.switch-im` 오퍼레이션 핸들러.
///
/// 클라이언트(navigator) 가 자신의 입력 언어 변경을 호스트에 통보하면, 호스트는
/// 이 오퍼레이션을 받아 해당 언어에 상응하는 IM 으로 전환한다.
/// (AppStream quirk `app.noctiluca.appstream.quirks.sync_im_state` 에 대응)
///
/// 인자 규약:
///   - `args[0]`: BCP-47 언어 태그. `en`, `ko`, `ja`, `zh-Hans`, `zh-Hant` 등.
///     `Locale.Language(identifier:)` 가 인식 가능한 형식만 허용한다 — 비표준
///     약어(`abc`, `kor`, `chs` 등) 는 받지 않는다.
///   - `args[1]` (optional): `"prefer-third-party"` 또는 `"prefer-first-party"`.
///     생략 시 first-party 우선.
///
/// 응답 규약:
///   - 성공: `.success`, `retval = <BCP-47 정규형 (minimalIdentifier)>`.
///   - 인자 누락 / 알 수 없는 언어 코드: `.invalidArgs`.
///   - 매칭되는 IM 이 없거나 TIS 호출 실패: `.internalError`.
final class CJKSwitchInputMethodRPCHandler: RPCHandlerPluginV1 {
    static let id: String =
        "app.noctiluca.rpchandler.cjk.switch_im"

    static let supportedOperations: Set<String> = [
        "app.noctiluca.rpc.switch-im"
    ]

    required init() {}

    func onRPCRequest(operation: String, args: [String]) async throws -> RPCResult {
        guard Self.supportedOperations.contains(operation) else {
            return .failure(.notSupported)
        }

        guard let rawLanguageTag = args.first else {
            return .failure(.invalidArgs)
        }
        let trimmed = rawLanguageTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(.invalidArgs)
        }
        let language = Locale.Language(identifier: trimmed)
        guard let code = language.languageCode, code != .unidentified else {
            return .failure(.invalidArgs)
        }

        let preferThirdParty: Bool
        if args.count >= 2 {
            switch args[1].lowercased() {
            case "prefer-third-party":
                preferThirdParty = true
            case "prefer-first-party", "":
                preferThirdParty = false
            default:
                return .failure(.invalidArgs)
            }
        } else {
            preferThirdParty = false
        }

        let success = await CJKInputMethodManager.shared.switchInputMethod(
            matching: language,
            preferThirdParty: preferThirdParty
        )
        guard success else {
            return .failure(.internalError)
        }

        return .success(language.minimalIdentifier)
    }
}
