import SwiftUI
import MetalKit

#if os(macOS)
struct MetalCursorView: NSViewRepresentable {
    var cursorState: RemoteSession.CursorState
    var sourceSize: CGSize
    var targetDisplayID: Int

    func makeCoordinator() -> CursorRenderer? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return CursorRenderer(device: device)
    }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()

        view.device = MTLCreateSystemDefaultDevice()
        view.layer?.isOpaque = false
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        view.isPaused = true
        view.enableSetNeedsDisplay = true

        view.delegate = context.coordinator

        // Combine 기반 직접 구독 (SwiftUI 뷰 업데이트 파이프라인 우회)
        context.coordinator?.bind(to: view, cursorState: cursorState, sourceSize: sourceSize, targetDisplayID: targetDisplayID)

        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        // sourceSize/targetDisplayID 변경 시에만 반영 (커서 상태는 Combine으로 직접 처리)
        context.coordinator?.updateSourceParameters(sourceSize: sourceSize, targetDisplayID: targetDisplayID)
    }
}
#endif

#if os(iOS)
struct MetalCursorView: UIViewRepresentable {
    var cursorState: RemoteSession.CursorState
    var sourceSize: CGSize
    var targetDisplayID: Int

    func makeCoordinator() -> CursorRenderer? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return CursorRenderer(device: device)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()

        view.device = MTLCreateSystemDefaultDevice()
        view.isOpaque = false
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        view.isPaused = true
        view.enableSetNeedsDisplay = true

        view.delegate = context.coordinator

        // Combine 기반 직접 구독 (SwiftUI 뷰 업데이트 파이프라인 우회)
        context.coordinator?.bind(to: view, cursorState: cursorState, sourceSize: sourceSize, targetDisplayID: targetDisplayID)

        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        // sourceSize/targetDisplayID 변경 시에만 반영 (커서 상태는 Combine으로 직접 처리)
        context.coordinator?.updateSourceParameters(sourceSize: sourceSize, targetDisplayID: targetDisplayID)
    }
}
#endif
