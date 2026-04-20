//
//  PluginBundleRegistry.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/5/25.
//

import Foundation
import AppKit

import SiriusKit
@preconcurrency import NoctilucaPluginKit

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
    let signingResult: CodeSigningVerificationResult?
}

actor PluginBundleRegistry {
    static let shared = PluginBundleRegistry()
    
    private let logger = NoctilucaLogger(category: "PluginBundleRegistry")
    
    private(set) var bundles: [String: PluginBundleHandle] = [:]
    private(set) var defaultPolicy: PluginBundleSecurityPolicy = .allowTeamUnstablers

    private init() {
    }

    func configure(policy: PluginBundleSecurityPolicy) {
        self.defaultPolicy = policy
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
        guard let bundleInfo = bundle.infoDictionary else {
            return .failure(.invalidBundle)
        }

        do {
            let metadata = try PluginBundlePlistMetadata(from: bundleInfo)
            return .success(metadata)
        } catch {
            return .failure(.metadataValidationFailed(reason: error.localizedDescription))
        }
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
        
        // 보안 정책 검증 (bundle.load() 이전에 수행해야 함)
        let effectivePolicy = policy ?? defaultPolicy
        let verificationResult = PluginBundleCodeSigningVerifier.verify(bundleURL: url)
        let allowResult = PluginBundleCodeSigningVerifier.shouldAllow(result: verificationResult, policy: effectivePolicy)

        if case .failure(let error) = allowResult {
            logger.warning("Plugin bundle \(metadata.id) rejected by security policy (\(effectivePolicy.rawValue)): \(error.localizedDescription ?? "")")
            Task { @MainActor [metadata, effectivePolicy] in
                AppNotification.pluginBundleRejectedBySecurityPolicy(metadata: metadata, currentPolicy: effectivePolicy)
                    .post()
            }
            return .failure(error)
        }

        // allowAll 정책에서 unsigned/adHoc 번들은 사용자 확인 필요
        if effectivePolicy == .allowAll {
            switch verificationResult {
            case .unsigned, .adHocSignature:
                let confirmed = await confirmUnsignedBundleLoad(bundleURL: url, metadata: metadata)
                if !confirmed {
                    logger.info("User rejected loading unsigned/ad-hoc bundle: \(metadata.id)")
                    return .failure(.rejectedBySystem)
                }
            default:
                break
            }
        }

        guard bundle.load() else {
            logger.error("Failed to load plugin bundle from \(url.path): unable to load bundle")
            return .failure(.rejectedBySystem)
        }
        
        guard let bundleClass = bundle.principalClass as? NoctilucaPluginBundle.Type else {
            logger.error("Failed to load plugin bundle from \(url.path): principal class is not a NoctilucaPluginBundle")
            return .failure(.invalidBundle)
        }
                
        return await registerBundle(bundleClass: bundleClass, metadata: metadata, signingResult: verificationResult)
    }
    
    /// 플러그인 번들을 등록한다.
    @discardableResult
    func registerBundle(bundleClass: NoctilucaPluginBundle.Type, metadata: any PluginBundleMetadata, signingResult: CodeSigningVerificationResult? = nil) async -> Result<any PluginBundleMetadata, PluginBundleRegistryError> {
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
            if let reason = self.validateBundleExports(bundleClass: bundleClass, with: metadata) {
                logger.error("Failed to load plugin bundle \(metadata.id): \(reason)")
                return .failure(.metadataValidationFailed(reason: reason))
            }
        }
        
        let handle = PluginBundleHandle(bundleClass: bundleClass, metadata: metadata, signingResult: signingResult)
        self.bundles[metadata.id] = handle
        
        for export in bundleClass.exports {
            switch export {
            case .auth(let plugin):
                await AuthPluginRegistry.shared.register(plugin: plugin)
                let pluginId = await plugin.id
                
                logger.info("Registered auth plugin: \(pluginId) from bundle: \(metadata.id)")
            case .extension(let extensionPlugin):
                // TODO: ExtensionPluginRegistry 연동 (향후 구현)
                logger.info("Registered extension plugin: \(type(of: extensionPlugin).id) from bundle: \(metadata.id)")
            case .keyboardHack(let keyboardHack):
                await HIDIOKeyboardHackRegistry.shared.register(keyboardHack)
                logger.info("Registered keyboard hack: \(type(of: keyboardHack).id) from bundle: \(metadata.id)")
            @unknown default:
                logger.warning("Encountered unknown plugin export type from bundle: \(metadata.id), skipping registration")
            }
        }
        
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
    @MainActor
    private func confirmUnsignedBundleLoad(bundleURL: URL, metadata: PluginBundlePlistMetadata) -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "core.plugin.unsigned_bundle_alert.title", defaultValue: "서명되지 않은 플러그인 번들")
        alert.informativeText = String(localized: "core.plugin.unsigned_bundle_alert.informative_text", defaultValue: """
            "\(metadata.displayName)" (\(metadata.id)) 플러그인 번들은 유효한 코드 서명이 없습니다.
            서명되지 않은 플러그인은 시스템에 악영향을 줄 수 있습니다.

            경로: \(bundleURL.path)

            계속 로드하시겠습니까?
            """)
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "core.plugin.unsigned_bundle_alert.button.load", defaultValue: "로드"))
        alert.addButton(withTitle: String(localized: "core.plugin.unsigned_bundle_alert.button.cancel", defaultValue: "취소"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: - 외부 번들 스캔 및 로드

    /// 검색 경로에서 외부 플러그인 번들을 스캔하고 로드한다.
    func loadExternalBundles() async {
        let searchPaths = buildPluginSearchPaths()
        for path in searchPaths {
            await scanAndLoadBundles(in: path)
        }
    }

    /// 플러그인 번들 검색 경로 목록을 구성한다.
    private func buildPluginSearchPaths() -> [URL] {
        var paths: [URL] = []

        // 1. 앱 번들 내장 PlugIns 디렉토리
        if let builtInPlugInsURL = Bundle.main.builtInPlugInsURL {
            paths.append(builtInPlugInsURL)
        }

        // 2. Application Support의 Plugins 디렉토리
        if let appSupportDir = try? AppSettings.applicationSupportDirectory() {
            let pluginsDir = appSupportDir.appendingPathComponent("Plugins", isDirectory: true)
            paths.append(pluginsDir)
        }

        return paths
    }

    /// 지정된 디렉토리에서 .nocbundle / .bundle 확장자를 가진 번들을 스캔하고 로드한다.
    private func scanAndLoadBundles(in directory: URL) async {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: directory.path) else {
            logger.debug("Plugin search path does not exist, skipping: \(directory.path)")
            return
        }

        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            logger.warning("Failed to scan plugin directory \(directory.path): \(error.localizedDescription)")
            return
        }

        let bundleURLs = contents.filter { url in
            let ext = url.pathExtension.lowercased()
            return ext == "nocbundle" || ext == "bundle"
        }

        for bundleURL in bundleURLs {
            let result = await loadBundle(from: bundleURL)
            if case .failure(let error) = result {
                logger.warning("Failed to load external bundle at \(bundleURL.path): \(error.localizedDescription ?? "unknown error")")
            }
        }
    }
}

extension PluginBundleRegistry {
    /// 플러그인 번들에서 export한 플러그인 목록이 메타데이터와 일치하는지 검증한다.
    /// - Returns: 검증 성공 시 `nil`, 실패 시 상세 사유 문자열
    func validateBundleExports(bundleClass: NoctilucaPluginBundle.Type, with metadata: PluginBundlePlistMetadata) -> String? {
        let pluginsMetadata = metadata.exports as! [PluginBundleExportPlistMetadata]

        // 1. Export된 플러그인 수가 일치하는지 확인
        if bundleClass.exports.count != pluginsMetadata.count {
            let exportIds = bundleClass.exports.map { $0.id }
            let metadataIds = pluginsMetadata.map { $0.id }
            return "Export count mismatch: bundle exports \(bundleClass.exports.count) plugin(s) \(exportIds),"
                + " but metadata declares \(pluginsMetadata.count) plugin(s) \(metadataIds)"
        }

        // 2. 각 플러그인의 ID와 타입이 일치하는지 확인
        var reasons: [String] = []
        for pluginExport in bundleClass.exports {
            if let reason = validatePluginMetadata(pluginExport: pluginExport, with: pluginsMetadata) {
                reasons.append(reason)
            }
        }

        return reasons.isEmpty ? nil : reasons.joined(separator: "; ")
    }

    /// - Returns: 검증 성공 시 `nil`, 실패 시 상세 사유 문자열
    func validatePluginMetadata(pluginExport: NoctilucaPluginExport, with pluginsMetadata: [PluginBundleExportPlistMetadata]) -> String? {
        let exportId = pluginExport.id
        let exportType: NoctilucaPluginType? = switch pluginExport {
        case .auth: .auth
        case .extension: .extension
        case .keyboardHack: .keyboardHack
        @unknown default: nil
        }
        
        guard let exportType else {
            return "Unknown plugin export type for plugin with id: \(exportId)"
        }

        let matchingById = pluginsMetadata.filter { $0.id == exportId }

        if matchingById.isEmpty {
            let available = pluginsMetadata.map { "\($0.id) (\($0.type.rawValue))" }
            return "Export '\(exportId)' (type: \(exportType.rawValue)) not found in metadata."
                + " Available: [\(available.joined(separator: ", "))]"
        }

        if !matchingById.contains(where: { $0.type == exportType }) {
            let actualTypes = matchingById.map { $0.type.rawValue }
            return "Export '\(exportId)' type mismatch: bundle declares '\(exportType.rawValue)',"
                + " but metadata has '\(actualTypes.joined(separator: ", "))'"
        }

        return nil
    }
}
