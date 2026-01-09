import SwiftUI

import SiriusKit

struct AboutSettingsTab: View {
    var body: some View {
        Form {
            Section {
                SettingsEntry(title: "Noctiluca Server 버전") {
                    VStack(alignment: .trailing) {
                        Text("0.1.0-alpha1")
                        Text("개발 버전")
                            .font(.subheadline)
                    }
                }
                SettingsEntry(title: "SiriusKit 버전") {
                    VStack(alignment: .trailing) {
                        Text("\(SiriusKitMeta.displayVersion)")
                        Text("프로토콜 버전 \(SiriusKitMeta.currentProtocolVersion.displayVersion)")
                            .font(.subheadline)
                    }
                }
                SettingsEntry(title: "사용 중인 트랜스포트 레이어 구현체") {
                    VStack(alignment: .trailing) {
                        Text("QUIC (SiriusKit + Apple)")
                    }
                }
                SettingsEntry(title: "사용 가능한 기능 목록") {
                    VStack(alignment: .trailing) {
                        Text("HIDIO")
                        Text("Projection")
                        Text("ProjectionData")
                    }
                }
                SettingsEntry(title: "유효한 라이선스") {
                    VStack(alignment: .trailing) {
                        Text("아니오")
                    }
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
            
            Section {
                AuthPluginListContainer()
            } header: {
                Text("로드된 인증 플러그인 목록")
            }
        }
        .formStyle(.grouped)
    }
}
