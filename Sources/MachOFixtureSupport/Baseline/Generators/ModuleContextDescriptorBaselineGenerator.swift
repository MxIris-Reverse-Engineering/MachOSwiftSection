import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/ModuleContextDescriptorBaseline.swift` from the
/// `SymbolTestsCore` fixture via the MachOFile reader.
///
/// `ModuleContextDescriptor` declares only the `offset` and `layout` ivars
/// (`init(layout:offset:)` is filtered as memberwise-synthesized). The
/// `Layout` carries the `flags + parent + name` triple; `flags.rawValue`
/// is the only stable scalar worth embedding here. The `name` lookup lives
/// on `NamedContextDescriptorProtocol` and is exercised by the
/// `ModuleContextTests` Suite via the wrapper.
package enum ModuleContextDescriptorBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.module_SymbolTestsCore(in: machO)
        let entryExpr = emitEntryExpr(for: descriptor)

        let registered = ["layout", "offset"]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ModuleContextDescriptorBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let layoutFlagsRawValue: UInt32
            }

            static let symbolTestsCore = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ModuleContextDescriptorBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(for descriptor: ModuleContextDescriptor) -> String {
        let offset = descriptor.offset
        let flagsRaw = descriptor.layout.flags.rawValue

        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(offset)),
            layoutFlagsRawValue: \(raw: BaselineEmitter.hex(flagsRaw))
        )
        """
        return expr.description
    }
}
