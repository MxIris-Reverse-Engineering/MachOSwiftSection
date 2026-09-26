import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/KeyPathStoredFieldOffsetBaseline.swift`.
///
/// Two of the four shapes are stored ones, and they land on different cases:
/// the non-generic struct's offset is `inline`, the generic struct's is
/// `unresolvedFieldOffset` — which is exactly the distinction
/// `staticFieldOffset` exists to express (a real offset versus one that can
/// only be read out of live metadata).
package enum KeyPathStoredFieldOffsetBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptors = try KeyPathFixtureDescriptors(in: machO)
        let inlineOffset = try required(descriptors.inlineStoredOffset.storedFieldOffset(in: machO))
        let unresolvedOffset = try required(descriptors.unresolvedFieldOffset.storedFieldOffset(in: machO))

        let registered = ["kind", "rawValue", "staticFieldOffset"]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // The two stored shapes a property descriptor produces: an offset
        // the binary states outright, and one that only names where in the
        // metadata the real offset lives.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum KeyPathStoredFieldOffsetBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let kindDescription: String
                let rawValue: UInt32
                let staticFieldOffset: UInt32?
            }

            static let inlineStoredOffset = \(raw: emitEntry(for: inlineOffset))

            static let unresolvedFieldOffset = \(raw: emitEntry(for: unresolvedOffset))

            /// Synthesized: no fixture property lands on the out-of-line case
            /// (it needs an offset above 0x7FFFFC), but it is a static offset
            /// like the inline one and must report as such.
            static let synthesizedOutOfLine = \(raw: emitEntry(for: .outOfLine(0x0080_0000)))

            /// Synthesized: the shape a class with a resilient superclass
            /// gets. Like `unresolvedFieldOffset`, it has no static offset.
            static let synthesizedUnresolvedIndirectOffset = \(raw: emitEntry(for: .unresolvedIndirectOffset(offsetOfFieldOffsetPointer: 0x40)))
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("KeyPathStoredFieldOffsetBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntry(for offset: KeyPathStoredFieldOffset) -> String {
        let expr: ExprSyntax = """
        Entry(
            kindDescription: \(literal: String(describing: offset.kind)),
            rawValue: \(raw: BaselineEmitter.hex(offset.rawValue)),
            staticFieldOffset: \(raw: BaselineEmitter.optionalHex(offset.staticFieldOffset))
        )
        """
        return expr.description
    }
}
