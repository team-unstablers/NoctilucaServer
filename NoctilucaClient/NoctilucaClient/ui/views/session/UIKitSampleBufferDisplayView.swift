//
//  SampleBufferDisplayView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/12/25.
//

#if canImport(UIKit)

import UIKit
import SwiftUI

import AVFoundation

final class SampleBufferHostView: UIView {
    let displayLayer: AVSampleBufferDisplayLayer

    init(displayLayer: AVSampleBufferDisplayLayer) {
        self.displayLayer = displayLayer
        super.init(frame: .zero)
        
        displayLayer.removeFromSuperlayer()

        backgroundColor = .blue
        layer.addSublayer(displayLayer)

        displayLayer.backgroundColor = UIColor.black.cgColor
        displayLayer.videoGravity = .resizeAspect
        // displayLayer.contentsScale = UIScreen.main.scale
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true) // 리사이즈 애니메이션 방지
        displayLayer.frame = bounds
        CATransaction.commit()
    }
}

final class SampleBufferHostViewController: UIViewController {
    let displayLayer: AVSampleBufferDisplayLayer
    
    var isPointerLocked: Bool = false {
        didSet {
            setNeedsUpdateOfPrefersPointerLocked()
        }
    }
    
    override var prefersPointerLocked: Bool {
        return isPointerLocked
    }

    init(displayLayer: AVSampleBufferDisplayLayer) {
        self.displayLayer = displayLayer
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = SampleBufferHostView(displayLayer: displayLayer)
        
        Task {
            while (true) {
                print("[TEST] \(self.prefersPointerLocked) \(self.isPointerLocked) \(view.window?.windowScene?.activationState == .foregroundActive)")
                try? await Task.sleep(for: .seconds(1))
                
                self.setNeedsUpdateOfPrefersPointerLocked()
            }
        }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        isPointerLocked = true
    }
}

struct UIKitSampleBufferDisplayView: UIViewControllerRepresentable {
    let displayLayer: AVSampleBufferDisplayLayer

    func makeUIViewController(context: Context) -> SampleBufferHostViewController {
        SampleBufferHostViewController(displayLayer: displayLayer)
    }

    func updateUIViewController(_ uiViewController: SampleBufferHostViewController, context: Context) {
        // No-op: displayLayer is managed by SampleBufferHostView.
        uiViewController.isPointerLocked = true
    }
}

typealias SampleBufferDisplayView = UIKitSampleBufferDisplayView

#endif
