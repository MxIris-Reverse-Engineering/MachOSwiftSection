import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/TypeContextDescriptorBaseline.swift` from the
/// `SymbolTestsCore` fixture via the MachOFile reader.
///
/// `TypeContextDescriptor` is the bare type-descriptor header common to
/// struct/enum/class kinds — it carries `offset`/`layout` plus three same-
/// file extensions adding `enumDescriptor`/`structDescriptor`/`classDescriptor`
/// kind-projection methods (each with MachO + InProcess + ReadingContext
/// overloads that collapse to one MethodKey under PublicMemberScanner's
/// name-only key). Protocol-extension members (`name(in:)`, `fields(in:)`,
/// `metadataAccessorFunction(in:)`, etc.) live on
/// `TypeContextDescriptorProtocol` and are covered by
/// `TypeContextDescriptorProtocolBaseline` per the protocol-extension
/// attribution rule.
///
/// We materialize a representative `TypeContextDescriptor` by reading the
/// bare header at the offset of `Structs.StructTest`. Because the picker
/// targets a struct, `structDescriptor()` returns non-nil and the other
/// two kind projections (`enumDescriptor`/`classDescriptor`) return nil.
package enum TypeContextDescriptorBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let structTest = try BaselineFixturePicker.struct_StructTest(in: machO)
        let descriptor: TypeContextDescriptor = try machO.readWrapperElement(offset: structTest.offset)

        let entryExpr = try emitEntryExpr(for: descriptor, in: machO)

        // Public members directly declared in TypeContextDescriptor.swift
        // (across the body and three same-file extensions). Protocol-extension
        // methods like `name(in:)` are attributed to
        // `TypeContextDescriptorProtocol` and live in their own baseline.
        let registered = [
            "classDescriptor",
            "enumDescriptor",
            "layout",
            "offset",
            "structDescriptor",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum TypeContextDescriptorBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let layoutFlagsRawValue: UInt32
                let hasEnumDescriptor: Bool
                let hasStructDescriptor: Bool
                let hasClassDescriptor: Bool
            }

            static let structTest = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("TypeContextDescriptorBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(
        for descriptor: TypeContextDescriptor,
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> String {
        let offset = descriptor.offset
        let flagsRaw = descriptor.layout.flags.rawValue
        let hasEnumDescriptor = (try descriptor.enumDescriptor(in: machO)) != nil
        let hasStructDescriptor = (try descriptor.structDescriptor(in: machO)) != nil
        let hasClassDescriptor = (try descriptor.classDescriptor(in: machO)) != nil

        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(offset)),
            layoutFlagsRawValue: \(raw: BaselineEmitter.hex(flagsRaw)),
            hasEnumDescriptor: \(literal: hasEnumDescriptor),
            hasStructDescriptor: \(literal: hasStructDescriptor),
            hasClassDescriptor: \(literal: hasClassDescriptor)
        )
        """
        return expr.description
    }
}
