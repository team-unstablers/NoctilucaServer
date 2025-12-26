//
//  HIDIOSwiftUIMouseView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/26/25.
//

import SwiftUI
import SiriusKitClient


struct HIDIOSwiftUIMouseView: View {
    fileprivate enum SpatialEventPhase {
        case change
        case end
    }
    
    let client: NoctilucaClient?
    
    @State
    var mouse = HIDIOSwiftUIMouse()
    
    @State
    var aspectRatio: CGFloat = 16.0 / 9.0
    
    @State
    var isDragging = false
    
    @State
    var isScrolling = false
    
    @State
    var scrollPrevLocation: CGPoint = .zero

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
                        mouse.setGeometry(size)
                    }
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            mouse.reportMouseMove(location)
                        case .ended:
                            break
                        }
                    }
                    .gesture(
                        DragGesture(coordinateSpace: .local)
                            .onChanged { event in
                                mouse.reportMouseMove(event.location)
                                
                                if !isDragging {
                                    isDragging = true
                                    mouse.reportMouseClick(button: .left, isPressed: true)
                                }
                                
                                print("Dragging at location: \(event.location)")
                                
                            }
                            .onEnded { event in
                                isDragging = false
                                mouse.reportMouseMove(event.location)
                                mouse.reportMouseClick(button: .left, isPressed: false)
                                print("Dragging at location: \(event.location)")
                            }
                            .exclusively(before:
                        SpatialTapGesture(count: 1, coordinateSpace: .local)
                            .onEnded { event in
                                print("Tapped at location: \(event)")
                                mouse.reportMouseMove(event.location)
                                mouse.reportMouseClick(button: .left, isPressed: true)
                                mouse.reportMouseClick(button: .left, isPressed: false)

                            }
                                        ).exclusively(before:
                                                     SpatialEventGesture(coordinateSpace: .local)
                            .onChanged { event in
                                print("spatial event: \(event.count)")
                                handleSpatialEvent(for: .change, events: event)
                            }
                        
                            .onEnded { event in
                                print("spatial event end: \(event.count)")
                                handleSpatialEvent(for: .change, events: event)

                            }
                                                     )
                    )
                    .onAppear {
                        if client.hidioController != nil {
                            client.hidioController.connect(mouse)
                        }
                    }
                    .onDisappear {
                        if client.hidioController != nil {
                            client.hidioController.disconnect(.swiftUIMouse)
                        }
                    }
                    .onReceive(client.uiEvents) { event in
                        guard case .FIXME_projectionStarted(let projectionSession) = event else {
                            return
                        }
                        
                        client.hidioController.connect(mouse)
                        
                        // FIXME: 레 이 스 컨 디 션
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
    
    fileprivate func handleSpatialEvent(for phase: SpatialEventPhase, events: SpatialEventCollection) {
        
        if phase == .change {
            if events.count == 2 {
                if !isScrolling {
                    isScrolling = true
                }
                
                let location = events.averageLocation()
                
                if scrollPrevLocation != .zero {
                    let deltaX = location.x - scrollPrevLocation.x
                    let deltaY = location.y - scrollPrevLocation.y
                    
                    mouse.reportMouseScroll(deltaX: Double(deltaX), deltaY: Double(-deltaY))
                }
                
                scrollPrevLocation = location
            } else {
                isScrolling = false
                scrollPrevLocation = .zero
                // end scroll
            }
        } else if phase == .end {
            isScrolling = false
            scrollPrevLocation = .zero
        }
        
    }
}

fileprivate extension SpatialEventCollection {
    // 평균 위치를 계산합니다.
    func averageLocation() -> CGPoint {
        guard self.count > 0 else {
            return CGPoint.zero
        }
        
        var totalX: CGFloat = 0
        var totalY: CGFloat = 0
        
        for event in self {
            totalX += event.location.x
            totalY += event.location.y
        }
        
        return CGPoint(x: totalX / CGFloat(self.count), y: totalY / CGFloat(self.count))
    }
}
