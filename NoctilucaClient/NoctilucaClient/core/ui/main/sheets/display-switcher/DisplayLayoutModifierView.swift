//
//  DisplayLayoutModifierView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/2/26.
//

import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

import SiriusKitClient

struct DisplayLayoutModifierView: View {
    typealias DisplayID = UInt32

    let displays: [DisplayInfo]
    let onApply: ([DisplayOperation], UInt32?) async throws -> Void

    @State private var stagedOrigins: [DisplayID: CGPoint] = [:]
    @State private var stagedSpecs: [DisplayID: DisplaySpec] = [:]
    @State private var stagedMainDisplayID: DisplayID?
    @State private var draggingID: DisplayID?
    @State private var dragStartOrigin: CGPoint?
    @State private var collidingIDs: Set<DisplayID> = []
    @State private var selectedDisplayID: DisplayID?
    @State private var isApplying: Bool = false
    @State private var lastError: String?

    private var selectedDisplay: DisplayInfo? {
        guard let id = selectedDisplayID else { return nil }
        return displays.first { $0.displayID == id }
    }

    private let snapThresholdScaled: CGFloat = 12
    
    var body: some View {
        ViewThatFits(in: [.horizontal, .vertical]) {
            mainBody
                .padding()
            // FIXME: EmptyView() 걸면 ViewThatFits가 제대로 작동하지 않아서 어쩔 수 없이 투명한 Text로 대체
            Text("FIXME")
                .opacity(0.001)
        }
    }

    private var mainBody: some View {
        HStack(spacing: 32) {
            RingoOSDialog(title: "Display Layout") {
                VStack {
                    VStack(spacing: 0) {
                        GeometryReader { geomProxy in
                            let viewport = stagedViewport
                            let scale: CGFloat = (viewport.width > 0 && viewport.height > 0)
                            ? min(geomProxy.size.width / viewport.width, geomProxy.size.height / viewport.height)
                            : 1.0
                            let scaledSize = CGSize(
                                width: viewport.width * scale,
                                height: viewport.height * scale
                            )
                            
                            ZStack(alignment: .topLeading) {
                                ForEach(sortedDisplays, id: \.displayID) { display in
                                    displayItemView(for: display, scale: scale, viewportOrigin: viewport.origin)
                                }
                            }
                            .frame(width: scaledSize.width, height: scaledSize.height)
                            .position(
                                x: geomProxy.frame(in: .local).midX,
                                y: geomProxy.frame(in: .local).midY
                            )
                        }
                        .padding()
                        
                        actionBarView
                    }
                    .frame(width: 320, height: 320)
                }
                .background(.white)
            }
            .fixedSize(horizontal: true, vertical: false)
            .onAppear {
                if stagedOrigins.isEmpty {
                    resetStagedOrigins()
                }
            }
            .onChange(of: displays.map { DisplayKey(id: $0.displayID, bounds: $0.bounds) }) { _, _ in
                resetStagedOrigins()
                collidingIDs.removeAll()
                lastError = nil
            }
            
            RingoOSDialog(title: "Display Spec") {
                VStack {
                    if let display = selectedDisplay {
                        VStack(alignment: .leading) {
                            Text("\(display.displayName) (#\(display.displayID))")
                                .bold()
                                .multilineTextAlignment(.leading)
                            Text(String(localized: "main.display_switcher.layout.spec.resolution", defaultValue: "해상도"))
                            Picker("", selection: specBinding(for: display)) {
                                ForEach(Array(display.supportedSpecs.enumerated()), id: \.offset) { index, spec in
                                    Text(specLabel(spec)).tag(Int?.some(index))
                                }
                            }
                            .disabled(display.supportedSpecs.isEmpty)

                            Toggle(isOn: mainDisplayBinding(for: display)) {
                                Text(String(localized: "main.display_switcher.layout.spec.set_as_main", defaultValue: "메인 디스플레이로 설정"))
                            }
                            .disabled(effectiveMainDisplayID == display.displayID)
                        }
                        .padding()
                    } else {
                        Text(String(localized: "main.display_switcher.layout.empty", defaultValue: "디스플레이를 선택하세요"))
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                }
                .frame(maxWidth: 480, maxHeight: 320)
                .background(.white)
            }
            .fixedSize()
        }
    }

    @ViewBuilder
    private var actionBarView: some View {
        VStack(spacing: 8) {
            if let lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            HStack {
                Button(String(localized: "main.display_switcher.layout.action.revert", defaultValue: "되돌리기")) {
                    resetStagedOrigins()
                    collidingIDs.removeAll()
                    lastError = nil
                }
                .disabled(!isDirty || isApplying)

                Spacer()

                Button {
                    Task { await applyChanges() }
                } label: {
                    if isApplying {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(String(localized: "main.display_switcher.layout.action.apply", defaultValue: "적용하기"))
                    }
                }
                .disabled(!isDirty || isApplying || !collidingIDs.isEmpty)
            }
        }
        .padding()
        .background(.white)
    }

    // MARK: - Derived state

    private var sortedDisplays: [DisplayInfo] {
        displays.sorted { $0.displayID < $1.displayID }
    }

    private func size(of id: DisplayID) -> CGSize? {
        guard let display = displays.first(where: { $0.displayID == id }) else { return nil }
        return CGSize(width: display.bounds.width, height: display.bounds.height)
    }

    private func stagedRect(for id: DisplayID) -> CGRect? {
        guard let origin = stagedOrigins[id], let size = size(of: id) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private var stagedViewport: CGRect {
        let union = sortedDisplays
            .compactMap { stagedRect(for: $0.displayID) }
            .reduce(CGRect.null) { $0.union($1) }
        return union.isNull ? .zero : union
    }

    private var isDirty: Bool {
        if !stagedSpecs.isEmpty { return true }
        if let staged = stagedMainDisplayID, staged != currentMainDisplayID { return true }
        for display in displays {
            guard let staged = stagedOrigins[display.displayID] else { return true }
            if staged.x != display.bounds.x || staged.y != display.bounds.y { return true }
        }
        return false
    }

    // MARK: - Main Display

    private var currentMainDisplayID: DisplayID? {
        displays.first { $0.state.isPrimary }?.displayID
    }

    /// staged된 메인이 있으면 그것, 없으면 현재 서버 상태의 메인.
    private var effectiveMainDisplayID: DisplayID? {
        stagedMainDisplayID ?? currentMainDisplayID
    }

    /// 디스플레이별 '메인으로 지정' 토글 binding.
    /// OFF로 토글하는 동작은 무시한다 (메인은 항상 하나여야 하므로).
    /// 사용자가 원래 메인 디스플레이의 토글을 다시 켜면 staged 변경이 취소된다.
    private func mainDisplayBinding(for display: DisplayInfo) -> Binding<Bool> {
        Binding(
            get: { effectiveMainDisplayID == display.displayID },
            set: { newValue in
                guard newValue else { return }
                if currentMainDisplayID == display.displayID {
                    stagedMainDisplayID = nil
                } else {
                    stagedMainDisplayID = display.displayID
                }
            }
        )
    }

    // MARK: - Spec Selection

    /// 디스플레이의 현재 상태와 가장 잘 맞는 supportedSpec을 추정합니다.
    ///
    /// 서버 측에서 `bounds`는 NSScreen.frame, `supportedSpecs[].resolution`은 CGDisplayMode의
    /// (width, height) — 둘 다 동일한 logical point 단위이므로 직접 비교합니다.
    /// 정확 매칭이 실패하면 점진적으로 조건을 완화해서 fallback 합니다.
    private func currentSpec(for display: DisplayInfo) -> DisplaySpec? {
        // 1. resolution + refreshRate + scaleFactor 전부 일치
        if let exact = display.supportedSpecs.first(where: { spec in
            spec.resolution?.width == display.bounds.width
                && spec.resolution?.height == display.bounds.height
                && spec.refreshRate == display.refreshRate
                && spec.scaleFactor == display.scaleFactor
        }) {
            return exact
        }

        // 2. resolution + scaleFactor 일치 (built-in display의 refreshRate=0 케이스 등)
        if let resScale = display.supportedSpecs.first(where: { spec in
            spec.resolution?.width == display.bounds.width
                && spec.resolution?.height == display.bounds.height
                && spec.scaleFactor == display.scaleFactor
        }) {
            return resScale
        }

        // 3. resolution만 일치
        if let resOnly = display.supportedSpecs.first(where: { spec in
            spec.resolution?.width == display.bounds.width
                && spec.resolution?.height == display.bounds.height
        }) {
            return resOnly
        }

        return display.supportedSpecs.first
    }

    /// staged된 변경이 있으면 그 spec을, 없으면 현재 추정 spec을 반환합니다.
    private func effectiveSpec(for display: DisplayInfo) -> DisplaySpec? {
        stagedSpecs[display.displayID] ?? currentSpec(for: display)
    }

    private func areSpecsEqual(_ a: DisplaySpec, _ b: DisplaySpec) -> Bool {
        a.resolution?.width == b.resolution?.width
            && a.resolution?.height == b.resolution?.height
            && a.refreshRate == b.refreshRate
            && a.scaleFactor == b.scaleFactor
    }

    private func specBinding(for display: DisplayInfo) -> Binding<Int?> {
        Binding(
            get: {
                guard let target = effectiveSpec(for: display) else { return nil }
                return display.supportedSpecs.firstIndex { areSpecsEqual($0, target) }
            },
            set: { newIndex in
                guard let i = newIndex, display.supportedSpecs.indices.contains(i) else { return }
                let newSpec = display.supportedSpecs[i]
                if let current = currentSpec(for: display), areSpecsEqual(newSpec, current) {
                    stagedSpecs.removeValue(forKey: display.displayID)
                } else {
                    stagedSpecs[display.displayID] = newSpec
                }
            }
        )
    }

    private func specLabel(_ spec: DisplaySpec) -> String {
        let resolutionText: String
        if let res = spec.resolution {
            resolutionText = "\(Int(res.width))×\(Int(res.height))"
        } else {
            resolutionText = "(unknown)"
        }
        let hzText = "\(Int(spec.refreshRate.rounded()))Hz"
        let scaleText = String(format: "%.1fx", spec.scaleFactor)
        return "\(resolutionText) @ \(hzText) (\(scaleText))"
    }

    // MARK: - Display Item

    @ViewBuilder
    private func displayItemView(for display: DisplayInfo, scale: CGFloat, viewportOrigin: CGPoint) -> some View {
        let id = display.displayID
        let origin = stagedOrigins[id] ?? CGPoint(x: display.bounds.x, y: display.bounds.y)
        let size = CGSize(width: display.bounds.width, height: display.bounds.height)

        let scaledRect = CGRect(
            x: (origin.x - viewportOrigin.x) * scale,
            y: (origin.y - viewportOrigin.y) * scale,
            width: size.width * scale,
            height: size.height * scale
        )

        let isDragging = draggingID == id
        let isColliding = collidingIDs.contains(id)
        let isSelected = selectedDisplayID == id
        let borderColor: Color = isColliding ? .red
            : isDragging ? .blue
            : isSelected ? .accentColor
            : (display.state.isPrimary ? .red : .black)
        let borderWidth: CGFloat = (isColliding || isDragging || isSelected) ? 2 : 1

        VStack {
            Spacer()
            Text(display.displayName)
                .bold()
            Spacer()
        }
        .multilineTextAlignment(.center)
        .padding()
        .frame(width: scaledRect.width, height: scaledRect.height)
        .background {
            displayThumbnailView(for: display)
                .frame(width: scaledRect.width, height: scaledRect.height)
        }
        .overlay {
            if isColliding {
                Color.red.opacity(0.25)
            }
        }
        .border(borderColor, width: borderWidth)
        .position(x: scaledRect.midX, y: scaledRect.midY)
        .onTapGesture {
            selectedDisplayID = id
        }
        .gesture(dragGesture(for: id, scale: scale))
    }

    @ViewBuilder
    private func displayThumbnailView(for display: DisplayInfo) -> some View {
        ZStack {
            if let thumbnail = display.thumbnail, let image = platformImage(from: thumbnail) {
                Image(decorative: image, scale: 1.0)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            Rectangle()
                .fill(.white)
                .opacity(0.3)
        }
    }

    // MARK: - Drag

    private func dragGesture(for id: DisplayID, scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragStartOrigin == nil {
                    dragStartOrigin = stagedOrigins[id]
                    draggingID = id
                }
                guard let start = dragStartOrigin else { return }

                var candidate = CGPoint(
                    x: start.x + value.translation.width / scale,
                    y: start.y + value.translation.height / scale
                )
                candidate = applyMagneticSnap(candidate, draggedID: id, scale: scale)

                stagedOrigins[id] = candidate
                collidingIDs = collisions(with: id)
            }
            .onEnded { _ in
                let start = dragStartOrigin
                dragStartOrigin = nil
                draggingID = nil
                selectedDisplayID = id

                if !collisions(with: id).isEmpty, let start {
                    stagedOrigins[id] = start
                    collidingIDs.removeAll()
                }
            }
    }

    private func applyMagneticSnap(_ candidate: CGPoint, draggedID: DisplayID, scale: CGFloat) -> CGPoint {
        guard let size = size(of: draggedID) else { return candidate }
        let threshold = snapThresholdScaled / scale

        var snappedX = candidate.x
        var snappedY = candidate.y
        var bestDX: CGFloat = .greatestFiniteMagnitude
        var bestDY: CGFloat = .greatestFiniteMagnitude

        for other in displays where other.displayID != draggedID {
            guard let oRect = stagedRect(for: other.displayID) else { continue }

            let xCandidates: [CGFloat] = [
                oRect.maxX,                  // dLeft = oRight
                oRect.minX - size.width,     // dRight = oLeft
                oRect.minX,                  // 같은 좌측 정렬
                oRect.maxX - size.width      // 같은 우측 정렬
            ]
            for newX in xCandidates {
                let dx = abs(newX - candidate.x)
                if dx < threshold && dx < bestDX {
                    bestDX = dx
                    snappedX = newX
                }
            }

            let yCandidates: [CGFloat] = [
                oRect.maxY,                  // dTop = oBottom
                oRect.minY - size.height,    // dBottom = oTop
                oRect.minY,                  // 같은 상단 정렬
                oRect.maxY - size.height     // 같은 하단 정렬
            ]
            for newY in yCandidates {
                let dy = abs(newY - candidate.y)
                if dy < threshold && dy < bestDY {
                    bestDY = dy
                    snappedY = newY
                }
            }
        }

        return CGPoint(x: snappedX, y: snappedY)
    }

    private func collisions(with draggedID: DisplayID) -> Set<DisplayID> {
        guard let dRect = stagedRect(for: draggedID) else { return [] }
        var result: Set<DisplayID> = []
        for other in displays where other.displayID != draggedID {
            guard let oRect = stagedRect(for: other.displayID) else { continue }
            let intersection = dRect.intersection(oRect)
            if !intersection.isNull && intersection.width > 0.5 && intersection.height > 0.5 {
                result.insert(other.displayID)
                result.insert(draggedID)
            }
        }
        return result
    }

    // MARK: - Apply / Reset

    private func resetStagedOrigins() {
        var next: [DisplayID: CGPoint] = [:]
        for d in displays {
            next[d.displayID] = CGPoint(x: d.bounds.x, y: d.bounds.y)
        }
        stagedOrigins = next
        stagedSpecs.removeAll()
        stagedMainDisplayID = nil
    }

    private func applyChanges() async {
        var operations: [DisplayOperation] = []
        for d in displays {
            let stagedOrigin = stagedOrigins[d.displayID]
            let positionChanged = stagedOrigin.map { $0.x != d.bounds.x || $0.y != d.bounds.y } ?? false
            let stagedSpec = stagedSpecs[d.displayID]
            let specChanged = stagedSpec != nil

            guard positionChanged || specChanged else { continue }

            let change = DisplayLayoutChange(
                displayID: d.displayID,
                spec: stagedSpec,
                rotation: nil,
                origin: positionChanged ? stagedOrigin.map { SRPoint(x: $0.x, y: $0.y) } : nil
            )
            operations.append(DisplayOperation(operation: .change(change)))
        }

        let mainChanged = stagedMainDisplayID != nil && stagedMainDisplayID != currentMainDisplayID
        let mainIDToSend: UInt32? = mainChanged ? stagedMainDisplayID : nil

        guard !operations.isEmpty || mainChanged else { return }

        isApplying = true
        lastError = nil
        do {
            try await onApply(operations, mainIDToSend)
        } catch {
            lastError = String(describing: error)
        }
        isApplying = false
    }

    private func platformImage(from data: Data) -> CGImage? {
        #if os(macOS)
        return NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        return UIImage(data: data)?.cgImage
        #endif
    }
}

// MARK: - Helpers

private struct DisplayKey: Hashable {
    let id: UInt32
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(id: UInt32, bounds: SRRect) {
        self.id = id
        self.x = bounds.x
        self.y = bounds.y
        self.width = bounds.width
        self.height = bounds.height
    }
}
