//
//  RootViewController.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/26/25.
//
#if canImport(UIKit)
import Foundation
import UIKit
import Combine

import SwiftUI

@MainActor
final class AboutAppWindowViewController: UIHostingController<AnyView> {
    init() {
        let contentView = AboutAppView()
        super.init(rootView: AnyView(contentView))
        
        self.sizingOptions = .intrinsicContentSize
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

#endif
