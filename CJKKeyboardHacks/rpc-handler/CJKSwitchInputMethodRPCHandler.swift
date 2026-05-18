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
///   - `args[0]`: BCP-47 단순화 언어 토큰. `en` / `ko` / `ja` / `zh-Hans` / `zh-Hant`
///     및 자주 쓰이는 별칭(`abc`, `zh-CN`, `kor` 등). 자세한 매핑은
///     `CJKInputMethodManager.LanguageToken.init(token:)` 참조.
///   - `args[1]` (optional): `"prefer-third-party"` 또는 `"prefer-first-party"`.
///     생략 시 first-party 우선.
///
/// 응답 규약:
///   - 성공: `.success`, `retval = <전환된 언어 토큰의 정규형>`.
///   - 인자 누락 / 알 수 없는 토큰: `.invalidArgs`.
///   - 매칭되는 IM 이 없거나 TIS 호출 실패: `.internalError`.
final class CJKSwitchInputMethodRPCHandler: RPCHandlerPluginV1 {
    static let id: String =
        "app.noctiluca.rpchandler.cjk.switch_im"

    static let supportedOperations: Set<String> = [
        "app.noctiluca.rpc.switch-im"
    ]

    required init() {}

    func onRPCRequest(request: any RPCRequest) async throws -> any RPCResponse {
        guard Self.supportedOperations.contains(request.operation) else {
            return request.resolve(with: .notSupported)
        }

        guard let rawLanguageToken = request.args.first,
              let language = CJKInputMethodManager.LanguageToken(token: rawLanguageToken) else {
            return request.resolve(with: .invalidArgs)
        }

        let preferThirdParty: Bool
        if request.args.count >= 2 {
            switch request.args[1].lowercased() {
            case "prefer-third-party":
                preferThirdParty = true
            case "prefer-first-party", "":
                preferThirdParty = false
            default:
                return request.resolve(with: .invalidArgs)
            }
        } else {
            preferThirdParty = false
        }

        let success = await CJKInputMethodManager.shared.switchInputMethod(
            to: language,
            preferThirdParty: preferThirdParty
        )
        guard success else {
            return request.resolve(with: .internalError)
        }

        return request.resolve(with: .success, retval: language.rawValue)
    }
}
