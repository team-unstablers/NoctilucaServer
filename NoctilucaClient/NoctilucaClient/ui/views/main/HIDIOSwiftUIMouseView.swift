//
//  HIDIOSwiftUIMouseView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/26/25.
//

import SwiftUI

struct HIDIOSwiftUIMouseView: View {
    let client: NoctilucaClient?
    
    @State
    var pointer = HIDIOSwiftUIPointer()
    
    @State
    var aspectRatio: CGFloat = 16.0 / 9.0
    
    var body: some View {
        VStack(alignment: .center) {
            if let client = self.client {
                Spacer()
                Color.white
                    .opacity(0.001)
                    .aspectRatio(aspectRatio, contentMode: .fit)
                    .onGeometryChange(for: CGSize.self) {
                        $0.size
                    } action: { size in
                        pointer.setGeometry(size)
                        HIDIOGCMouse.shared()?.geometry = size
                    }
                /*
                    .gesture(HoverGestureRepresentable { location, _ in
                        print("mouse location changed: \(location)")
                        pointer.reportMouseMove(location)
                    })
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            print("mouse location changed: \(location)")
                            pointer.reportMouseMove(location)
                        case .ended:
                            break
                        }
                    }
                    .onAppear {
                        if client.hidioController != nil {
                            client.hidioController.connect(pointer)
                        }
                    }
                    .onDisappear {
                        if client.hidioController != nil {
                            client.hidioController.disconnect(kind: .pointer)
                        }
                    }
                 */
                    .onReceive(client.uiEvents) { event in
                        guard case .FIXME_projectionStarted(let projectionSession) = event else {
                            return
                        }
                        
                        client.hidioController.connect(pointer)
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            let size = projectionSession.size
                            self.aspectRatio = size.width / size.height
                        }
                    }
                Spacer()
            } else {
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
