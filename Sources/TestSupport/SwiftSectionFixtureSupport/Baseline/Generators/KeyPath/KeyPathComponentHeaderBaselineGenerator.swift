import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/KeyPathComponentHeaderBaseline.swift`.
///
/// The header is pure bit arithmetic over one word, so the baseline records
/// every derived accessor for the four fixture descriptors' headers. The
/// `optional` and `external` kinds have no fixture carrier — a property
/// descriptor never holds one — so they are pinned through synthesized raw
/// values instead, which is what keeps the pattern-side accessors honest.
package enum KeyPathComponentHeaderBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptors = try KeyPathFixtureDescriptors(in: machO)

        let registered = [
            "computedIdentifierKind",
            "computedIdentifierResolution",
            "hasComputedArguments",
            "init(rawValue:)",
            "inlineStoredFieldOffset",
            "isComputedMutating",
            "isComputedSettable",
            "isEndOfReferencePrefix",
            "isStoredMutable",
            "isTrivialPropertyDescriptor",
            "kind",
            "optionalComponentKind",
            "patternComponentBodySize",
            "payload",
            "propertyDescriptorBodySize",
            "rawKind",
            "rawValue",
            "storedFieldOffsetKind",
            "storedOffsetPayload",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // Every derived accessor of the four fixture descriptors' header
        // words. Pure bit arithmetic, so identical across readers.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum KeyPathComponentHeaderBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let rawValue: UInt32
                let rawKind: UInt32
                let kindDescription: String
                let payload: UInt32
                let isTrivialPropertyDescriptor: Bool
                let isEndOfReferencePrefix: Bool
                let storedOffsetPayload: UInt32
                let isStoredMutable: Bool
                let storedFieldOffsetKindDescription: String
                let inlineStoredFieldOffset: UInt32?
                let isComputedSettable: Bool
                let isComputedMutating: Bool
                let hasComputedArguments: Bool
                let computedIdentifierKindDescription: String
                let computedIdentifierResolutionRawValue: UInt32?
                let optionalComponentKindDescription: String
                let propertyDescriptorBodySize: Int
                let patternComponentBodySize: Int
            }

            static let trivial = \(raw: emitEntry(for: descriptors.trivial.header))

            static let inlineStoredOffset = \(raw: emitEntry(for: descriptors.inlineStoredOffset.header))

            static let unresolvedFieldOffset = \(raw: emitEntry(for: descriptors.unresolvedFieldOffset.header))

            static let computedSettable = \(raw: emitEntry(for: descriptors.computedSettable.header))

            /// An `optional` chain component. No property descriptor can carry
            /// one, so it is synthesized from the encoding the runtime defines.
            static let synthesizedOptionalChain = \(raw: emitEntry(for: KeyPathComponentHeader(rawValue: 0x0400_0000)))

            /// An `external` component with two substitution arguments, also
            /// synthesized: `4 * (1 + 2)` bytes of body.
            static let synthesizedExternalWithTwoArguments = \(raw: emitEntry(for: KeyPathComponentHeader(rawValue: 0x0000_0002)))

            /// A stored component flagged as the end of a reference prefix,
            /// synthesized: the flag only ever appears inside a pattern.
            static let synthesizedEndOfReferencePrefix = \(raw: emitEntry(for: KeyPathComponentHeader(rawValue: 0x8180_0010)))
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("KeyPathComponentHeaderBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntry(for header: KeyPathComponentHeader) -> String {
        let expr: ExprSyntax = """
        Entry(
            rawValue: \(raw: BaselineEmitter.hex(header.rawValue)),
            rawKind: \(literal: header.rawKind),
            kindDescription: \(literal: String(describing: header.kind)),
            payload: \(raw: BaselineEmitter.hex(header.payload)),
            isTrivialPropertyDescriptor: \(literal: header.isTrivialPropertyDescriptor),
            isEndOfReferencePrefix: \(literal: header.isEndOfReferencePrefix),
            storedOffsetPayload: \(raw: BaselineEmitter.hex(header.storedOffsetPayload)),
            isStoredMutable: \(literal: header.isStoredMutable),
            storedFieldOffsetKindDescription: \(literal: String(describing: header.storedFieldOffsetKind)),
            inlineStoredFieldOffset: \(raw: BaselineEmitter.optionalHex(header.inlineStoredFieldOffset)),
            isComputedSettable: \(literal: header.isComputedSettable),
            isComputedMutating: \(literal: header.isComputedMutating),
            hasComputedArguments: \(literal: header.hasComputedArguments),
            computedIdentifierKindDescription: \(literal: String(describing: header.computedIdentifierKind)),
            computedIdentifierResolutionRawValue: \(raw: BaselineEmitter.optionalHex(header.computedIdentifierResolution?.rawValue)),
            optionalComponentKindDescription: \(literal: String(describing: header.optionalComponentKind)),
            propertyDescriptorBodySize: \(literal: header.propertyDescriptorBodySize),
            patternComponentBodySize: \(literal: header.patternComponentBodySize)
        )
        """
        return expr.description
    }
}
