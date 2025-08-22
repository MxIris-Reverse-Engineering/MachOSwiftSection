import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct MachOMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        LayoutMacro.self,
        MachOImageGeneratorMacro.self,
        MachOImageAllMembersGeneratorMacro.self,
        AssociatedValueMacro.self,
        CaseCheckableMacro.self,
    ]
}
