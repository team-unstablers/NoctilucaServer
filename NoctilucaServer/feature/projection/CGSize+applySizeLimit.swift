//
//  CGSize+applySizeLimit.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 2/26/26.
//

import Foundation

extension CGSize {
    /// 원본 비율을 유지하면서 `desired` 해상도의 픽셀 수 이하로 축소된 새 해상도를 반환합니다.
    /// `desired`의 픽셀 수가 원본보다 크거나 같으면 원본을 그대로 반환합니다.
    func applySizeLimit(_ desired: CGSize) -> CGSize {
        let oursPixelCount = width * height
        let theirsPixelCount = desired.width * desired.height

        if theirsPixelCount >= oursPixelCount {
            return self
        }

        let aspectRatio = width / height
        // newHeight^2 * aspectRatio = theirsPixelCount
        let newHeight = floor(sqrt(theirsPixelCount / aspectRatio))
        let newWidth = floor(newHeight * aspectRatio)

        return CGSize(width: newWidth, height: newHeight)
    }
}
