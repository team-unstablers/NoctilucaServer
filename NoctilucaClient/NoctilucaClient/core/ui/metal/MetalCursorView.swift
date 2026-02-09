import SwiftUI
import MetalKit

#if os(macOS)
struct MetalCursorView: NSViewRepresentable {
    @ObservedObject var cursorState: RemoteSession.CursorState
    var sourceSize: CGSize
    var targetDisplayID: Int

    func makeCoordinator() -> CursorRenderer? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return CursorRenderer(device: device)
    }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()

        // 1. Metal Device 설정
        view.device = MTLCreateSystemDefaultDevice()

        // 2. 배경 투명하게
        view.layer?.isOpaque = false
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        // 3. 저전력 모드 설정 (Event-Driven)
        view.isPaused = true
        view.enableSetNeedsDisplay = true

        // 4. Delegate 연결
        view.delegate = context.coordinator

        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        // 커서 상태가 변경될 때마다 Renderer에게 알림
        context.coordinator?.updateCursorState(cursorState, sourceSize: sourceSize, targetDisplayID: targetDisplayID, in: nsView)
    }
}
#endif

#if os(iOS)
struct MetalCursorView: UIViewRepresentable {
    @ObservedObject var cursorState: RemoteSession.CursorState
    var sourceSize: CGSize
    var targetDisplayID: Int

    func makeCoordinator() -> CursorRenderer? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return CursorRenderer(device: device)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()

        view.device = MTLCreateSystemDefaultDevice()
        view.isOpaque = false // iOS는 layer 대신 view 속성
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        view.isPaused = true
        view.enableSetNeedsDisplay = true

        view.delegate = context.coordinator

        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator?.updateCursorState(cursorState, sourceSize: sourceSize, targetDisplayID: targetDisplayID, in: uiView)
    }
}
#endif
