import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/MangledNameBaseline.swift`.
///
/// `MangledName` is the parser/decoder for Swift's mangled-name byte
/// stream. Carriers exist throughout the fixture: every multi-payload
/// enum's `mangledTypeName`, every associated-type record's mangled
/// names, etc. We pick the multi-payload-enum descriptor's
/// `mangledTypeName` for `Enums.MultiPayloadEnumTests` as a stable
/// carrier — it's deterministic across builds and exercises the
/// non-empty-elements / lookup-element paths.
///
/// The Suite asserts cross-reader equality on:
///   - `isEmpty` — same boolean across readers
///   - `rawString` — byte-equal across readers
///   - presence of `lookupElements` — count match
package enum MangledNameBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.multiPayloadEnumDescriptor_MultiPayloadEnumTest(in: machO)
        let mangledName = try descriptor.mangledTypeName(in: machO)
        let entryExpr = emitEntryExpr(for: mangledName)

        // Public members declared in MangledName.swift. The three
        // `resolve` overloads (MachO + InProcess + ReadingContext)
        // collapse to one MethodKey under PublicMemberScanner's
        // name-only key.
        let registered = [
            "description",
            "isEmpty",
            "rawString",
            "resolve",
            "symbolString",
            "typeString",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // Carrier: the mangledTypeName of the MultiPayloadEnumDescriptor
        // for Enums.MultiPayloadEnumTests. The Suite asserts cross-reader
        // equality on (isEmpty, rawString, element-count, lookup-count).
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum MangledNameBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let isEmpty: Bool
                let rawString: String
                let lookupElementsCount: Int
            }

            static let multiPayloadEnumName = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("MangledNameBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(for mangledName: MangledName) -> String {
        let isEmpty = mangledName.isEmpty
        let rawString = mangledName.rawString
        let lookupElementsCount = mangledName.lookupElements.count

        let expr: ExprSyntax = """
        Entry(
            isEmpty: \(literal: isEmpty),
            rawString: \(literal: rawString),
            lookupElementsCount: \(literal: lookupElementsCount)
        )
        """
        return expr.description
    }
}
