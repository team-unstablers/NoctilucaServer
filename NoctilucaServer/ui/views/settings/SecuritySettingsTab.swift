import SwiftUI

struct SecuritySettingsTab: View {
    @Binding
    var settings: AppSettings

    var body: some View {
        Form {
            Section {
                AuthMethodContainer(authMethods: $settings.security.allowedEntries)
            } header: {
                Text("인증 수단")
                Text("이 컴퓨터에 접속할 때 사용할 인증 수단을 설정합니다. 드래그-드롭으로 우선 순위를 변경할 수 있습니다. [더 알아보기…](http://google.com)")
            }

            Section {
                IntegerField(value: $settings.quicTransport.listenPort) {
                    Text("서버 포트")
                    Text("Noctiluca가 수신 대기할 포트를 설정합니다.")
                }
                SettingsEntry(title: "서버 인증서", subtitle: "이 인증서는 2032-12-31까지 유효합니다.") {
                    VStack(alignment: .trailing) {
                        Text("Keychain에서 불러온 인증서: Test Certificate")
                        Text("AA:BB:CC:DD:EE:FF:DE:AD:BE:EF")
                            .font(.subheadline.monospaced())
                    }
                }
                Toggle(isOn: $settings.quicTransport.tlsUseAutoconf) {
                    Text("서버 인증서를 자동으로 구성하기")
                    Text("자가 서명 인증서를 사용하여 QUIC 통신을 암호화합니다.")
                }
                
                if !settings.quicTransport.tlsUseAutoconf {
                    Toggle(isOn: $settings.quicTransport.tlsStrictValidation) {
                        Text("엄격한 유효성 검사 사용하기")
                        Text("시스템의 트러스트 스토어를 기준으로 신뢰할 수 없는 인증서를 사용 시 경고를 표시합니다.")
                    }
                    SettingsEntry(title: "인증서 불러오기") {
                        Button("파일 선택…") {
                            
                        }
                        Button("Keychain에서 불러오기…") {
                            
                        }
                    }
                }

            } header: {
                Text("트랜스포트 레이어")
                Text("Noctiluca에서는 QUIC 프로토콜을 사용하여 통신합니다. [더 알아보기…](http://google.com)")
            }

            Section {
                Toggle(isOn: $settings.transport.disableServerVersionAnnouncement) {
                    Text("서버 버전을 알리지 않기")
                    Text("서버 버전을 클라이언트에게 알리지 않습니다.")
                }

                Toggle(isOn: $settings.transport.disableSupportedFeaturesAnnouncement) {
                    Text("사용 가능한 기능 목록을 알리지 않기")
                    Text("서버에서 지원하는 기능 목록을 클라이언트에게 알리지 않습니다. 호환성이 떨어질 수 있습니다.")
                }
                TextField(text: $settings.transport.motd, prompt: Text("[부자가 되는 가장 빠른 지름길은, 많은 돈을 버는 것입니다.]").italic()) {
                    Text("오늘의 메시지 (MOTD)")
                    Text("클라이언트가 접속할 때 표시할 오늘의 메시지를 설정합니다.")
                }
                TextField(text: $settings.transport.authChallengeMessage, prompt: Text("[Contoso Inc. - 관계자 외 접근을 금합니다.]").italic()) {
                    Text("인증 요청 시 표시할 메시지")
                    Text("클라이언트에게 인증 요청 시 표시할 메시지를 설정합니다.")
                }
            } header: {
                Text("프로토콜")
                Text("Sirius 프로토콜의 동작 방식을 설정합니다. [더 알아보기…](http://google.com)")
            }
        }
        .formStyle(.grouped)
    }
}
