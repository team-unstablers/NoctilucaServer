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
        
        let rawRetTypeStr = retArg.expression.description.replacingOccurrences(of: ".self", with: "")
        let argTypesStr = args.compactMap { $0.expression.description.replacingOccurrences(of: ".self", with: "") }
            .joined(separator: ", ")

        // retainedCF: true 면 Copy/Create rule 에 따른 +1 retained CF 반환값을
        // Swift ARC 가 인식하도록 typealias 의 반환 타입을 Unmanaged<T>? 로 감싼다.
        // 호출자는 .takeRetainedValue() 로 소유권을 ARC 에 이전해야 한다.
        let retainedCF: Bool = {
            guard let arg = arguments.first(where: { $0.label?.text == "retainedCF" }) else {
                return false
            }
            if let boolExpr = arg.expression.as(BooleanLiteralExprSyntax.self) {
                return boolExpr.literal.text == "true"
            }
            return false
        }()

        let retTypeStr: String = {
            guard retainedCF else { return rawRetTypeStr }
            let trimmed = rawRetTypeStr.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix("?") {
                let inner = String(trimmed.dropLast())
                return "Unmanaged<\(inner)>?"
            }
            return "Unmanaged<\(trimmed)>"
        }()

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


