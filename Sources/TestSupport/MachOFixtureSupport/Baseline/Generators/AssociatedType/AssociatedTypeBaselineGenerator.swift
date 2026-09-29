import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/AssociatedTypeBaseline.swift`.
///
/// `AssociatedType` is the high-level wrapper around
/// `AssociatedTypeDescriptor`. Beyond holding the descriptor itself it
/// pre-resolves `conformingTypeName`, `protocolTypeName`, and the
/// trailing `[AssociatedTypeRecord]`. The two MachO-based initializers
/// (`init(descriptor:in:)`) and the InProcess `init(descriptor:)` collapse
/// to single MethodKey entries under PublicMemberScanner's name-based
/// deduplication.
///
/// Picker: `AssociatedTypeWitnessPatterns.ConcreteWitnessTest` conforming
/// to `AssociatedTypeWitnessPatterns.AssociatedPatternProtocol`. The
/// fixture declares five concrete witnesses
/// (`First = Int`, `Second = [String]`, `Third = Double`, `Fourth = Bool`,
/// `Fifth = Character`), so the wrapper's records array has five entries.
package enum AssociatedTypeBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.associatedTypeDescriptor_ConcreteWitnessTest(in: machO)
        let associatedType = try AssociatedType(descriptor: descriptor, in: machO)

        let entryExpr = emitEntryExpr(for: associatedType)

        // Public members declared directly in AssociatedType.swift.
        // The two `init(descriptor:in:)` overloads (MachO + ReadingContext)
        // collapse to one MethodKey under the scanner's name-based
        // deduplication; `init(descriptor:)` is the InProcess form.
        let registered = [
            "conformingTypeName",
            "descriptor",
            "init(descriptor:)",
            "init(descriptor:in:)",
            "protocolTypeName",
            "records",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // Live MangledName payloads aren't embedded as literals; the
        // companion Suite (AssociatedTypeTests) verifies the methods
        // produce cross-reader-consistent results at runtime against the
        // counts / presence flags recorded here.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum AssociatedTypeBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let descriptorOffset: Int
                let recordsCount: Int
                let hasConformingTypeName: Bool
                let hasProtocolTypeName: Bool
            }

            static let concreteWitnessTest = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("AssociatedTypeBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(for associatedType: AssociatedType) -> String {
        let descriptorOffset = associatedType.descriptor.offset
        let recordsCount = associatedType.records.count
        // The pre-resolved MangledNames are non-empty when their elements
        // array is non-empty (the value type is not optional, but emptiness
        // signals a missing payload).
        let hasConformingTypeName = !associatedType.conformingTypeName.elements.isEmpty
        let hasProtocolTypeName = !associatedType.protocolTypeName.elements.isEmpty

        let expr: ExprSyntax = """
        Entry(
            descriptorOffset: \(raw: BaselineEmitter.hex(descriptorOffset)),
            recordsCount: \(literal: recordsCount),
            hasConformingTypeName: \(literal: hasConformingTypeName),
            hasProtocolTypeName: \(literal: hasProtocolTypeName)
        )
        """
        return expr.description
    }
}
