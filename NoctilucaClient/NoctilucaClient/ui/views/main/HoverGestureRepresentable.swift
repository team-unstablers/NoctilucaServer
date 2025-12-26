//
//  HoverGestureRepresentable.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/26/25.
//

import SwiftUI
import UIKit

import CoreGraphics

fileprivate class FZGestureRecognizerInternalDelegate: NSObject, UIGestureRecognizerDelegate {
    static let shared = FZGestureRecognizerInternalDelegate()
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
    
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        return true
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive event: UIEvent) -> Bool {
        print("shouldReceive \(event)")
        return true
    }
    
}

struct HoverGestureRepresentable: UIGestureRecognizerRepresentable {
    typealias UIGestureRecognizerType = UIHoverGestureRecognizer
    
    let handler: (CGPoint, CGRect) -> Void

    
    func makeUIGestureRecognizer(context: Context) -> UIHoverGestureRecognizer {
        let gestureRecognizer = UIHoverGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleHover(_:)))
        gestureRecognizer.delegate = FZGestureRecognizerInternalDelegate.shared
        
        return gestureRecognizer
    }
    
    func updateGestureRecognizer(_ gestureRecognizer: UIHoverGestureRecognizer, context: Context) {
        // No update needed
    }
    
    
    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(handler: self.handler)
    }

    
    class Coordinator: NSObject {
        let handler: (CGPoint, CGRect) -> Void
        
        init(handler: @escaping (CGPoint, CGRect) -> Void) {
            self.handler = handler
        }

        @objc func handleHover(_ gestureRecognizer: UIHoverGestureRecognizer) {
            switch gestureRecognizer.state {
            case .began:
                print("Hover began")
            case .changed:
                print("Hover changed")
                handleUIGestureRecognizerAction(gestureRecognizer)
                
            case .ended:
                print("Hover ended")
            default:
                break
            }
        }
        
        func handleUIGestureRecognizerAction(_ recognizer: UIHoverGestureRecognizer) {
            handler(recognizer.location(in: recognizer.view), recognizer.view!.frame)
        }
    }
    
}
