import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

@main
struct GesuPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        PrivateLibraryMacro.self,
        PrivateFunctionMacro.self,
    ]
}
