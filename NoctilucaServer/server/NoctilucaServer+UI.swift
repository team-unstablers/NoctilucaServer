//
//  NoctilucaServer+UI.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 3/12/26.
//

import Foundation

import SiriusKit

extension NoctilucaServer {
    
    func handleError(identityLoadError error: QUICServerIdentityLoadError) async {
        let isAutoconfEnabled = self.settings.quicTransport.tlsUseAutoconf
        let identitySource = self.settings.quicTransport.identity
        var identityName = switch identitySource {
        case .keychain(let label):
            label
        case .pemFile(let certFilePath, _):
            certFilePath
        default:
            "(unknown)"
        }
        
        let alert = NOCAlert()
        
        let performAutoconfInner = {
            self.settings.quicTransport.tlsUseAutoconf = false
            self.settings.quicTransport.identity = nil
            // autoconf 강제 호출
            self.settings.quicTransport.tlsUseAutoconf = true
            
            try? self.settings.save()
            
            Task.detached {
                // 서버 재시작
                try? await self.shutdown()
                try? await self.startup()
            }
        }
        
        switch error {
        case .conflictingIdentitiesFound:
            alert.title = String(localized: "server.identity_error.conflicting.title", defaultValue: "중복된 이름의 서버 인증서 발견됨")
            // 꼭 소스가 Keychain일거란 보장은 없다. 하지만 지금은 Keychain에서만 로드한다.
            alert.message = String(localized: "server.identity_error.conflicting.message", defaultValue: "Keychain에서 '\(identityName)' 이름을 가진 인증서가 여러 개 발견되어 서버를 기동할 수 없습니다.\nKeychain Access 앱으로부터 중복된 인증서들을 제거 후 다시 서버를 기동하여 주십시오.")
            
            let openKeychainAccess = {
                // FIXME: 별도 코드로 뺄것
                let appleScript =
"""
tell application "Keychain Access"
    activate
end tell
"""
                
                var error: NSDictionary?
                if let scriptObject = NSAppleScript(source: appleScript) {
                    scriptObject.executeAndReturnError(&error)
                }
            }
            
            alert.addButton(title: String(localized: "server.identity_error.button.open_keychain", defaultValue: "Keychain Access 열기"), action: openKeychainAccess)
            
            alert.addButton(title: String(localized: "server.identity_error.button.autoconf", defaultValue: "자가 서명 인증서를 자동 구성하기")) {
                if isAutoconfEnabled {
                    // 어떤 상황이냐면: 자가 서명 인증서가 이미 구성되어 있는데 서버 버그인지 뭔지 자가 서명 인증서가 여러 개 있는거임
                    let alert = NOCAlert()
                    alert.title = String(localized: "server.identity_error.autoconf_confirm.title", defaultValue: "자동 구성을 다시 실시하시겠습니까?")
                    alert.message = String(localized: "server.identity_error.autoconf_confirm.message", defaultValue: "자동 구성을 다시 실시하면 기존에 생성된 인증서가 전부 삭제되고 새로운 인증서가 생성됩니다.")
                    
                    alert.addButton(title: String(localized: "server.identity_error.autoconf_confirm.yes", defaultValue: "예")) {
                         performAutoconfInner()
                    }
                    
                    alert.addButton(title: String(localized: "server.identity_error.autoconf_confirm.no", defaultValue: "아니오")) {}
                    
                    alert.addButton(title: String(localized: "server.identity_error.button.open_keychain", defaultValue: "Keychain Access 열기"), action: openKeychainAccess)
                    
                    Task {
                        await alert.present()
                    }
                } else {
                    performAutoconfInner()
                }
            }
            
            alert.addButton(title: String(localized: "server.identity_error.button.close", defaultValue: "닫기")) {}
        case .identityNotFound:
            alert.title = String(localized: "server.identity_error.not_found.title", defaultValue: "서버 인증서를 찾을 수 없음")
            
            switch identitySource {
            case .keychain:
                alert.message = String(localized: "server.identity_error.not_found.message.keychain", defaultValue: "Keychain에서 '\(identityName)' 이름을 가진 서버 인증서를 찾을 수 없습니다.")
            case .pemFile:
                alert.message = String(localized: "server.identity_error.not_found.message.pem", defaultValue: "지정된 경로에서 서버 인증서를 찾을 수 없습니다.")
            default:
                alert.message = String(localized: "server.identity_error.not_found.message.default", defaultValue: "서버 인증서를 찾을 수 없습니다.")
            }
            
            alert.addButton(title: String(localized: "server.identity_error.button.autoconf", defaultValue: "자가 서명 인증서를 자동 구성하기"), action: performAutoconfInner)
            
            alert.addButton(title: String(localized: "server.identity_error.button.close", defaultValue: "닫기")) {}
        default:
            alert.title = String(localized: "server.identity_error.load_failed.title", defaultValue: "서버 인증서 로드 실패")
            alert.message = String(localized: "server.identity_error.load_failed.message", defaultValue: "알 수 없는 이유로 서버 인증서를 로드하지 못했습니다.\n\(error.localizedDescription)")
            
            alert.addButton(title: String(localized: "server.identity_error.button.close", defaultValue: "닫기")) {}
        }
        
        // 어, 망했다.. 이거 뜰 때는 NSWindow가 하나도 없을 수도 있을텐데 (왜냐하면 서버 앱이니까) -> 파라미터 없는 present()로 해결!
        await alert.present()
    }
}
