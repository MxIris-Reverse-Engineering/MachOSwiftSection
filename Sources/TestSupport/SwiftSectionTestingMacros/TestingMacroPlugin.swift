import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct TestingMacroPlugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [
        FixtureSuiteMacro.self,
    ]
}
