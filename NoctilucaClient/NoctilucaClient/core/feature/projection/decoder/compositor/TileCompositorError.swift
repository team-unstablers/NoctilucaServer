//
//  TileCompositorError.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2025/01/28.
//

import Foundation

enum TileCompositorError: LocalizedError {
    case bufferPoolCreationFailed
    case bufferAcquisitionFailed
    case missingKeyFrame
    case invalidTileRect
    case invalidFrameSize
    case metalNotAvailable
    case commandQueueCreationFailed
    case textureNotInitialized
    case commandBufferCreationFailed
    case blitEncoderCreationFailed
    case textureCreationFailed

    var errorDescription: String? {
        switch self {
        case .bufferPoolCreationFailed:
            return "Failed to create pixel buffer pool"
        case .bufferAcquisitionFailed:
            return "Failed to acquire pixel buffer from pool"
        case .missingKeyFrame:
            return "Missing key frame for delta frame composition"
        case .invalidTileRect:
            return "Invalid tile rectangle"
        case .invalidFrameSize:
            return "Invalid frame size"
        case .metalNotAvailable:
            return "Metal is not available on this device"
        case .commandQueueCreationFailed:
            return "Failed to create Metal command queue"
        case .textureNotInitialized:
            return "Metal texture not initialized"
        case .commandBufferCreationFailed:
            return "Failed to create Metal command buffer"
        case .blitEncoderCreationFailed:
            return "Failed to create Metal blit command encoder"
        case .textureCreationFailed:
            return "Failed to create Metal texture"
        }
    }
}
