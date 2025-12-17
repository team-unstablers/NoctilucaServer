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

struct AppKitSampleBufferDisplayView: NSViewRepresentable {
    let displayLayer: AVSampleBufferDisplayLayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // AppKit views need their layer set explicitly to host Core Animation layers
        view.wantsLayer = true
        view.layer?.addSublayer(displayLayer)
        displayLayer.backgroundColor = .black
        displayLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.needsDisplayOnBoundsChange = true
        displayLayer.needsDisplayOnBoundsChange = true
        
        displayLayer.frame = view.bounds
        displayLayer.bounds = view.bounds
        displayLayer.videoGravity = .resize
        displayLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 1.0
        
        
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Update frame or other properties if needed
        displayLayer.frame = nsView.bounds
        displayLayer.bounds = nsView.bounds
    }
}

typealias SampleBufferDisplayView = AppKitSampleBufferDisplayView

#endif
