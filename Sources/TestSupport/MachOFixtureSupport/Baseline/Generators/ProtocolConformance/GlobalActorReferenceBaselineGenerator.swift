import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/GlobalActorReferenceBaseline.swift`.
///
/// `GlobalActorReference` is the trailing object of
/// `TargetProtocolConformanceDescriptor` carrying the actor type that
/// isolates the conformance (e.g. `extension X: @MainActor P`). Present
/// iff `ProtocolConformanceFlags.hasGlobalActorIsolation` is set.
///
/// Picker: the first conformance from the fixture with the
/// `hasGlobalActorIsolation` bit. The fixture's
/// `Actors.GlobalActorIsolatedConformanceTest` declares both
/// `: @MainActor Actors.GlobalActorIsolatedProtocolTest` and
/// `: @CustomGlobalActor Actors.CustomGlobalActorIsolatedProtocolTest`,
/// so a global-actor reference is always available.
///
/// We pin the `offset` of the trailing reference and the type-name string
/// (resolved via `typeName(in:)`). The conformance pointer slot exists for
/// runtime dispatch; the dumper only uses the type-name pointer, so the
/// baseline only validates that.
package enum GlobalActorReferenceBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let conformance = try BaselineFixturePicker.protocolConformance_globalActorFirst(in: machO)
        let reference = try required(conformance.globalActorReference)
        let typeName = try reference.typeName(in: machO)
        let entryExpr = emitEntryExpr(offset: reference.offset, typeNameString: typeName.symbolString)

        // Public members declared directly in GlobalActorReference.swift.
        // `init(layout:offset:)` is filtered as memberwise-synthesized.
        // `typeName` collapses across MachO/InProcess/ReadingContext
        // overloads under the scanner's name-based deduplication.
        let registered = [
            "layout",
            "offset",
            "typeName",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum GlobalActorReferenceBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let typeNameSymbolString: String
            }

            static let firstReference = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("GlobalActorReferenceBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(offset: Int, typeNameString: String) -> String {
        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(offset)),
            typeNameSymbolString: \(literal: typeNameString)
        )
        """
        return expr.description
    }
}
