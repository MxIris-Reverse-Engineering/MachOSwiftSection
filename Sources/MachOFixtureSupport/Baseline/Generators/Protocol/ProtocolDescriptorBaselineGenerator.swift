import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/ProtocolDescriptorBaseline.swift`.
///
/// Members directly declared in `ProtocolDescriptor.swift` (across the body
/// and three same-file extensions). Protocol-extension methods that surface
/// at compile-time — `name(in:)`, `mangledName(in:)` — live on
/// `NamedContextDescriptorProtocol` and are exercised in Task 6 under
/// `NamedContextDescriptorProtocolTests`. The `parent`/`genericContext`/
/// etc. lookups live on `ContextDescriptorProtocol` (see `ContextDescriptorProtocolTests`).
///
/// Picker: `Protocols.ProtocolTest` — its `associatedTypes(in:)` returns
/// `["Body"]`, so the entry-point method is exercised with non-empty data.
package enum ProtocolDescriptorBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.protocol_ProtocolTest(in: machO)
        let entryExpr = try emitEntryExpr(for: descriptor, in: machO)

        // Public members declared directly in ProtocolDescriptor.swift.
        // The three `associatedTypes` overloads (MachO/InProcess/ReadingContext)
        // collapse to a single MethodKey under the scanner's name-based
        // deduplication. `init(layout:offset:)` is filtered as memberwise-
        // synthesized.
        let registered = [
            "associatedTypes",
            "layout",
            "offset",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ProtocolDescriptorBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let layoutNumRequirementsInSignature: UInt32
                let layoutNumRequirements: UInt32
                let layoutFlagsRawValue: UInt32
                let associatedTypes: [String]
            }

            static let protocolTest = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ProtocolDescriptorBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(
        for descriptor: ProtocolDescriptor,
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> String {
        let offset = descriptor.offset
        let layoutNumRequirementsInSignature = descriptor.layout.numRequirementsInSignature
        let layoutNumRequirements = descriptor.layout.numRequirements
        let layoutFlagsRawValue = descriptor.layout.flags.rawValue
        let associatedTypes = try descriptor.associatedTypes(in: machO)

        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(offset)),
            layoutNumRequirementsInSignature: \(literal: layoutNumRequirementsInSignature),
            layoutNumRequirements: \(literal: layoutNumRequirements),
            layoutFlagsRawValue: \(raw: BaselineEmitter.hex(layoutFlagsRawValue)),
            associatedTypes: \(literal: associatedTypes)
        )
        """
        return expr.description
    }
}
