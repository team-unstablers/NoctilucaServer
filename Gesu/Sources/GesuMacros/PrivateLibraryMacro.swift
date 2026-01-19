//
//  PrivateLibraryMacro.swift
//  Gesu
//
//  Created by Gyuhwan Park on 1/19/26.
//

import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// 구현 로직 (Pseudo-code)
public struct PrivateLibraryMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) -> [DeclSyntax] {
        guard case .argumentList(let arguments) = node.arguments else {
            return []
        }
        
        guard let pathArg = arguments.first(where: { $0.label?.text == "path" }),
              let stringExpr = pathArg.expression.as(StringLiteralExprSyntax.self),
              let pathValue = stringExpr.representedLiteralValue
        else {
            return []
        }
        
        // arguments에서 추출
        return [
            """
                nonisolated(unsafe) private static var _libraryHandle: UnsafeMutableRawPointer?
            
                public static func open() throws {
                    guard _libraryHandle == nil else { return }
            
                    let handle = dlopen("\(raw: pathValue)", RTLD_NOW)
                    if handle == nil { 
                        throw Gesu.PrivateLibraryError.dlopenFailed
                    }
            
                    _libraryHandle = handle
                }
            """
        ]
    }
}
