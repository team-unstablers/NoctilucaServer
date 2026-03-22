//
//  MetalVideoView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 3/22/26.
//

import SwiftUI
import MetalKit

#if os(macOS)
struct MetalVideoView: NSViewRepresentable {
    let renderer: MetalVideoRenderer

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()

        view.device = renderer.device
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        // HDR OS 위임: macOS 26+에서는 RGBA16Float + preferredDynamicRange로 OS에 톤매핑 위임
        if #available(macOS 26.0, *), renderer.colorSpace.isHDR {
            view.colorPixelFormat = .rgba16Float
            (view.layer as? CAMetalLayer)?.preferredDynamicRange = .high
        } else {
            view.colorPixelFormat = .bgra8Unorm
            if renderer.colorSpace.isHDR {
                (view.layer as? CAMetalLayer)?.wantsExtendedDynamicRangeContent = true
            }
        }

        // 수동 갱신 모드: present() 호출 시에만 렌더링
        view.isPaused = true
        view.enableSetNeedsDisplay = true

        view.delegate = renderer
        renderer.bind(to: view)

        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        if nsView.delegate !== renderer {
            nsView.delegate = renderer
            renderer.bind(to: nsView)
        }
    }
}
#endif

#if os(iOS)
struct MetalVideoView: UIViewRepresentable {
    let renderer: MetalVideoRenderer

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()

        view.device = renderer.device
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        // HDR OS 위임: iOS 26+
        if #available(iOS 26.0, *), renderer.colorSpace.isHDR {
            view.colorPixelFormat = .rgba16Float
            (view.layer as? CAMetalLayer)?.preferredDynamicRange = .high
        } else {
            view.colorPixelFormat = .bgra8Unorm
            if renderer.colorSpace.isHDR {
                (view.layer as? CAMetalLayer)?.wantsExtendedDynamicRangeContent = true
            }
        }

        // 수동 갱신 모드
        view.isPaused = true
        view.enableSetNeedsDisplay = true

        view.delegate = renderer
        renderer.bind(to: view)

        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        if uiView.delegate !== renderer {
            uiView.delegate = renderer
            renderer.bind(to: uiView)
        }
    }
}
#endif
