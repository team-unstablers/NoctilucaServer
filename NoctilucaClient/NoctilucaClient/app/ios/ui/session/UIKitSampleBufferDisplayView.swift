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
    private(set) var displayLayer: AVSampleBufferDisplayLayer

    init(displayLayer: AVSampleBufferDisplayLayer) {
        self.displayLayer = displayLayer
        super.init(frame: .zero)

        displayLayer.removeFromSuperlayer()
        backgroundColor = .blue
        configureDisplayLayer(displayLayer)
        layer.addSublayer(displayLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setDisplayLayer(_ newLayer: AVSampleBufferDisplayLayer) {
        guard newLayer !== displayLayer else { return }
        displayLayer.removeFromSuperlayer()
        newLayer.removeFromSuperlayer()
        displayLayer = newLayer
        configureDisplayLayer(displayLayer)
        layer.addSublayer(displayLayer)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true) // 리사이즈 애니메이션 방지
        displayLayer.frame = bounds
        CATransaction.commit()
    }

    private func configureDisplayLayer(_ displayLayer: AVSampleBufferDisplayLayer) {
        displayLayer.backgroundColor = UIColor.black.cgColor
        displayLayer.videoGravity = .resizeAspect
        displayLayer.contentsScale = UIScreen.main.scale
        
        if #available(iOS 26.0, *) {
            // TODO: 컨텐츠가 HDR일때만 이걸 설정해야 하지 않을까?
            displayLayer.preferredDynamicRange = .high
        } else {
            displayLayer.wantsExtendedDynamicRangeContent = true
        }
        
    }
}

final class SampleBufferHostViewController: UIViewController {
    private var displayLayer: AVSampleBufferDisplayLayer

    init(displayLayer: AVSampleBufferDisplayLayer) {
        self.displayLayer = displayLayer
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = SampleBufferHostView(displayLayer: displayLayer)
    }

    func updateDisplayLayer(_ newLayer: AVSampleBufferDisplayLayer) {
        displayLayer = newLayer
        (view as? SampleBufferHostView)?.setDisplayLayer(newLayer)
    }
}

struct UIKitSampleBufferDisplayView: UIViewControllerRepresentable {
    let displayLayer: AVSampleBufferDisplayLayer

    func makeUIViewController(context: Context) -> SampleBufferHostViewController {
        SampleBufferHostViewController(displayLayer: displayLayer)
    }

    func updateUIViewController(_ uiViewController: SampleBufferHostViewController, context: Context) {
        uiViewController.updateDisplayLayer(displayLayer)
    }
}

typealias SampleBufferDisplayView = UIKitSampleBufferDisplayView

#endif
