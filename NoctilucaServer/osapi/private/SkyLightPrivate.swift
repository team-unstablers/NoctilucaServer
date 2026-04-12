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
