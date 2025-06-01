import Foundation
import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct MachOSwiftSectionMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        LayoutMacro.self,
        MachOImageGeneratorMacro.self,
        MachOImageAllMembersGeneratorMacro.self,
    ]
}
