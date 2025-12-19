//
//  ContactsItem.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/19/25.
//

import SwiftUI

struct LaunchEffect: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .scaleEffect(phase == .identity || phase == .didDisappear ? 1.25 : 0.8)
            .opacity(phase == .identity ? 1.0 : 0.0)
    }
}


extension AnyTransition {
    static var launchEffect: AnyTransition {
        AnyTransition(LaunchEffect())
    }
}


enum ContactItemAction {
    case launch
    case edit
}

struct ContactItemView: View {
    let item: ContactItem
    let actionHandler: ((ContactItemAction) -> Void)
    
    @FocusState
    var isFocused: Bool
    
    @State
    var shouldAnimateLaunchEffect: Bool = false
    
    @ViewBuilder
    var _body: some View {
        HStack {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 32))
                .frame(width: 48, height: 48)
                .padding(.trailing, 8)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(item.displayName)
                    .font(.title2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 6)
                Text("3년 전에 최종 접속")
            }
            
            Spacer()
            
            HStack {
                Button {
                    actionHandler(.edit)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .contentShape(.rect(cornerRadius: 8))
        .glassEffect(
            .regular.tint(.gray.opacity(0.05)).interactive(true),
            in: .rect(cornerRadius: 8)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
    
    var body: some View {
        _body
        .focusable(interactions: [.activate, .edit])
        .focused($isFocused)
        .onKeyPress(.return) {
            print("Return key pressed on ContactsItem")
            performLaunch()
            
            return .handled
        }
        .onTapGesture(count: 2) {
            print("ContactsItem double-clicked")
            performLaunch()
        }
        .overlay {
            if shouldAnimateLaunchEffect {
                _body
                    .background(.white)
                    .transition(
                        .launchEffect.animation(.easeInOut(duration: 0.3))
                    )
            }
        }
    }
    
    func performLaunch() {
        if (shouldAnimateLaunchEffect) {
            return
        }
        
        shouldAnimateLaunchEffect = true
        
        actionHandler(.launch)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            shouldAnimateLaunchEffect = false
        }
    }
}


#Preview {
    let item = ContactItem(name: nil, endpointURL: "localhost")
    let item2 = ContactItem(name: "내부 리소스 #1", endpointURL: "localhost")
    let item3 = ContactItem(name: "집 컴퓨터", endpointURL: "localhost")
    
    VStack {
        ContactItemView(item: item) {_ in}
        ContactItemView(item: item2) {_ in}
        ContactItemView(item: item3) {_ in}
    }
    .frame(minWidth: 360, minHeight: 360)
}
