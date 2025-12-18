import SwiftUI

import SiriusKitClient

struct AboutSettingsTab: View {
    var body: some View {
        let productName = NoctilucaMeta.productName
        
        Form {
            Section {
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        Text("\(productName) 버전")
                        Text("")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("\(NoctilucaMeta.version) (\(NoctilucaMeta.buildVersion))")
                        Text("App Store")
                            .font(.subheadline)
                    }
                    .foregroundStyle(.secondary)
                }
                HStack(alignment: .top) {
                    Text("SiriusKit 버전")
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("\(SiriusKitMeta.displayVersion) (\(SiriusKitMeta.buildVersion))")
                        Text("프로토콜 버전 \(SiriusKitMeta.currentProtocolVersion.displayVersion)")
                            .font(.subheadline)
                    }
                    .foregroundStyle(.secondary)
                }
                HStack(alignment: .top) {
                    Text("사용 중인 트랜스포트 레이어 구현체")
                    Spacer()
                    VStack(alignment: .trailing) {
                        ForEach(TransportLayerImplementation.allCases, id: \.self) { implementation in
                            Text(implementation.description)
                        }
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
            } header: {
                Text("\(productName) 정보")
            } footer: {
                Text("이 소프트웨어는 오픈 소스 소프트웨어가 포함되어 있습니다. [라이선스 정보…](http://google.com)")
                Text("Sirius 프로토콜의 사양 문서는 GitHub [team-unstablers/SiriusProtocol](https://github.com/team-unstablers/SiriusProtocol) 에 공개되어 있습니다.")
                Text("")
                Text("© 2025 team unstablers Inc. All rights reserved.")
            }
        }
        .formStyle(.grouped)
    }
}
