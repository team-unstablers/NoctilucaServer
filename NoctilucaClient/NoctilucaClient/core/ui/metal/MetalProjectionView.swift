//
//  MetalProjectionView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/27/26.
//

import SwiftUI
import MetalKit

#if os(macOS)
struct MetalProjectionView: NSViewRepresentable {
    let renderer: ProjectionCanvasRenderer

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()

        view.device = MTLCreateSystemDefaultDevice()
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.colorPixelFormat = .bgra8Unorm

        // 수동 갱신 모드: compositor가 canvas를 업데이트할 때만 다시 그린다
        view.isPaused = true
        view.enableSetNeedsDisplay = true

        view.delegate = renderer
        renderer.bind(to: view)

        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        // renderer 교체 시 delegate 재설정
        if nsView.delegate !== renderer {
            nsView.delegate = renderer
            renderer.bind(to: nsView)
        }
    }
}
#endif

#if os(iOS)
struct MetalProjectionView: UIViewRepresentable {
    let renderer: ProjectionCanvasRenderer

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()

        view.device = MTLCreateSystemDefaultDevice()
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.colorPixelFormat = .bgra8Unorm

        // 수동 갱신 모드: compositor가 canvas를 업데이트할 때만 다시 그린다
        view.isPaused = true
        view.enableSetNeedsDisplay = true

        view.delegate = renderer
        renderer.bind(to: view)

        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        // renderer 교체 시 delegate 재설정
        if uiView.delegate !== renderer {
            uiView.delegate = renderer
            renderer.bind(to: uiView)
        }
    }
}
#endif
