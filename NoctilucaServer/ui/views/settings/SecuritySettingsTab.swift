import SwiftUI

struct SecuritySettingsTab: View {
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading) {
                    VStack(alignment: .leading) {
                        Text("구성된 인증 수단")
                        Text("드래그-드롭으로 우선 순위를 변경할 수 있습니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading) {
                        VStack(alignment: .leading) {
                            Text("스마트카드 인증")
                                .font(.headline)
                            Text("cardid: 1234567890abcdef1234567890abcdef12345678")
                                .font(.subheadline.monospaced())
                                .lineLimit(1)
                        }
                        Divider()
                        VStack(alignment: .leading) {
                            Text("SSH 키")
                                .font(.headline)
                            Text("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINGHpezMcBEmby7zNaxPmj4cFPZ/P6zi3wcO5xC1LPZz cheesekun@cheese-mbpr14.local")
                                .font(.subheadline.monospaced())
                                .lineLimit(1)
                        }
                        Divider()
                        VStack(alignment: .leading) {
                            Text("PAM 인증 (사용자명-비밀번호)")
                                .font(.headline)
                            Text("`staff` 그룹의 Mac 사용자에게 사용자명-비밀번호 인증을 허용합니다.")
                                .font(.subheadline)
                                .lineLimit(1)
                        }
                        Divider()
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
                    .background(.white)
                    HStack() {
                        Spacer()
                        Button("삭제") {

                        }
                        .disabled(true)
                        Button("추가") {

                        }
                    }
                }
            } header: {
                Text("인증 수단")
                Text("이 컴퓨터에 접속할 때 사용할 인증 수단을 설정합니다. [더 알아보기…](http://google.com)")
            }

            Section {
                TextField(text: .constant("12345")) {
                    Text("서버 포트")
                    Text("Noctiluca가 수신 대기할 포트를 설정합니다.")
                }
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        Text("서버 인증서")
                        Text("이 인증서는 2032-12-31까지 유효합니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("Keychain에서 불러온 인증서: Test Certificate")
                        Text("AA:BB:CC:DD:EE:FF:DE:AD:BE:EF")
                            .font(.subheadline.monospaced())
                    }
                    .foregroundStyle(.secondary)
                }
                Toggle(isOn: .constant(true)) {
                    Text("서버 인증서를 자동으로 구성하기")
                    Text("자가 서명 인증서를 사용하여 QUIC 통신을 암호화합니다.")
                }
                Toggle(isOn: .constant(true)) {
                    Text("엄격한 유효성 검사 사용하기")
                    Text("시스템의 트러스트 스토어를 기준으로 신뢰할 수 없는 인증서를 사용 시 경고를 표시합니다.")
                }
                HStack(alignment: .center) {
                    Text("인증서 불러오기")
                    Spacer()
                    HStack {
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
                Toggle(isOn: .constant(false)) {
                    Text("서버 버전을 알리지 않기")
                    Text("서버 버전을 클라이언트에게 알리지 않습니다.")
                }

                Toggle(isOn: .constant(false)) {
                    Text("사용 가능한 기능 목록을 알리지 않기")
                    Text("서버에서 지원하는 기능 목록을 클라이언트에게 알리지 않습니다. 호환성이 떨어질 수 있습니다.")
                }
                TextField(text: .constant(""), prompt: Text("부자가 되는 가장 빠른 지름길은, 많은 돈을 버는 것입니다.").italic()) {
                    Text("오늘의 메시지 (MOTD)")
                    Text("클라이언트가 접속할 때 표시할 오늘의 메시지를 설정합니다.")
                }
                TextField(text: .constant(""), prompt: Text("Contoso Inc. - 관계자 외 접근을 금합니다.")) {
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
