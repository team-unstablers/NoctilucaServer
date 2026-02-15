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
    case delete
    case duplicate
}

struct ContactItemView: View {
    let item: ContactItem
    let actionHandler: ((ContactItemAction) -> Void)

    @FocusState
    var isFocused: Bool

    @State
    var shouldAnimateLaunchEffect: Bool = false

    @State
    private var isHovering: Bool = false

    private var icon: SessionSettings.ContactIcon {
        item.settings.general?.icon ?? .init()
    }

    @ViewBuilder
    var __innerBody: some View {
        VStack(spacing: 8) {
            ContactIconView(icon: icon, size: 48)

            Text(item.displayName)
                .font(.callout)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .padding(12)
        .contentShape(.rect(cornerRadius: 12))
        .with {
            if #available(macOS 26.0, iOS 26.0, *) {
                $0.glassEffect(
                    .regular.tint(.gray.opacity(0.05)).interactive(true),
                    in: .rect(cornerRadius: 12)
                )
            } else {
                $0.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .scaleEffect(isHovering ? 1.05 : 1.0)
        .brightness(isHovering ? 0.1 : 0.0)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
    }

    var body: some View {
        Button {
            performLaunch()
        } label: {
            __innerBody
        }
        .buttonStyle(.plain)
        .focusable(interactions: [.activate, .edit])
        .focused($isFocused)
        .onKeyPress(.return) {
            performLaunch()
            return .handled
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            Button(String(localized: "common.edit", defaultValue: "편집")) {
                actionHandler(.edit)
            }
            Button(String(localized: "common.duplicate", defaultValue: "복제")) {
                actionHandler(.duplicate)
            }
            Divider()
            Button(String(localized: "common.delete", defaultValue: "삭제"), role: .destructive) {
                actionHandler(.delete)
            }
        }
        .overlay {
            if shouldAnimateLaunchEffect {
                __innerBody
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

    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 120))], spacing: 16) {
        ContactItemView(item: item) {_ in}
        ContactItemView(item: item2) {_ in}
        ContactItemView(item: item3) {_ in}
    }
    .padding()
    .frame(minWidth: 400, minHeight: 300)
}
