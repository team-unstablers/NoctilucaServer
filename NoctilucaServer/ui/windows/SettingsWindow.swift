//
//  Untitled.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 11/26/25.
//

import SwiftUI

struct SettingsWindow: View {
    var body: some View {
        NavigationStack {
            TabView {
                Tab {
                    Form {
                        Section("일반") {
                            Toggle(isOn: .constant(true)) {
                                Text("시스템 기동 시 자동으로 Noctiluca 시작하기")
                            }
                            
                            TextField(text: .constant("2")) {
                                Text("최대 동시 접속 수")
                                Text("Noctiluca가 허용할 최대 동시 접속 수를 설정합니다.")
                            }
                        }
                        
                        
                        Section("알림") {
                            Toggle(isOn: .constant(true)) {
                                Text("사용자에게 알림 표시하기")
                                Text("...")
                            }
                            
                            Toggle("사용자가 접속했을 때", isOn: .constant(true))
                            Toggle("사용자가 접속을 종료했을 때", isOn: .constant(true))
                            Toggle("오류가 발생했을 때", isOn: .constant(true))
                            
                        }
                    }
                    .formStyle(.grouped)
                } label: {
                    Text("일반")
                }
                Tab {
                    Text("Settings")
                        .frame(minWidth: 400, minHeight: 300)
                } label: {
                    Text("화면")
                }
                Tab {
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
                } label: {
                    Text("보안")
                }
                Tab {
                    Form {
                        Section("텔레메트리 및 진단 정보") {
                            Toggle(isOn: .constant(false)) {
                                Text("Noctiluca의 개발을 익명으로 돕기")
                                Text("사용자 환경 및 사용 통계를 익명으로 수집하는 것을 허용합니다.\n프라이버시 보호를 우선하기 위해, 이 옵션은 기본적으로 꺼져 있습니다. [더 알아보기…](http://google.com)")
                            }
                            HStack(alignment: .center) {
                                Text("텔레메트리 식별자")
                                Spacer()
                                HStack {
                                    Button("식별자 재설정") {
                                        
                                    }
                                }
                            }
                            
                            HStack(alignment: .center) {
                                Text("진단 정보 내보내기")
                                Spacer()
                                HStack {
                                    Button("파일로 저장…") {
                                        
                                    }
                                }
                            }
                            HStack(alignment: .top) {
                                VStack(alignment: .leading) {
                                    Text("외부 접속 테스트")
                                    Text("주식회사 팀언스테이블러즈에서 제공하는 테스트 노드를 통해 외부로부터 접속이 가능한지 테스트합니다.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Button("접속 테스트 요청하기") {}
                                }
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .formStyle(.grouped)
                } label: {
                    Text("기타")
                }
                Tab {
                    Form {
                        Section {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading) {
                                    Text("Noctiluca Server 버전")
                                    Text("")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text("1.0.0-beta1")
                                    Text("App Store")
                                        .font(.subheadline)
                                }
                                .foregroundStyle(.secondary)
                            }
                            HStack(alignment: .top) {
                                Text("SiriusKit 버전")
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text("1.0.0-beta1")
                                    Text("프로토콜 버전 1 / 개정판 1")
                                        .font(.subheadline)
                                }
                                .foregroundStyle(.secondary)
                            }
                            HStack(alignment: .top) {
                                Text("사용 중인 트랜스포트 레이어 구현체")
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text("QUIC (SiriusKit + Apple)")
                                }
                                .foregroundStyle(.secondary)
                            }
                            HStack(alignment: .top) {
                                Text("사용 가능한 기능 목록")
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text("HIDIO")
                                    Text("Projection")
                                    Text("ProjectionData")
                                    Text("ConcurrentSession")
                                }
                                .foregroundStyle(.secondary)
                            }
                            HStack(alignment: .top) {
                                VStack(alignment: .leading) {
                                    Text("유효한 라이선스")
                                    Text("")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text("아니오")
                                }
                                .foregroundStyle(.secondary)
                            }
                        } header: {
                            Text("Noctiluca Server (Explicit Edition) 정보")
                            Text("")
                        } footer: {
                            Text("이 소프트웨어는 오픈 소스 소프트웨어가 포함되어 있습니다. [라이선스 정보…](http://google.com)")
                            Text("Sirius 프로토콜의 사양 문서는 GitHub [team-unstablers/SiriusProtocol](https://github.com/team-unstablers/SiriusProtocol) 에 공개되어 있습니다.")
                            Text("")
                            Text("© 2024 team unstablers Inc. All rights reserved.")
                        }
                    }
                    .formStyle(.grouped)
                } label: {
                    Text("정보")
                }
            }
            .frame(minWidth: 640)
        }
        .navigationTitle("test")
        .navigationSubtitle("test")
        .toolbar {
            ToolbarItem {
                Button("닫기") {
                    NSApp.keyWindow?.close()
                }
            }
        }
    }
}

#Preview {
    SettingsWindow()
}
