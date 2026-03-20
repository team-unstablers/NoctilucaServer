//
//  AboutAppView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/14/26.
//

import Foundation
import SwiftUI

struct AboutAppView: View {
    @Environment(\.openURL)
    var openURL
    
    @State
    var isLetterSectionVisible: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
#if os(macOS)
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 128, height: 128)
#else
                if let icon = NoctilucaMeta.applicationIcon() {
                    Image(uiImage: icon)
                        .resizable()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.15), radius: 16)
                        .padding(.bottom, 8)
                }
#endif
                
                VStack(alignment: .leading) {
                    VStack(alignment: .leading) {
                        HStack(spacing: 0) {
                            Text("Noctiluca ")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                            
                            Text("Navigator")
                                .font(.largeTitle)
                                .fontWeight(.light)
                        }
                        
                        Text(String(format: String(localized: "about.version_format", defaultValue: "버전 %@ (%@)"), NoctilucaMeta.version, NoctilucaMeta.buildVersion))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 8)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Group {
                            Text("Copyright © 2026 team unstablers Inc. All rights reserved.")
                            Text(markdown: String(localized: "about.open_source_notice", defaultValue: "이 소프트웨어는 오픈 소스 소프트웨어를 포함합니다. 자세한 사항은 아래 '오픈 소스 라이선스' 버튼을 눌러 확인할 수 있습니다."))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 8)
                    
                    VStack {
                        HStack {
                            Button {
                                openURL(URL(string: "https://noctiluca.app/docs/eula/navigator/apple")!)
                            } label: {
                                Text(markdown: String(localized: "about.terms_of_service", defaultValue: "사용권 계약"))
                            }

                            Button {
                                openURL(URL(string: "https://noctiluca.app/docs/open-sources/navigator/apple")!)
                            } label: {
                                Text(markdown: String(localized: "about.open_source_licenses", defaultValue: "오픈 소스 라이선스"))
                            }

                            Button {
                                isLetterSectionVisible.toggle()
                            } label: {
                                Text(markdown: String(localized: "about.appeal_button", defaultValue: "호소문…"))
                            }
                        }
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            
            
            if isLetterSectionVisible {
                ScrollView {
                    VStack(alignment: .leading) {
                        Text(markdown: String(localized: "about.appeal.title", defaultValue: "호소문"))
                            .font(.title)
                            .bold()
                            .padding(.bottom, 1)

                        Text(markdown: String(localized: "about.appeal.subtitle", defaultValue: "저희 [주식회사 팀언스테이블러즈](https://unstabler.pl)에게 일을 맡겨주세요"))
                            .font(.title2)
                            .bold()
                            .padding(.bottom, 4)

                        Text(
                            markdown: String(
                                localized: "about.appeal.body",
                                defaultValue: "안녕하세요, 저희는 대한민국 경기도 안산에 위치한 영세한 소프트웨어 개발 업체인 **주식회사 팀언스테이블러즈** (team unstablers Inc.) 입니다. \n\n저희는 \"여러분들의 꿈을 이루어 드립니다\" 라는 모토 아래, 많은 클라이언트들이 이루지 못한 기술적 난제를 주로 해결해오곤 했습니다. 사실은 저희는 \"우리가 하고 싶은 것이 무엇인지 몰라서\", \"그나마 할 줄 아는 것이 컴퓨터 뿐이어서\" 이런 모토를 내걸고 남을 돕는 일을 계속 해왔습니다.\n\n하지만, 불경기로 인해 수익 구조에도 여러 변동이 생기면서, 저희 회사의 지속 가능 여부도 불투명해졌습니다. 급여와 세금도 밀리고, 회사 통장에는 압류도 들어오게 되었습니다.\n\nNoctiluca / Sirius는 그런 와중에 멍청한 제가 바닥부터 구상해내고 실현할 수 있었던 몇 안되는 프로젝트 중 하나였습니다. 몇 년 가까이 생각을 구체화 하면서, 처음으로 여러분께 선보일 수 있게 된 것을 자랑스럽게 생각하고 있습니다.\n\n저희는 부자가 되고 싶지 않습니다. 그저 매일마다 생존에 대한 걱정 없이 컴퓨터 프로그래밍을 하고 싶을 뿐입니다.\n\n감사합니다."
                            )
                        )
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                }
                .background(.white)
                .border(.tertiary)
                .frame(minHeight: 250)
                .padding(.top, 24)
            }
        }
        .padding(24)
        .frame(minWidth: 580, maxWidth: 480)
            
    }
}

#Preview {
    AboutAppView()
}
