//
//  KeyboardHackPluginV1.swift
//  NoctilucaPluginKit
//
//  Created by Gyuhwan Park on 2/14/26.
//

import Foundation

public enum KeyboardHackResult {
    /// 다음 파이프라인으로 키보드 입력이 전달됩니다.
    case passthrough
    
    /// 키보드 입력이 수정되어 다음 파이프라인으로 전달됩니다.
    case modify(KeySequence)
    
    /// 키보드 입력을 전달하지 않습니다.
    case stop
}

public protocol KeyboardHackPluginV1: AnyObject {
    static var id: String { get }
    static var name: String { get }
    static var description: String { get }
    
    static var authors: [String] { get }
    static var license: SoftwareLicense { get }
    
    static var version: UInt32 { get }
    static var displayVersion: String { get }
    
    /// 보안을 위해 모든 플러그인은 받고자 하는 키 이벤트를 명시적으로 선언해야만 합니다.
    /// 서버는 여기에 명시된 키 이벤트 외에는 플러그인에게 전달하지 않습니다.
    static var desiredKeyEvents: Set<LinuxKeycode> { get }
    
    init()
    
    /// 서버가 클라이언트로부터 키보드 입력 (down)을 받았습니다.
    func onKeyDown(_ keyCode: LinuxKeycode) async -> KeyboardHackResult
    /// 서버가 클라이언트로부터 키보드 입력 (up)을 받았습니다.
    func onKeyUp(_ keyCode: LinuxKeycode) async -> KeyboardHackResult
}



