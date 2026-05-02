import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/StructDescriptorBaseline.swift` from the
/// `SymbolTestsCore` fixture via the MachOFile reader.
///
/// `StructDescriptor` declares only two members directly (the `offset` ivar
/// and the `layout` ivar; `init(layout:offset:)` is filtered as a memberwise
/// synthesized initializer). All `name`/`fields`/`numberOfFields` etc. live on
/// `TypeContextDescriptorProtocol` (a protocol-extension Suite) and will be
/// covered by Task 9, not here.
package enum StructDescriptorBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let structTest = try BaselineFixturePicker.struct_StructTest(in: machO)
        let genericStruct = try BaselineFixturePicker.struct_GenericStructNonRequirement(in: machO)

        let structTestExpr = try emitEntryExpr(for: structTest)
        let genericStructExpr = try emitEntryExpr(for: genericStruct)

        let registered = ["layout", "offset"]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: swift run baseline-generator
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum StructDescriptorBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let layoutNumFields: Int
                let layoutFieldOffsetVector: Int
                let layoutFlagsRawValue: UInt32
            }

            static let structTest = \(raw: structTestExpr)

            static let genericStructNonRequirement = \(raw: genericStructExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("StructDescriptorBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(for descriptor: StructDescriptor) throws -> String {
        let offset = descriptor.offset
        let numFields = Int(descriptor.layout.numFields)
        let fieldOffsetVector = Int(descriptor.layout.fieldOffsetVector)
        let flagsRaw = descriptor.layout.flags.rawValue

        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(offset)),
            layoutNumFields: \(literal: numFields),
            layoutFieldOffsetVector: \(literal: fieldOffsetVector),
            layoutFlagsRawValue: \(raw: BaselineEmitter.hex(flagsRaw))
        )
        """
        return expr.description
    }
}
