//
//  ProjectionChannel+displayman.swift
//  NoctilucaServer
//
//  Created by Claude on 1/28/26.
//

import Foundation

import AppKit
import CoreGraphics

import SiriusKit

extension ProjectionChannel {
    // MARK: - Display List Request

    func handleDisplayListRequest(_ request: DisplayListRequest) async throws {
        let displayLayoutManager = await DisplayLayoutManager.shared
        let layouts = displayLayoutManager.displayLayouts

        let flags = DisplayListRequestFlags(rawValue: request.flags)
        let includeThumbnails = flags.contains(.includeThumbnails)

        var displays: [DisplayInfo] = []

        for (displayID, screen) in layouts {
            let displayInfo = buildDisplayInfo(from: screen, displayID: displayID, includeThumbnail: includeThumbnails)
            displays.append(displayInfo)
        }

        try await self.send(opcode: .displayListResponse, message: DisplayListResponse(
            requestID: request.requestID,
            displays: displays
        ))
    }

    // MARK: - Subscribe Display Changes

    func handleSubscribeDisplayChangesRequest(_ request: SubscribeDisplayChangesRequest) async throws {
        let subscription = DisplayEventSubscription(eventMask: request.eventMask)
        subscription.channel = self

        let result = await state.replaceDisplaySubscription(subscription)

        switch result {
        case .rejected:
            subscription.destroy()
            return

        case .installed(let previousSubscription):
            await subscription.setup()

            guard await state.isCurrentDisplaySubscription(subscription) else {
                subscription.destroy()
                return
            }

            previousSubscription?.destroy()

            try await self.send(opcode: .subscribeDisplayChangesResponse, message: SubscribeDisplayChangesResponse(
                requestID: request.requestID,
                subscriptionID: subscription.id
            ))
        }
    }

    // MARK: - Unsubscribe Display Changes

    func handleUnsubscribeDisplayChangesRequest(_ request: UnsubscribeDisplayChangesRequest) async throws {
        let unsubscribeResult = await state.unsubscribeDisplaySubscription(expectedID: request.subscriptionID)

        switch unsubscribeResult {
        case .notFound, .mismatchedSubscriptionID:
            try await self.send(opcode: .unsubscribeDisplayChangesResponse, message: UnsubscribeDisplayChangesResponse(
                requestID: request.requestID,
                subscriptionID: request.subscriptionID,
                isSuccess: false
            ))

        case .unsubscribed(let subscription):
            subscription.destroy()

            try await self.send(opcode: .unsubscribeDisplayChangesResponse, message: UnsubscribeDisplayChangesResponse(
                requestID: request.requestID,
                subscriptionID: subscription.id,
                isSuccess: true
            ))
        }
    }

    // MARK: - Send Display Changed Event

    func sendDisplayChangedEvent(_ event: DisplayChangeEvent) async throws {
        guard await state.lifecycleState == .active else {
            return
        }

        let displayInfo: DisplayInfo

        if event.eventType.contains(.disconnected) {
            // disconnected 이벤트는 displayID만 포함한 minimal DisplayInfo 전송
            displayInfo = DisplayInfo(
                displayID: event.displayID,
                kind: .unknown,
                displayName: "",
                state: DisplayState(isPrimary: false, isConnected: false, isActive: false),
                bounds: SRRect(x: 0, y: 0, width: 0, height: 0),
                refreshRate: 0,
                colorDepth: .unknown,
                dynamicRange: .sdr,
                colorProfile: nil,
                physicalSizeInfo: nil,
                thumbnail: nil,
                metadata: [:],
                flags: 0
            )
        } else {
            let displayID = event.displayID
            guard let nocScreen = DisplayLayoutManager.shared.displayLayouts[displayID] else {
                return
            }

            displayInfo = buildDisplayInfo(from: nocScreen, displayID: event.displayID)
        }

        try await self.send(opcode: .displayChangedEvent, message: DisplayChangedEvent(
            eventType: event.eventType,
            display: displayInfo
        ))
    }

    // MARK: - Build DisplayInfo

    private func buildDisplayInfo(from screen: NOCScreen, displayID: CGDirectDisplayID, includeThumbnail: Bool = false) -> DisplayInfo {
        // 디스플레이 종류 판별
        let kind = getDisplayKind(displayID: displayID)

        let nsScreen = screen.backingNSScreen

        // 디스플레이 이름
        let displayName = nsScreen?.localizedName ?? ""

        // 상태 정보
        let isPrimary = CGDisplayIsMain(displayID) != 0
        let isConnected = CGDisplayIsOnline(displayID) != 0
        let isActive = CGDisplayIsActive(displayID) != 0
        let state = DisplayState(isPrimary: isPrimary, isConnected: isConnected, isActive: isActive)

        // 화면 영역 (글로벌 좌표계 기준)
        let frame = screen.frame
        let bounds = SRRect(x: frame.origin.x, y: frame.origin.y, width: frame.width, height: frame.height)

        // 주사율
        let refreshRate = getRefreshRate(displayID: displayID)

        // 색상 깊이
        let colorDepth = getColorDepth(displayID: displayID)

        // 다이나믹 레인지 (HDR 지원 여부)
        let dynamicRange = if let nsScreen {
            getDynamicRange(screen: nsScreen)
        } else {
            DisplayDynamicRange.sdr
        }

        // 색상 프로파일
        let colorProfile = if let nsScreen {
            getColorProfile(screen: nsScreen)
        } else {
            DisplayColorProfile.sRGB
        }

        // 물리적 크기 정보
        let physicalSizeInfo = getPhysicalSizeInfo(displayID: displayID)

        // 메타데이터
        var metadata: [String: String] = [:]

        // 미러링 정보 추가
        let mirroredDisplayID = CGDisplayMirrorsDisplay(displayID)
        if mirroredDisplayID != kCGNullDirectDisplay {
            metadata["related-display-id"] = String(mirroredDisplayID)
        }

        let thumbnailData: Data? = if includeThumbnail {
            captureThumbnail(displayID: displayID)
        } else {
            nil
        }

        return DisplayInfo(
            displayID: displayID,
            kind: kind,
            displayName: displayName,
            state: state,
            bounds: bounds,
            refreshRate: refreshRate,
            colorDepth: colorDepth,
            dynamicRange: dynamicRange,
            colorProfile: colorProfile,
            physicalSizeInfo: physicalSizeInfo,
            thumbnail: thumbnailData,
            metadata: metadata,
            flags: 0
        )
    }

    private func getDisplayKind(displayID: CGDirectDisplayID) -> DisplayKind {
        if CGDisplayIsBuiltin(displayID) != 0 {
            return .internal
        }

        // 가상 디스플레이 체크
        // CGDisplayVendorNumber가 0이거나, IOKit을 통해 확인할 수 있음
        // 간단하게 vendor/model이 특정 값인지 확인
        let vendorNumber = CGDisplayVendorNumber(displayID)
        if vendorNumber == 0 {
            return .virtual
        }

        return .external
    }

    private func getRefreshRate(displayID: CGDirectDisplayID) -> Float {
        guard let mode = CGDisplayCopyDisplayMode(displayID) else {
            return 0
        }
        return Float(mode.refreshRate)
    }

    private func getColorDepth(displayID: CGDirectDisplayID) -> DisplayColorDepth {
        guard let mode = CGDisplayCopyDisplayMode(displayID) else {
            return .unknown
        }

        // pixelEncoding 또는 bitsPerPixel로 판단
        let bitsPerPixel = mode.pixelWidth > 0 ? 32 : 24 // 기본값

        // HDR 지원 모니터는 10bit일 가능성이 높음
        if let pixelEncoding = mode.pixelEncoding {
            let encodingString = pixelEncoding as String
            if encodingString.contains("10") {
                return .bit10
            }
        }

        // 대부분의 경우 8bit
        _ = bitsPerPixel
        return .bit8
    }

    private func getDynamicRange(screen: NSScreen) -> DisplayDynamicRange {
        // macOS 10.15+에서 maximumPotentialExtendedDynamicRangeColorComponentValue 확인
        if screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.0 {
            return .hdr
        }
        return .sdr
    }

    private func getColorProfile(screen: NSScreen) -> DisplayColorProfile? {
        guard let colorSpace = screen.colorSpace,
              let name = colorSpace.localizedName else {
            return nil
        }

        // 알려진 색상 프로파일 매핑
        if name.contains("sRGB") {
            return .sRGB
        } else if name.contains("Adobe RGB") {
            return .adobeRGB
        } else if name.contains("P3") || name.contains("DCI") {
            return .dciP3
        }

        // 기타 프로파일은 이름 그대로 반환
        return DisplayColorProfile(rawValue: name)
    }

    /// 디스플레이의 현재 화면을 캡처하여 JPEG 섬네일로 변환합니다.
    private func captureThumbnail(displayID: CGDirectDisplayID, maxDimension: Int = 320) -> Data? {
        guard let cgImage = CGDisplayCreateImage(displayID) else {
            return nil
        }

        let originalWidth = cgImage.width
        let originalHeight = cgImage.height
        let scale = min(
            CGFloat(maxDimension) / CGFloat(originalWidth),
            CGFloat(maxDimension) / CGFloat(originalHeight)
        )
        let targetWidth = Int(CGFloat(originalWidth) * scale)
        let targetHeight = Int(CGFloat(originalHeight) * scale)

        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

        guard let resizedImage = context.makeImage() else {
            return nil
        }

        let bitmapRep = NSBitmapImageRep(cgImage: resizedImage)
        return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
    }

    private func getPhysicalSizeInfo(displayID: CGDirectDisplayID) -> DisplayPhysicalSizeInfo? {
        let widthMM = CGDisplayScreenSize(displayID).width
        let heightMM = CGDisplayScreenSize(displayID).height

        // 0이면 정보 없음
        guard widthMM > 0 && heightMM > 0 else {
            return nil
        }

        // 가로/세로 DPI 계산
        let pixelWidth = CGFloat(CGDisplayPixelsWide(displayID))
        let pixelHeight = CGFloat(CGDisplayPixelsHigh(displayID))
        let widthInches = widthMM / 25.4
        let heightInches = heightMM / 25.4

        let horizontalDPI = widthInches > 0 ? (pixelWidth / widthInches) : 0
        let verticalDPI = heightInches > 0 ? (pixelHeight / heightInches) : 0
        let averageDPI = UInt32(((horizontalDPI + verticalDPI) / 2.0).rounded())

        return DisplayPhysicalSizeInfo(
            physicalSize: SRSize(
                width: Double(widthMM),
                height: Double(heightMM)
            ),
            dpi: averageDPI
        )
    }
}
