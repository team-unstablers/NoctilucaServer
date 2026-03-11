//
//  ContactIconView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/12/26.
//

import SwiftUI

extension SessionSettings.ContactIconSymbol {
    var sfSymbolName: String {
        switch self {
        case .monitor:  return "desktopcomputer"
        case .laptop:   return "laptopcomputer"
        case .server:   return "server.rack"
        case .terminal: return "terminal"
        case .gamepad:  return "gamecontroller"
        case .sparkles: return "sparkles"
        case .gear:     return "gearshape"
        case .globe:    return "globe"
        }
    }

    var displayName: String {
        switch self {
        case .monitor:  return String(localized: "contact_icon.symbol.monitor", defaultValue: "모니터")
        case .laptop:   return String(localized: "contact_icon.symbol.laptop", defaultValue: "노트북")
        case .server:   return String(localized: "contact_icon.symbol.server", defaultValue: "서버")
        case .terminal: return String(localized: "contact_icon.symbol.terminal", defaultValue: "터미널")
        case .gamepad:  return String(localized: "contact_icon.symbol.gamepad", defaultValue: "게임 컨트롤러")
        case .sparkles: return String(localized: "contact_icon.symbol.sparkles", defaultValue: "반짝임")
        case .gear:     return String(localized: "contact_icon.symbol.gear", defaultValue: "설정")
        case .globe:    return String(localized: "contact_icon.symbol.globe", defaultValue: "지구")
        }
    }
}

extension SessionSettings.ContactIconBackground {
    var displayName: String {
        switch self {
        case .blue:   return String(localized: "contact_icon.color.blue", defaultValue: "파랑")
        case .green:  return String(localized: "contact_icon.color.green", defaultValue: "초록")
        case .orange: return String(localized: "contact_icon.color.orange", defaultValue: "주황")
        case .purple: return String(localized: "contact_icon.color.purple", defaultValue: "보라")
        case .gray:   return String(localized: "contact_icon.color.gray", defaultValue: "회색")
        case .red:    return String(localized: "contact_icon.color.red", defaultValue: "빨강")
        case .teal:   return String(localized: "contact_icon.color.teal", defaultValue: "청록")
        case .yellow: return String(localized: "contact_icon.color.yellow", defaultValue: "노랑")
        }
    }

    var color: Color {
        switch self {
        case .blue:   return .blue
        case .green:  return .green
        case .orange: return .orange
        case .purple: return .purple
        case .gray:   return .gray
        case .red:    return .red
        case .teal:   return .teal
        case .yellow: return .yellow
        }
    }
}

struct ContactIconView: View {
    let icon: SessionSettings.ContactIcon
    var size: CGFloat = 48

    var body: some View {
        Image(systemName: icon.symbol.sfSymbolName)
            .font(.system(size: size * 0.45))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(icon.background.color.gradient)
            .clipShape(Circle())
    }
}

#Preview {
    HStack(spacing: 16) {
        ContactIconView(icon: .init(symbol: .monitor, background: .blue))
        ContactIconView(icon: .init(symbol: .laptop, background: .green))
        ContactIconView(icon: .init(symbol: .server, background: .purple))
        ContactIconView(icon: .init(symbol: .terminal, background: .orange), size: 64)
        ContactIconView(icon: .init(symbol: .gamepad, background: .red), size: 32)
    }
    .padding()
}
