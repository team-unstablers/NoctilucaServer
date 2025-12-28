//
//  SettingsEntry.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/21/25.
//

import SwiftUI


struct SettingsEntry<Content: View>: View {
    let title: String
    let subtitle: String
    
    let content: () -> Content
    
    init(title: String, subtitle: String = "", @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }
    
#if os(iOS) || os(tvOS)
    var body: some View {
        VStack {
            VStack(alignment: .leading) {
                Text(title)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        content()
    }
#elseif os(macOS)
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading) {
                Text(title)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack() {
                content()
            }
            .foregroundStyle(.secondary)
        }
    }
#endif
}

#Preview {
    Form {
        Section {
            SettingsEntry(title: "기본 연결 설정", subtitle: "키매핑 테이블을 직접 편집합니다.\n잘못 편집할 경우 입력 기능이 정상적으로 동작하지 않을 수 있습니다.") {
                Button("설정…") {}
            }
        }
        Section {
            SettingsEntry(title: "키매핑 테이블 (고급 기능)", subtitle: "키매핑 테이블을 직접 편집합니다.\n잘못 편집할 경우 입력 기능이 정상적으로 동작하지 않을 수 있습니다.") {
                Button("기본값으로 복원") {}
                Button("설정…") {}
            }
        }
        
        Section {
            Picker(selection: .constant("")) {
                VStack(alignment: .leading) {
                    Text("GameController.framework")
                    Text("Apple의 게임 컨트롤러 프레임워크를 사용합니다.\nApp 전환 (⌘Tab), 창 닫기(⌘W), App 종료(⌘Q) 등의 단축키가 동작하지 않을 수 있습니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .tag("GameController")
                
                VStack(alignment: .leading) {
                    Text("Cocoa Event Tap")
                    Text("macOS의 Cocoa Event Tap API를 사용하여 입력을 리디렉션합니다.\n모든 단축키가 정상적으로 동작하지만, 접근성 / 손쉬운 사용 권한을 필요로 합니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .tag("CocoaEventTap")
            } label: {
                Text("입력 리디렉션 방법")
                Text("키보드, 마우스 등의 입력 장치를 원격 컴퓨터로 리디렉션하는 방법을 설정합니다.")
            }
            .pickerStyle(.inline)
        } header: {
            Text("키보드 입력 설정")
            Text("키보드 입력과 관련된 설정을 구성합니다.")
        }
    }
    .formStyle(.grouped)
}
