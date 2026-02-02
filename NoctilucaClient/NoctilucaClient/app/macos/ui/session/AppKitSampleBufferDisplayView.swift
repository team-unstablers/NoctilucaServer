//
//  SampleBufferDisplayView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/12/25.
//

#if canImport(AppKit)
import AppKit
import SwiftUI

import AVFoundation

final class SampleBufferHostView: NSView {
    private(set) var displayLayer: AVSampleBufferDisplayLayer

    init(displayLayer: AVSampleBufferDisplayLayer) {
        self.displayLayer = displayLayer
        super.init(frame: .zero)

        wantsLayer = true
        if layer == nil {
            layer = CALayer()
        }

        displayLayer.removeFromSuperlayer()
        configureDisplayLayer(displayLayer)
        layer?.addSublayer(displayLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setDisplayLayer(_ newLayer: AVSampleBufferDisplayLayer) {
        guard newLayer !== displayLayer else { return }
        displayLayer.removeFromSuperlayer()
        newLayer.removeFromSuperlayer()
        displayLayer = newLayer
        configureDisplayLayer(displayLayer)
        layer?.addSublayer(displayLayer)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
        displayLayer.bounds = bounds
        CATransaction.commit()
    }

    private func configureDisplayLayer(_ displayLayer: AVSampleBufferDisplayLayer) {
        displayLayer.backgroundColor = NSColor.black.cgColor
        displayLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        displayLayer.needsDisplayOnBoundsChange = true
        self.layer?.needsDisplayOnBoundsChange = true

        displayLayer.videoGravity = .resize
        displayLayer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0

        if #available (macOS 26.0, *) {
            self.layer?.preferredDynamicRange = .high
            displayLayer.preferredDynamicRange = .high
        } else {
            self.layer?.wantsExtendedDynamicRangeContent = true
            displayLayer.wantsExtendedDynamicRangeContent = true
        }
    }
}

struct AppKitSampleBufferDisplayView: NSViewRepresentable {
    let displayLayer: AVSampleBufferDisplayLayer

    func makeNSView(context: Context) -> SampleBufferHostView {
        SampleBufferHostView(displayLayer: displayLayer)
    }

    func updateNSView(_ nsView: SampleBufferHostView, context: Context) {
        nsView.setDisplayLayer(displayLayer)
    }
}

typealias SampleBufferDisplayView = AppKitSampleBufferDisplayView

#endif
