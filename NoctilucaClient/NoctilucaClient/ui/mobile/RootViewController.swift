//
//  RootViewController.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/26/25.
//
#if canImport(UIKit)
import Foundation
import UIKit

import SwiftUI

final class RootViewController: UIHostingController<AnyView> {
    /// 포인터 락 여부를 설정합니다.
    /// true로 설정 시 포인터가 고정되지만, 전체 화면 모드에서만 동작합니다.
    var isPointerLocked: Bool = false {
        didSet {
            setNeedsUpdateOfPrefersPointerLocked()
        }
    }
    
    override var prefersPointerLocked: Bool {
        return isPointerLocked
    }
}

#endif
