import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct MachOMacroPlugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [
        LayoutMacro.self,
        ResolvableLocatableLayoutWrapperMacro.self,
    ]
}
