//
//  WindowFilter.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 12/26/25.
//

import Foundation


public enum WindowFilterExpressionField {
    /// 윈도우 핸들 ID로 매칭합니다.
    /// @note OS / DM에 따라 윈도우 핸들 ID의 크기가 다를 수 있으므로 fixed64 타입을 사용합니다.
    case windowID(UInt64)
    
    /// 프로세스 ID로 매칭합니다.
    case pid(UInt64)
    
    /// 윈도우 타이틀로 매칭합니다.
    case windowTitle(String)
    
    /// 애플리케이션 이름(실행 파일 이름)으로 매칭합니다.
    /// ## NOTE: Platform Differences
    /// - Windows의 경우 실행 파일 이름 (예: "chrome.exe")을 의미합니다.
    /// - macOS / Linux의 경우 프로세스 이름 (ARGV[0])을 의미합니다. 이는 전체 경로일 수도 있고, 단순 실행 파일 이름일 수도 있습니다.
    ///   - eg: `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome`
    ///   - eg: `/usr/bin/google-chrome-stable`
    ///   - eg: `nginx: worker process` (자기 자신의 ARGV[0]을 수정하는 케이스)
    ///   - eg: `python3 script.py` (전체 경로가 아닌 실행 파일만 나타나는 케이스)
    case applicationName(String)
    
    /// 번들 ID로 매칭합니다.
    /// - 의미는 서버 구현체에 따라 다를 수 있습니다.
    ///   Noctiluca의 경우 macOS의 번들 ID (예: "com.apple.Safari")를 의미합니다.
    /// - eg) Android의 경우 패키지 이름 (예: "com.google.android.youtube")을 의미할 수 있습니다.
    case applicationBundleID(String)
    
    /// 윈도우 클래스 이름으로 매칭합니다.
    /// - macOS는 클래스 이름을 지원하지 않으므로 이 필드는 무시될 수 있습니다.
    case windowClass(String)
}


public struct WindowFilterExpression: @unchecked Sendable {
    public let field: WindowFilterExpressionField
    package(set) public var `operator`: WindowFilterExpressionOperator
    package(set) public var invert: Bool
    
    public init(_ field: WindowFilterExpressionField) {
        self.field = field
        self.operator = .matchExact
        self.invert = false
    }
    
    public func exact() -> Self {
        var mutated = self
        mutated.operator = .matchExact
        
        return mutated
    }
    
    public func contains() -> Self {
        var mutated = self
        mutated.operator = .matchContains
        
        return mutated
    }
    
    public func icontains() -> Self {
        var mutated = self
        mutated.operator = .matchIContains
        
        return mutated
    }
    
    public func regex() -> Self {
        var mutated = self
        mutated.operator = .matchRegex
        
        return mutated
    }
    
    public func inverted() -> Self {
        var mutated = self
        mutated.invert = true
        
        return mutated
    }
}


public extension WindowFilterExpression {
    static func windowID(_ value: UInt64) -> Self {
        return Self(.windowID(value))
    }
    
    static func pid(_ value: UInt64) -> Self {
        return Self(.pid(value))
    }
    
    static func windowTitle(_ value: String) -> Self {
        return Self(.windowTitle(value))
    }
    
    static func applicationName(_ value: String) -> Self {
        return Self(.applicationName(value))
    }
    
    static func applicationBundleID(_ value: String) -> Self {
        return Self(.applicationBundleID(value))
    }
    
    static func windowClass(_ value: String) -> Self {
        return Self(.windowClass(value))
    }
}

public struct WindowFilter: Sendable {
    public typealias Operator = WindowFilterOperator
    
    public let `operator`: Operator
    public let expressions: [WindowFilter]
    public let expression: WindowFilterExpression?
    
    public init(_ `operator`: Operator, expressions: [WindowFilter]) {
        self.operator = `operator`
        self.expressions = expressions
        self.expression = nil
    }
    
    public init(expression: WindowFilterExpression) {
        self.operator = .or
        self.expressions = []
        self.expression = expression
    }
}

public extension WindowFilter {
    static func `or`(_ expressions: [WindowFilter]) -> Self {
        return Self(.or, expressions: expressions)
    }
    
    static func `and`(_ expressions: [WindowFilter]) -> Self {
        return Self(.and, expressions: expressions)
    }
    
    static func `expr`(_ expression: WindowFilterExpression) -> Self {
        return Self(expression: expression)
    }
}


