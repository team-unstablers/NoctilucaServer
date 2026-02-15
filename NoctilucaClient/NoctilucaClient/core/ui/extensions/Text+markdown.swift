//
//  Text+markdown.swift
//  NoctilucaClient
//

import SwiftUI

extension Text {
    init(markdown: String) {
        self.init(LocalizedStringKey(markdown))
    }
}
