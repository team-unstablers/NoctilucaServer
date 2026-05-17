//
//  PluginBundleManifest.swift
//  NoctilucaPluginKitHostCore
//
//  Created by Gyuhwan Park on 5/16/26.
//

import Foundation
import NoctilucaPluginKit

/// 플러그인 번들의 식별/표시용 메타데이터 contract.
public protocol PluginBundleMetadataManifest: Identifiable, Sendable {
    var id: String { get }
    var name: NocPluginLocalizableString { get }
    var bundleDescription: NocPluginLocalizableString { get }

    var authors: [String] { get }
    var license: SoftwareLicense { get }

    var url: String? { get }
}

/// 플러그인 번들 매니페스트 전체 contract.
/// 식별 메타데이터 + PluginKit 버전 + 격리 정책 + exports 를 포함합니다.
public protocol PluginBundleManifest: PluginBundleMetadataManifest {
    var pluginKitVersion: NoctilucaPluginKitVersion { get }
    var isolationPolicy: PluginIsolationPolicy { get }
    var exports: [NocPluginManifest] { get }
}
