import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/BuiltinTypeDescriptorBaseline.swift`.
///
/// `BuiltinTypeDescriptor` is a 5-field record stored in the
/// `__swift5_builtin` section. The fixture's `BuiltinTypeFields`
/// declarations cause the compiler to emit one descriptor per
/// primitive backing type used in stored fields (Int / Float /
/// Double / Bool / Character / String etc.). The Suite picks the
/// first descriptor for a stable carrier and asserts cross-reader
/// equality of the layout fields.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
package enum BuiltinTypeDescriptorBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.builtinTypeDescriptor_first(in: machO)
        let entryExpr = try emitEntryExpr(for: descriptor, in: machO)

        // Public members declared in BuiltinTypeDescriptor.swift. The two
        // `typeName` overloads (MachO + ReadingContext) collapse to one
        // MethodKey under the scanner's name-only key.
        let registered = [
            "alignment",
            "hasMangledName",
            "isBitwiseTakable",
            "layout",
            "offset",
            "typeName",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // BuiltinTypeDescriptor is the first record in the
        // __swift5_builtin section of SymbolTestsCore. The Suite asserts
        // cross-reader equality of the size/alignment/stride/extra-
        // inhabitants layout fields and the typeName resolution.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum BuiltinTypeDescriptorBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let descriptorOffset: Int
                let size: UInt32
                let alignmentAndFlags: UInt32
                let stride: UInt32
                let numExtraInhabitants: UInt32
                let alignment: Int
                let isBitwiseTakable: Bool
                let hasMangledName: Bool
            }

            static let firstBuiltin = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("BuiltinTypeDescriptorBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(
        for descriptor: BuiltinTypeDescriptor,
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> String {
        let descriptorOffset = descriptor.offset
        let size = descriptor.layout.size
        let alignmentAndFlags = descriptor.layout.alignmentAndFlags
        let stride = descriptor.layout.stride
        let numExtraInhabitants = descriptor.layout.numExtraInhabitants
        let alignment = descriptor.alignment
        let isBitwiseTakable = descriptor.isBitwiseTakable
        let hasMangledName = descriptor.hasMangledName

        let expr: ExprSyntax = """
        Entry(
            descriptorOffset: \(raw: BaselineEmitter.hex(descriptorOffset)),
            size: \(raw: BaselineEmitter.hex(size)),
            alignmentAndFlags: \(raw: BaselineEmitter.hex(alignmentAndFlags)),
            stride: \(raw: BaselineEmitter.hex(stride)),
            numExtraInhabitants: \(raw: BaselineEmitter.hex(numExtraInhabitants)),
            alignment: \(raw: BaselineEmitter.hex(alignment)),
            isBitwiseTakable: \(literal: isBitwiseTakable),
            hasMangledName: \(literal: hasMangledName)
        )
        """
        return expr.description
    }
}
