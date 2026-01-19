//
//  PrivateFunctionMacro.swift
//  Gesu
//
//  Created by Gyuhwan Park on 1/19/26.
//

import Foundation

import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct PrivateFunctionMacro: DeclarationMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let arguments = node.arguments
        
        
        guard let nameArg = arguments.first,
              let nameExpr = nameArg.expression.as(StringLiteralExprSyntax.self),
              let funcName = nameExpr.representedLiteralValue
        else {
            return [
                """
                #error("PrivateFunctionMacro: failed to parse name")
                """
            ]
        }
        
        guard let argsArg = arguments.first(where: { $0.label?.text == "args" }),
              let argsExpr = argsArg.expression.as(TupleExprSyntax.self)
        else {
            return [
                """
                #error("PrivateFunctionMacro: failed to parse args")
                """
            ]
        }
        
        let args = argsExpr.elements
        
        guard let retArg = arguments.first(where: { $0.label?.text == "ret" }) else {
            return [
                """
                #error("PrivateFunctionMacro: failed to parse ret")
                """
            ]
        }
        
        let retTypeStr = retArg.expression.description.replacingOccurrences(of: ".self", with: "")
        let argTypesStr = args.compactMap { $0.expression.description.replacingOccurrences(of: ".self", with: "") }
            .joined(separator: ", ")

        // 1. 인자 파싱
        // name: "FooPrivateGetSomethingSize"
        // args: [UnsafeMutableRawPointer.self, UnsafeMutablePointer<Int>.self] -> ".self" 제거 후 문자열화
        // ret: Void.self -> "Void"
        
        // 2. C Function Convention Typealias 생성
        let typealiasName = "\(funcName)_FnType"
        let typealiasDecl = """
        typealias \(typealiasName) = @convention(c) (\(argTypesStr)) -> \(retTypeStr)
        """
        
        // 3. Lazy Static Property 생성
        // 부모의 _libraryHandle을 참조함
        let varDecl = """
        nonisolated(unsafe) static var \(funcName): \(typealiasName)? = {
            guard let handle = _libraryHandle else { return nil }
            guard let sym = dlsym(handle, "\(funcName)") else { return nil }
            return unsafeBitCast(sym, to: \(typealiasName).self)
        }()
        """
        
        return [DeclSyntax(stringLiteral: typealiasDecl), DeclSyntax(stringLiteral: varDecl)]
    }
}


