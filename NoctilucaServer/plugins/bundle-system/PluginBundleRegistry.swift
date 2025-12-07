//
//  PluginBundleRegistry.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/5/25.
//

import Foundation

import SiriusKit
import NoctilucaPluginKit

enum PluginBundleRegistryError: LocalizedError {
    /// 번들이 존재하지 않거나, 번들 검증에 실패한 경우
    case invalidBundle
    
    /// 같은 ID의 번들이 이미 등록된 경우 (버전이 다르거나, 파일 중복, ...)
    case duplicateBundle(id: String)
    
    /// 보안 정책 위반
    case securityPolicyViolation(currentPolicy: PluginBundleSecurityPolicy, requiredPolicy: PluginBundleSecurityPolicy)
    
    /// 보안 정책은 위반하지 않았으나, 시스템에서 로드를 거부한 경우
    case rejectedBySystem
    
    /// 메타데이터 검증 실패
    case metadataValidationFailed(reason: String?)
    
    case initializationFailed(error: Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidBundle:
            return NSLocalizedString("core.plugin.PluginBundleRegistryError.invalidBundle", comment: "플러그인 번들이 파손되었습니다.")
            
        case .duplicateBundle(let id):
            return String(
                localized: "core.plugin.PluginBundleRegistryError.duplicateBundle(id: \(id))",
                comment: "플러그인 번들이 중복 등록되었습니다."
            )
            
        case .securityPolicyViolation(let currentPolicy, let requiredPolicy):
            return String(
                localized: "core.plugin.PluginBundleRegistryError.securityPolicyViolation(currentPolicy: \(currentPolicy.rawValue), requiredPolicy: \(requiredPolicy.rawValue))",
                comment: "플러그인 번들이 보안 정책을 위반했습니다."
            )
        case .rejectedBySystem:
            return NSLocalizedString("core.plugin.PluginBundleRegistryError.rejectedBySystem", comment: "플러그인 번들이 시스템에서 거부되었습니다.")
            
        case .metadataValidationFailed(let reason):
            if let reason {
                return String(
                    localized: "core.plugin.PluginBundleRegistryError.metadataValidationFailed(reason: \(reason))",
                    comment: "플러그인 번들의 메타데이터 검증에 실패했습니다."
                )
            } else {
                return NSLocalizedString("core.plugin.PluginBundleRegistryError.metadataValidationFailed", comment: "플러그인 번들의 메타데이터 검증에 실패했습니다.")
            }
        case .initializationFailed(let error):
            return String(
                localized: "core.plugin.PluginBundleRegistryError.initializationFailed(error: \(error.localizedDescription))",
                comment: "플러그인 번들의 초기화에 실패했습니다."
            )
        }
    }
}

struct PluginBundleHandle {
    let bundleClass: NoctilucaPluginBundle.Type
    let metadata: any PluginBundleMetadata
}

class PluginBundleRegistry {
    static let shared = PluginBundleRegistry()
    
    private let logger = NoctilucaLogger(category: "PluginBundleRegistry")
    
    private(set) var bundles: [String: PluginBundleHandle] = [:]
    private let defaultPolicy: PluginBundleSecurityPolicy
    
    private init() {
        // TODO: Load policy from configuration
        self.defaultPolicy = .allowTeamUnstablers
    }
    
    deinit {
        for (id, handle) in bundles {
            do {
                try handle.bundleClass.deinitialize()
                logger.info("Successfully deinitialized plugin bundle with id: \(id)")
            } catch {
                logger.error("Failed to deinitialize plugin bundle with id: \(id), error: \(error)")
            }
        }
    }
    
    /// 주어진 URL의 플러그인 번들 정보를 가져온다
    func loadPluginBundleMetadata(from url: URL) -> Result<PluginBundlePlistMetadata, PluginBundleRegistryError> {
        guard let bundle = Bundle(url: url) else {
            return .failure(.invalidBundle)
        }
        
        return loadPluginBundleMetadata(from: bundle)
    }
    
    /// 주어진 URL의 플러그인 번들 정보를 가져온다
    func loadPluginBundleMetadata(from bundle: Bundle) -> Result<PluginBundlePlistMetadata, PluginBundleRegistryError> {
        guard let bundleInfo = bundle.infoDictionary,
              let metadata = PluginBundlePlistMetadata(from: bundleInfo)
        else {
            return .failure(.invalidBundle)
        }
        
        return .success(metadata)
    }
    
    /// 플러그인 번들을 URL로부터 로드한다.
    func loadBundle(from url: URL, policy: PluginBundleSecurityPolicy? = nil) async -> Result<any PluginBundleMetadata, PluginBundleRegistryError> {
        logger.info("Loading plugin bundle from \(url.path)")
        
        guard let bundle = Bundle(url: url) else {
            return .failure(.invalidBundle)
        }
        
        let metadataResult = loadPluginBundleMetadata(from: bundle)
        
        if case .failure(let error) = metadataResult {
            return .failure(error)
        }
        
        let metadata = try! metadataResult.get()
        
        guard !self.bundles.keys.contains(metadata.id) else {
            logger.error("Failed to load plugin bundle from \(url.path): duplicate bundle id \(metadata.id)")
            return .failure(.duplicateBundle(id: metadata.id))
        }
        
        // TODO: 보안 정책 검증
        
        guard bundle.load() else {
            logger.error("Failed to load plugin bundle from \(url.path): unable to load bundle")
            return .failure(.rejectedBySystem)
        }
        
        guard let bundleClass = bundle.principalClass as? NoctilucaPluginBundle.Type else {
            logger.error("Failed to load plugin bundle from \(url.path): principal class is not a NoctilucaPluginBundle")
            return .failure(.invalidBundle)
        }
                
        return await registerBundle(bundleClass: bundleClass, metadata: metadata)
    }
    
    /// 플러그인 번들을 등록한다.
    func registerBundle(bundleClass: NoctilucaPluginBundle.Type, metadata: any PluginBundleMetadata) async -> Result<any PluginBundleMetadata, PluginBundleRegistryError> {
        guard !self.bundles.keys.contains(metadata.id) else {
            logger.error("Failed to register plugin bundle: duplicate bundle id \(metadata.id)")
            return .failure(.duplicateBundle(id: metadata.id))
        }
        
        do {
            try await bundleClass.initialize()
        } catch {
            defer {
                try? bundleClass.deinitialize()
            }
            
            logger.error("Failed to load plugin bundle \(metadata.id) initialization failed with error: \(error)")
            return .failure(.initializationFailed(error: error))
        }
        
        if let metadata = metadata as? PluginBundlePlistMetadata {
            guard self.validateBundleExports(bundleClass: bundleClass, with: metadata) else {
                logger.error("Failed to load plugin bundle \(metadata.id): metadata validation failed")
                return .failure(.metadataValidationFailed(reason: "Exported plugins do not match metadata"))
            }
        }
        
        let handle = PluginBundleHandle(bundleClass: bundleClass, metadata: metadata)
        self.bundles[metadata.id] = handle
        
        logger.info("Successfully registered plugin bundle: \(metadata.id)")
        
        return .success(metadata)
    }
    
    func unloadBundle(withId id: String) {
        guard let handle = self.bundles[id] else {
            logger.warning("Attempted to unload non-existent plugin bundle with id: \(id)")
            return
        }
        
        do {
            try handle.bundleClass.deinitialize()
            logger.info("Successfully deinitialized plugin bundle with id: \(id)")
        } catch {
            logger.error("Failed to deinitialize plugin bundle with id: \(id), error: \(error)")
        }
        
        self.bundles.removeValue(forKey: id)
        logger.info("Successfully unloaded plugin bundle with id: \(id)")
    }
}

extension PluginBundleRegistry {
    /// 플러그인 번들에서 export한 플러그인 목록이 메타데이터와 일치하는지 검증한다.
    func validateBundleExports(bundleClass: NoctilucaPluginBundle.Type, with metadata: PluginBundlePlistMetadata) -> Bool {
        // 1. Export된 플러그인 수가 일치하는지 확인
        guard bundleClass.exports.count == metadata.exports.count else {
            return false
        }
        
        let pluginsMetadata = metadata.exports as! [PluginBundleExportPlistMetadata]
        
        // 2. 각 플러그인의 ID와 타입이 일치하는지 확인
        for pluginExport in bundleClass.exports {
            guard validatePluginMetadata(pluginExport: pluginExport, with: pluginsMetadata) else {
                self.logger.error("Plugin export validation failed for export: \(pluginExport.id)")
                return false
            }
        }
        
        return true
    }
    
    func validatePluginMetadata(pluginExport: NoctilucaPluginExport, with pluginsMetadata: [PluginBundleExportPlistMetadata]) -> Bool {
        switch pluginExport {
        case .auth(let authPlugin):
            return pluginsMetadata.contains { metadata in metadata.id == authPlugin.id && metadata.type == .auth }
        @unknown default:
            // 이거 어쩌죠?: 미래의 플러그인 타입이 추가된 경우
            break
        }
        
        return false
    }
}
