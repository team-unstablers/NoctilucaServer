//
//  TileTexturePool.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2025/01/28.
//

import Foundation
import Metal

/// 타일 텍스처 재사용 풀
final class TileTexturePool {
    private let device: MTLDevice
    private var pool: [TextureKey: [MTLTexture]] = [:]
    private let maxPoolSize: Int
    private let lock = NSLock()

    struct TextureKey: Hashable {
        let width: Int
        let height: Int
    }

    init(device: MTLDevice, maxPoolSize: Int = 16) {
        self.device = device
        self.maxPoolSize = maxPoolSize
    }

    func acquire(width: Int, height: Int) -> MTLTexture? {
        let key = TextureKey(width: width, height: height)

        lock.lock()
        defer { lock.unlock() }

        if let texture = pool[key]?.popLast() {
            return texture
        }

        return createTexture(width: width, height: height)
    }

    func release(_ texture: MTLTexture) {
        let key = TextureKey(width: texture.width, height: texture.height)

        lock.lock()
        defer { lock.unlock() }

        if pool[key, default: []].count < maxPoolSize {
            pool[key, default: []].append(texture)
        }
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        pool.removeAll()
    }

    private func createTexture(width: Int, height: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared

        return device.makeTexture(descriptor: descriptor)
    }
}
