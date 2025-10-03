import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct MachOMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        LayoutMacro.self,
        AssociatedValueMacro.self,
        CaseCheckableMacro.self,
    ]
}
