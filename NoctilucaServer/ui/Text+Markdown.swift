//
//  Text+Markdown.swift
//  NoctilucaServer
//
//  Created by Gemini on 1/30/26.
//

import SwiftUI

extension Text {
    /// 번역된 String을 마크다운으로 렌더링하기 위한 이니셜라이저입니다.
    /// - Parameter markdown: 마크다운 문법이 포함된 문자열
    init(markdown: String) {
        self.init(LocalizedStringKey(markdown))
    }
}
