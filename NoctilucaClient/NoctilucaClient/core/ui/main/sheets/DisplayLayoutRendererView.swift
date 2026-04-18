//
//  DisplayLayoutRendererView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/2/26.
//

import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

import SiriusKitClient

struct DisplayLayoutRendererView: View {
    let displays: [DisplayInfo]

    private var entireViewport: CGRect {
        displays.reduce(.zero) { $0.union($1.bounds.cgRect) }
    }

    private var sortedDisplays: [DisplayInfo] {
        displays.sorted { $0.displayID < $1.displayID }
    }

    var body: some View {
        GeometryReader { geomProxy in
            let viewport = entireViewport
            let scale = min(
                geomProxy.size.width / viewport.width,
                geomProxy.size.height / viewport.height
            )
            let scaledSize = CGSize(
                width: viewport.width * scale,
                height: viewport.height * scale
            )

            ZStack(alignment: .topLeading) {
                ForEach(sortedDisplays, id: \.displayID) { display in
                    displayItemView(for: display, scale: scale)
                }

                Text("[DEBUG] scaled: \(scaledSize)")
            }
            .frame(width: scaledSize.width, height: scaledSize.height)
            .position(
                x: geomProxy.frame(in: .local).midX,
                y: geomProxy.frame(in: .local).midY
            )
        }
        .frame(maxWidth: 480, maxHeight: 480)
    }

    @ViewBuilder
    private func displayItemView(for display: DisplayInfo, scale: CGFloat) -> some View {
        let scaled = CGRect(
            x: display.bounds.x * scale,
            y: display.bounds.y * scale,
            width: display.bounds.width * scale,
            height: display.bounds.height * scale
        )

        VStack {
            Spacer()
            Text(display.displayName)
                .bold()
            Spacer()
        }
        .multilineTextAlignment(.center)
        .padding()
        .frame(width: scaled.width, height: scaled.height)
        .background {
            displayThumbnailView(for: display)
        }
        // isPrimary가 아니라 현재 프로젝션 중인 디스플레이가 red여야 하지 않을까?
        .border(display.state.isPrimary ? .red : .black)
        .position(x: scaled.midX, y: scaled.midY)
    }

    @ViewBuilder
    private func displayThumbnailView(for display: DisplayInfo) -> some View {
        ZStack {
            if let thumbnail = display.thumbnail, let image = platformImage(from: thumbnail) {
                Image(decorative: image, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            Rectangle()
                .fill(.white)
                .opacity(0.3)
        }
    }

    private func platformImage(from data: Data) -> CGImage? {
        #if os(macOS)
        return NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        return UIImage(data: data)?.cgImage
        #endif
    }
}
