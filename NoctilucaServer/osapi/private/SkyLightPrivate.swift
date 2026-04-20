//
//  SkyLightPrivate.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 4/12/26.
//
//  ref: https://github.com/xorpse/yabai (src/misc/extern.h)

import Foundation
import CoreGraphics

import Gesu

// NOTE: CGSConnectionID는 CoreGraphicsPrivate.swift에 정의되어 있음

// MARK: - CGSWindowTagBit
// ref: https://github.com/NUIKit/CGSInternal (CGSWindow.h)
// ref: https://github.com/koekeishiya/yabai (src/misc/extern.h, src/window.c)

struct CGSWindowTag: OptionSet, Sendable {
    let rawValue: UInt64

    // MARK: Lo Word (bits 0-31)

    /// 기본 document 윈도우 스타일
    static let documentWindow                   = CGSWindowTag(rawValue: 1 << 0)
    /// 플로팅 윈도우
    static let floatingWindow                   = CGSWindowTag(rawValue: 1 << 1)
    /// Dock 타일 배지 비활성화
    static let doNotShowBadgeInDock             = CGSWindowTag(rawValue: 1 << 2)
    /// 윈도우 그림자 비활성화
    static let disableShadow                    = CGSWindowTag(rawValue: 1 << 3)
    /// 고품질 리샘플링 활성화
    static let highQualityResampling            = CGSWindowTag(rawValue: 1 << 4)
    /// 비활성 앱에서도 커서 변경 가능
    static let setsCursorInBackground           = CGSWindowTag(rawValue: 1 << 5)
    /// 모달 런 루프 중에도 동작
    static let worksWhenModal                   = CGSWindowTag(rawValue: 1 << 6)
    /// 다른 윈도우에 앵커링
    static let attachedWindow                   = CGSWindowTag(rawValue: 1 << 7)
    /// 드래그 중 100% 불투명하게 표시
    static let ignoreAlphaForDragging           = CGSWindowTag(rawValue: 1 << 8)
    /// 마우스 이벤트 투과 (click-through)
    static let ignoreForEvents                  = CGSWindowTag(rawValue: 1 << 9)
    /// 이벤트에 불투명 (ignoreForEvents와 상호 배타적)
    static let opaqueForEvents                  = CGSWindowTag(rawValue: 1 << 10)
    /// 모든 Space에 표시 (sticky)
    static let onAllWorkspaces                  = CGSWindowTag(rawValue: 1 << 11)
    /// (미문서화)
    static let pointerEventsAvoidCPS            = CGSWindowTag(rawValue: 1 << 12)
    /// (미문서화)
    static let kitVisible                       = CGSWindowTag(rawValue: 1 << 13)
    /// 앱 비활성화 시 윈도우 목록에서 제거
    static let hideOnDeactivate                 = CGSWindowTag(rawValue: 1 << 14)
    /// 표시 시 앱을 포그라운드로 가져오지 않음
    static let avoidsActivation                 = CGSWindowTag(rawValue: 1 << 15)
    /// 선택 시 앱을 포그라운드로 가져오지 않음
    static let preventsActivation               = CGSWindowTag(rawValue: 1 << 16)
    /// (미문서화)
    static let ignoresOption                    = CGSWindowTag(rawValue: 1 << 17)
    /// 윈도우 순환(Cmd+F4 등)에서 제외
    static let ignoresCycle                     = CGSWindowTag(rawValue: 1 << 18)
    /// (미문서화)
    static let defersOrdering                   = CGSWindowTag(rawValue: 1 << 19)
    /// (미문서화)
    static let defersActivation                 = CGSWindowTag(rawValue: 1 << 20)
    /// WindowServer가 order-front 요청을 무시
    static let ignoreAsFrontWindow              = CGSWindowTag(rawValue: 1 << 21)
    /// WindowServer가 드래그 rect를 통해 윈도우 이동 제어
    static let enableServerSideDrag             = CGSWindowTag(rawValue: 1 << 22)
    /// (미문서화)
    static let mouseDownEventsGrabbed           = CGSWindowTag(rawValue: 1 << 23)
    /// 숨기기 요청 무시
    static let dontHide                         = CGSWindowTag(rawValue: 1 << 24)
    /// (미문서화)
    static let dontDimWindowDisplay             = CGSWindowTag(rawValue: 1 << 25)
    /// 진입 시 커서를 윈도우의 포인터 타입으로 변환
    static let instantMouserWindow              = CGSWindowTag(rawValue: 1 << 26)
    /// 활성 Space에 표시, Space 전환 추적
    static let windowOwnerFollowsForeground     = CGSWindowTag(rawValue: 1 << 27)
    /// (미문서화)
    static let activationWindowLevel            = CGSWindowTag(rawValue: 1 << 28)
    /// 선택 시 소유 앱을 포그라운드로 가져옴
    static let bringOwningApplicationForward    = CGSWindowTag(rawValue: 1 << 29)
    /// 로그인 화면 위에 표시 허용
    static let permittedBeforeLogin             = CGSWindowTag(rawValue: 1 << 30)
    /// 모달 윈도우
    static let modalWindow                      = CGSWindowTag(rawValue: 1 << 31)

    // MARK: Hi Word (bits 32-63)

    /// Dock처럼 그리기 ("Magic Mirror")
    static let windowIsMagicMirror              = CGSWindowTag(rawValue: 1 << 33)
    /// (미문서화)
    static let followsUser                      = CGSWindowTag(rawValue: 1 << 34)
    /// (미문서화)
    static let windowDoesNotCastMirrorReflection = CGSWindowTag(rawValue: 1 << 35)
    /// (미문서화)
    static let meshedWindow                     = CGSWindowTag(rawValue: 1 << 36)
    /// CoreDrag에 의해 드래그 중일 때 설정됨
    static let coreDragIsDraggingWindow         = CGSWindowTag(rawValue: 1 << 37)
    /// 화면 캡처 회피
    static let avoidsCapture                    = CGSWindowTag(rawValue: 1 << 38)
    /// Mission Control / Exposé에서 무시
    static let ignoreForExpose                  = CGSWindowTag(rawValue: 1 << 39)
    /// 윈도우가 숨겨진 상태
    static let hidden                           = CGSWindowTag(rawValue: 1 << 40)
    /// 윈도우 순환에 명시적으로 포함
    static let includeInCycle                   = CGSWindowTag(rawValue: 1 << 41)
    /// 비포그라운드에서도 제스처 이벤트 캡처
    static let wantGesturesInBackground         = CGSWindowTag(rawValue: 1 << 42)
    /// 풀스크린 상태
    static let fullScreen                       = CGSWindowTag(rawValue: 1 << 43)
    /// (미문서화)
    static let windowIsMagicZoom                = CGSWindowTag(rawValue: 1 << 44)
    /// "슈퍼 스티키" (미문서화)
    static let superSticky                      = CGSWindowTag(rawValue: 1 << 45)
    /// 메뉴 바에 부착
    static let attachesToMenuBar                = CGSWindowTag(rawValue: 1 << 46)
    /// 메뉴 바에 표시 (메뉴 바 아이템용)
    static let mergesWithMenuBar                = CGSWindowTag(rawValue: 1 << 47)
    /// 절대 sticky 하지 않음
    static let neverSticky                      = CGSWindowTag(rawValue: 1 << 48)
    /// 데스크톱 배경 레벨에 표시
    static let desktopPicture                   = CGSWindowTag(rawValue: 1 << 49)
    /// 리드로우 시 앞으로 이동 (디버그용)
    static let ordersForwardWhenSurfaceFlushed  = CGSWindowTag(rawValue: 1 << 50)
    /// (미문서화)
    static let dragsMovementGroupParent         = CGSWindowTag(rawValue: 1 << 51)
    /// (미문서화)
    static let neverFlattenSurfacesDuringSwipes = CGSWindowTag(rawValue: 1 << 52)
    /// 풀스크린 가능
    static let fullScreenCapable                = CGSWindowTag(rawValue: 1 << 53)
    /// 풀스크린 타일 가능
    static let fullScreenTileCapable            = CGSWindowTag(rawValue: 1 << 54)
}

extension CGSWindowTag: CustomDebugStringConvertible {
    private static let knownTags: [(CGSWindowTag, String)] = [
        (.documentWindow, "documentWindow"),
        (.floatingWindow, "floatingWindow"),
        (.doNotShowBadgeInDock, "doNotShowBadgeInDock"),
        (.disableShadow, "disableShadow"),
        (.highQualityResampling, "highQualityResampling"),
        (.setsCursorInBackground, "setsCursorInBackground"),
        (.worksWhenModal, "worksWhenModal"),
        (.attachedWindow, "attachedWindow"),
        (.ignoreAlphaForDragging, "ignoreAlphaForDragging"),
        (.ignoreForEvents, "ignoreForEvents"),
        (.opaqueForEvents, "opaqueForEvents"),
        (.onAllWorkspaces, "onAllWorkspaces"),
        (.pointerEventsAvoidCPS, "pointerEventsAvoidCPS"),
        (.kitVisible, "kitVisible"),
        (.hideOnDeactivate, "hideOnDeactivate"),
        (.avoidsActivation, "avoidsActivation"),
        (.preventsActivation, "preventsActivation"),
        (.ignoresOption, "ignoresOption"),
        (.ignoresCycle, "ignoresCycle"),
        (.defersOrdering, "defersOrdering"),
        (.defersActivation, "defersActivation"),
        (.ignoreAsFrontWindow, "ignoreAsFrontWindow"),
        (.enableServerSideDrag, "enableServerSideDrag"),
        (.mouseDownEventsGrabbed, "mouseDownEventsGrabbed"),
        (.dontHide, "dontHide"),
        (.dontDimWindowDisplay, "dontDimWindowDisplay"),
        (.instantMouserWindow, "instantMouserWindow"),
        (.windowOwnerFollowsForeground, "windowOwnerFollowsForeground"),
        (.activationWindowLevel, "activationWindowLevel"),
        (.bringOwningApplicationForward, "bringOwningApplicationForward"),
        (.permittedBeforeLogin, "permittedBeforeLogin"),
        (.modalWindow, "modalWindow"),
        (.windowIsMagicMirror, "windowIsMagicMirror"),
        (.followsUser, "followsUser"),
        (.windowDoesNotCastMirrorReflection, "windowDoesNotCastMirrorReflection"),
        (.meshedWindow, "meshedWindow"),
        (.coreDragIsDraggingWindow, "coreDragIsDraggingWindow"),
        (.avoidsCapture, "avoidsCapture"),
        (.ignoreForExpose, "ignoreForExpose"),
        (.hidden, "hidden"),
        (.includeInCycle, "includeInCycle"),
        (.wantGesturesInBackground, "wantGesturesInBackground"),
        (.fullScreen, "fullScreen"),
        (.windowIsMagicZoom, "windowIsMagicZoom"),
        (.superSticky, "superSticky"),
        (.attachesToMenuBar, "attachesToMenuBar"),
        (.mergesWithMenuBar, "mergesWithMenuBar"),
        (.neverSticky, "neverSticky"),
        (.desktopPicture, "desktopPicture"),
        (.ordersForwardWhenSurfaceFlushed, "ordersForwardWhenSurfaceFlushed"),
        (.dragsMovementGroupParent, "dragsMovementGroupParent"),
        (.neverFlattenSurfacesDuringSwipes, "neverFlattenSurfacesDuringSwipes"),
        (.fullScreenCapable, "fullScreenCapable"),
        (.fullScreenTileCapable, "fullScreenTileCapable"),
    ]

    var debugDescription: String {
        var names: [String] = []
        for (tag, name) in Self.knownTags where contains(tag) {
            names.append(name)
        }
        if names.isEmpty {
            return "Tag: [] (rawValue: 0x\(String(rawValue, radix: 16)))"
        }
        return "Tag: [\(names.joined(separator: ", "))]"
    }
}

@PrivateLibrary(path: "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight")
class SkyLightPrivate {
    // MARK: - Connection

    #PrivateFunction(
        "SLSMainConnectionID",
        args: (),
        ret: CGSConnectionID.self
    )

    #PrivateFunction(
        "SLSGetConnectionPSN",
        args: (
            CGSConnectionID.self,
            UnsafeMutablePointer<ProcessSerialNumber>.self
        ),
        ret: CGError.self
    )

    #PrivateFunction(
        "SLSConnectionGetPID",
        args: (
            CGSConnectionID.self,
            UnsafeMutablePointer<pid_t>.self
        ),
        ret: CGError.self
    )

    // MARK: - Window Properties

    #PrivateFunction(
        "SLSGetWindowOwner",
        args: (
            CGSConnectionID.self,
            CGWindowID.self,
            UnsafeMutablePointer<CGSConnectionID>.self
        ),
        ret: CGError.self
    )

    #PrivateFunction(
        "SLSGetWindowBounds",
        args: (
            CGSConnectionID.self,
            CGWindowID.self,
            UnsafeMutablePointer<CGRect>.self
        ),
        ret: CGError.self
    )

    #PrivateFunction(
        "SLSGetWindowLevel",
        args: (
            CGSConnectionID.self,
            CGWindowID.self,
            UnsafeMutablePointer<Int32>.self
        ),
        ret: CGError.self
    )

    #PrivateFunction(
        "SLSGetWindowAlpha",
        args: (
            CGSConnectionID.self,
            CGWindowID.self,
            UnsafeMutablePointer<Float>.self
        ),
        ret: CGError.self
    )

    #PrivateFunction(
        "SLSSetWindowResolution",
        args: (
            CGSConnectionID.self,
            CGWindowID.self,
            Double.self
        ),
        ret: CGError.self
    )

    #PrivateFunction(
        "SLSSetWindowLevel",
        args: (
            CGSConnectionID.self,
            CGWindowID.self,
            Int32.self
        ),
        ret: CGError.self
    )

    #PrivateFunction(
        "SLSSetWindowOpacity",
        args: (
            CGSConnectionID.self,
            CGWindowID.self,
            Bool.self
        ),
        ret: CGError.self
    )

    #PrivateFunction(
        "SLSSetWindowTags",
        args: (
            CGSConnectionID.self,
            CGWindowID.self,
            UnsafeMutablePointer<UInt64>.self,
            Int32.self
        ),
        ret: CGError.self
    )

    #PrivateFunction(
        "SLSCopyWindowProperty",
        args: (
            CGSConnectionID.self,
            CGWindowID.self,
            CFString.self,
            UnsafeMutablePointer<CFTypeRef?>.self
        ),
        ret: CGError.self
    )

    // MARK: - Window Operations

    #PrivateFunction(
        "SLSOrderWindow",
        args: (
            CGSConnectionID.self,
            CGWindowID.self,
            Int32.self,
            CGWindowID.self
        ),
        ret: CGError.self
    )

    #PrivateFunction(
        "SLSMoveWindow",
        args: (
            CGSConnectionID.self,
            CGWindowID.self,
            UnsafeMutablePointer<CGPoint>.self
        ),
        ret: CGError.self
    )

    // MARK: - Associated Windows (Parent-Child)

    #PrivateFunction(
        "SLSCopyAssociatedWindows",
        args: (
            CGSConnectionID.self,
            CGWindowID.self
        ),
        ret: CFArray?.self
    )

    // MARK: - Window Query / Iterator

    #PrivateFunction(
        "SLSWindowQueryWindows",
        args: (
            CGSConnectionID.self,
            CFArray.self,
            Int32.self
        ),
        ret: CFTypeRef?.self
    )

    #PrivateFunction(
        "SLSWindowQueryResultCopyWindows",
        args: (CFTypeRef.self,),
        ret: CFTypeRef?.self
    )

    #PrivateFunction(
        "SLSWindowIteratorAdvance",
        args: (CFTypeRef.self,),
        ret: CGError.self
    )

    #PrivateFunction(
        "SLSWindowIteratorGetParentID",
        args: (CFTypeRef.self,),
        ret: CGWindowID.self
    )

    #PrivateFunction(
        "SLSWindowIteratorGetWindowID",
        args: (CFTypeRef.self,),
        ret: CGWindowID.self
    )

    #PrivateFunction(
        "SLSWindowIteratorGetTags",
        args: (CFTypeRef.self,),
        ret: UInt64.self
    )

    #PrivateFunction(
        "SLSWindowIteratorGetAttributes",
        args: (CFTypeRef.self,),
        ret: UInt64.self
    )

    // MARK: - Display / Space Management

    #PrivateFunction(
        "SLSCopyManagedDisplays",
        args: (CGSConnectionID.self,),
        ret: CFArray?.self
    )

    #PrivateFunction(
        "SLSCopyManagedDisplayForWindow",
        args: (
            CGSConnectionID.self,
            CGWindowID.self
        ),
        ret: CFString?.self
    )

    #PrivateFunction(
        "SLSCopyBestManagedDisplayForRect",
        args: (
            CGSConnectionID.self,
            CGRect.self
        ),
        ret: CFString?.self
    )

    #PrivateFunction(
        "SLSCopyBestManagedDisplayForPoint",
        args: (
            CGSConnectionID.self,
            CGPoint.self
        ),
        ret: CFString?.self
    )

    #PrivateFunction(
        "SLSCopyActiveMenuBarDisplayIdentifier",
        args: (CGSConnectionID.self,),
        ret: CFString?.self
    )

    #PrivateFunction(
        "SLSManagedDisplayGetCurrentSpace",
        args: (
            CGSConnectionID.self,
            CFString.self
        ),
        ret: UInt64.self
    )

    #PrivateFunction(
        "SLSManagedDisplayIsAnimating",
        args: (
            CGSConnectionID.self,
            CFString.self
        ),
        ret: Bool.self
    )

    #PrivateFunction(
        "SLSCopyManagedDisplaySpaces",
        args: (CGSConnectionID.self,),
        ret: CFArray?.self
    )

    #PrivateFunction(
        "SLSCopyManagedDisplayForSpace",
        args: (
            CGSConnectionID.self,
            UInt64.self
        ),
        ret: CFString?.self
    )

    // MARK: - Display Enable / Disable

    /// 지정한 디스플레이의 enable/disable 변경을 display config transaction에 추가한다.
    ///
    /// - Parameter config: `SLSBeginDisplayConfiguration` 등으로 획득한 config 핸들.
    /// - Note: 실제 적용은 `SLSCompleteDisplayConfiguration` 호출 시점이며, 이 함수 자체는
    ///         pending 리스트에 항목을 append 할 뿐이다.
    /// - Warning: 비활성화는 영구적이지 않으나, 복원 책임은 호출자에 있다.
    ///            프로세스가 비정상 종료되면 해당 디스플레이는 비활성화된 채로 남을 수 있다.
    #PrivateFunction(
        "SLSConfigureDisplayEnabled",
        args: (
            CGDisplayConfigRef.self,
            CGDirectDisplayID.self,
            Bool.self
        ),
        ret: CGError.self
    )

    // MARK: - Space Properties

    #PrivateFunction(
        "SLSSpaceGetType",
        args: (
            CGSConnectionID.self,
            UInt64.self
        ),
        ret: Int32.self
    )

    #PrivateFunction(
        "SLSSpaceCopyName",
        args: (
            CGSConnectionID.self,
            UInt64.self
        ),
        ret: CFString?.self
    )

    #PrivateFunction(
        "SLSCopySpacesForWindows",
        args: (
            CGSConnectionID.self,
            Int32.self,
            CFArray.self
        ),
        ret: CFArray?.self
    )

    #PrivateFunction(
        "SLSCopyWindowsWithOptionsAndTags",
        args: (
            CGSConnectionID.self,
            UInt32.self,
            CFArray.self,
            UInt32.self,
            UnsafeMutablePointer<UInt64>.self,
            UnsafeMutablePointer<UInt64>.self
        ),
        ret: CFArray?.self
    )

    // MARK: - Space / Process Assignment

    #PrivateFunction(
        "SLSMoveWindowsToManagedSpace",
        args: (
            CGSConnectionID.self,
            CFArray.self,
            UInt64.self
        ),
        ret: Void.self
    )

    #PrivateFunction(
        "SLSProcessAssignToSpace",
        args: (
            CGSConnectionID.self,
            pid_t.self,
            UInt64.self
        ),
        ret: CGError.self
    )

    #PrivateFunction(
        "SLSProcessAssignToAllSpaces",
        args: (
            CGSConnectionID.self,
            pid_t.self
        ),
        ret: CGError.self
    )

    // MARK: - Menu Bar / Dock

    #PrivateFunction(
        "SLSGetMenuBarAutohideEnabled",
        args: (
            CGSConnectionID.self,
            UnsafeMutablePointer<Int32>.self
        ),
        ret: CGError.self
    )

    #PrivateFunction(
        "SLSGetRevealedMenuBarBounds",
        args: (
            UnsafeMutablePointer<CGRect>.self,
            CGSConnectionID.self,
            UInt64.self
        ),
        ret: CGError.self
    )

    #PrivateFunction(
        "SLSGetDockRectWithReason",
        args: (
            CGSConnectionID.self,
            UnsafeMutablePointer<CGRect>.self,
            UnsafeMutablePointer<Int32>.self
        ),
        ret: CGError.self
    )

    // MARK: - Display Update Control

    #PrivateFunction(
        "SLSDisableUpdate",
        args: (CGSConnectionID.self,),
        ret: CGError.self
    )

    #PrivateFunction(
        "SLSReenableUpdate",
        args: (CGSConnectionID.self,),
        ret: CGError.self
    )

    // MARK: - Window Creation / Destruction

    #PrivateFunction(
        "SLSNewWindow",
        args: (
            CGSConnectionID.self,
            Int32.self,
            Float.self,
            Float.self,
            CFTypeRef.self,
            UnsafeMutablePointer<CGWindowID>.self
        ),
        ret: CGError.self
    )

    #PrivateFunction(
        "SLSReleaseWindow",
        args: (
            CGSConnectionID.self,
            CGWindowID.self
        ),
        ret: CGError.self
    )

    #PrivateFunction(
        "SLSSetWindowShape",
        args: (
            CGSConnectionID.self,
            CGWindowID.self,
            Float.self,
            Float.self,
            CFTypeRef.self
        ),
        ret: CGError.self
    )

    #PrivateFunction(
        "SLWindowContextCreate",
        args: (
            CGSConnectionID.self,
            CGWindowID.self,
            CFDictionary?.self
        ),
        ret: CGContext?.self
    )

    // MARK: - Cursor

    #PrivateFunction(
        "SLSGetCurrentCursorLocation",
        args: (
            CGSConnectionID.self,
            UnsafeMutablePointer<CGPoint>.self
        ),
        ret: CGError.self
    )

    // MARK: - Hit Testing

    #PrivateFunction(
        "SLSFindWindowByGeometry",
        args: (
            CGSConnectionID.self,
            Int32.self,
            Int32.self,
            Int32.self,
            UnsafeMutablePointer<CGPoint>.self,
            UnsafeMutablePointer<CGPoint>.self,
            UnsafeMutablePointer<CGWindowID>.self,
            UnsafeMutablePointer<CGSConnectionID>.self
        ),
        ret: OSStatus.self
    )

    #PrivateFunction(
        "SLSGetSpaceManagementMode",
        args: (CGSConnectionID.self,),
        ret: Int32.self
    )
}
