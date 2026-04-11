//
//  ringoOSTitleBar.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 4/3/26.
//

import SwiftUI

enum RingoOSTitleBarButtonType {
    case close
    case maximize
    case disabled
    
    var color: Color {
        switch self {
        case .close:
            return Color(r8: 255, g8: 92, b8: 95, a: 1.0)
        case .maximize:
            return Color(r8: 52, g8: 199, b8: 89, a: 1.0)
        default:
            return Color(r8: 220, g8: 220, b8: 220, a: 1.0)
        }
    }
    
    var borderColor: Color {
        switch self {
        case .close:
            return Color(r8: 253, g8: 58, b8: 64, a: 1.0)
        case .maximize:
            return Color(r8: 0, g8: 182, b8: 24, a: 1.0)
        default:
            return Color(r8: 209, g8: 209, b8: 209, a: 1.0)
        }
    }
}

struct RingoOSTitleBarButton: View {
    let type: RingoOSTitleBarButtonType
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(type.color)
                .strokeBorder(type.borderColor, lineWidth: 1)
                .frame(width: 15, height: 15)
        }
        .buttonStyle(.plain)
    }

}

struct RingoOSTitleBar: View {
    let title: String
    var showDivider: Bool = true
    var onClose: () -> Void = {}
    var onMaximize: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    RingoOSTitleBarButton(type: .close, action: onClose)
                    RingoOSTitleBarButton(type: .disabled)
                    RingoOSTitleBarButton(type: .maximize, action: onMaximize)
                }
                .padding(.horizontal, 8)
                Text(title)
                    .font(.system(size: 13).bold())
                    .foregroundStyle(.primary)

                Spacer()
            }
            .padding(.vertical, 8)
            if showDivider {
                Divider()
                    .background(Color(r8: 230, g8: 230, b8: 230))
            }
        }
        .background(.white)
    }
}

struct RingoOSResizeHandle: View {
    var body: some View {
        Canvas { context, size in
            for i in 0..<3 {
                let offset = CGFloat(i) * 4
                var path = Path()
                path.move(to: CGPoint(x: size.width, y: offset))
                path.addLine(to: CGPoint(x: offset, y: size.height))
                context.stroke(path, with: .color(.gray.opacity(0.5)), lineWidth: 1.5)
            }
        }
        .frame(width: 12, height: 12)
        .padding(6)
        .contentShape(Rectangle())
    }
}

struct RingoOSDialog<Content: View>: View {
    let title: String
    var isExpanded: Bool = true
    var onClose: (() -> Void)? = nil
    var onMaximize: (() -> Void)? = nil

    @ViewBuilder
    let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            RingoOSTitleBar(
                title: title,
                showDivider: isExpanded,
                onClose: { onClose?() },
                onMaximize: { onMaximize?() }
            )
            if isExpanded {
                content()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    RingoOSDialog(title: "test") {
        Text("Hello, World!")
    }
}
