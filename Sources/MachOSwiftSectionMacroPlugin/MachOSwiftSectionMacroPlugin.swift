import Foundation
import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct LayoutPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        LayoutMacro.self,
    ]
}
