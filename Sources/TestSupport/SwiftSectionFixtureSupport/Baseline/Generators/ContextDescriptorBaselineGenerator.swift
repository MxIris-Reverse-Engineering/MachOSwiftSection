import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/ContextDescriptorBaseline.swift` from the
/// `SymbolTestsCore` fixture via the MachOFile reader.
///
/// `ContextDescriptor` declares only the `offset` and `layout` ivars
/// (`init(layout:offset:)` is filtered as memberwise-synthesized). Protocol-
/// extension members (`parent`, `genericContext`, `subscript(dynamicMember:)`,
/// etc.) live on `ContextDescriptorProtocol` and are covered by
/// `ContextDescriptorProtocolTests`, per the protocol-extension attribution
/// rule documented in `BaselineGenerator.swift`.
///
/// We materialize a representative `ContextDescriptor` by reading the bare
/// header at `Structs.StructTest`'s offset.
package enum ContextDescriptorBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let structTest = try BaselineFixturePicker.struct_StructTest(in: machO)
        // Read the bare ContextDescriptor header at the same offset so the
        // baseline reflects the canonical descriptor view (flags only at the
        // header level — the layout's `parent` is a relative pointer and not
        // a stable scalar).
        let descriptor: ContextDescriptor = try machO.readWrapperElement(offset: structTest.offset)
        let entryExpr = emitEntryExpr(for: descriptor)

        let registered = ["layout", "offset"]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ContextDescriptorBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let layoutFlagsRawValue: UInt32
            }

            static let structTest = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ContextDescriptorBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(for descriptor: ContextDescriptor) -> String {
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
