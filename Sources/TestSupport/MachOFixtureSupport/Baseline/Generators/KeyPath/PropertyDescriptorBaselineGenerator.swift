import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/PropertyDescriptorBaseline.swift`.
///
/// A property descriptor has no section to walk, so the four entries are
/// picked by `…vpMV` symbol name, one per shape the descriptor can take
/// (see `PropertyDescriptorFixtureSymbol`). Every recorded value is either
/// pure header arithmetic or one body word, so all of them are identical
/// across readers.
package enum PropertyDescriptorBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptors = try KeyPathFixtureDescriptors(in: machO)

        let registered = [
            "bodyOffset",
            "bodySize",
            "computedPropertyBody",
            "header",
            "inlineStoredFieldOffset",
            "isTrivial",
            "layout",
            "offset",
            "size",
            "storedFieldOffset",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // Four property descriptors, one per shape: the module's shared
        // trivial one, a struct stored property whose offset is inline in the
        // header, a generic struct's stored property whose offset lives in
        // the metadata, and a resilient class's settable computed property.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum PropertyDescriptorBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let headerRawValue: UInt32
                let isTrivial: Bool
                let bodySize: Int
                let size: Int
                let bodyOffset: Int
                let inlineStoredFieldOffsetRawValue: UInt32?
                let storedFieldOffsetRawValue: UInt32?
                let computedGetterOffset: Int?
            }

            static let trivial = \(raw: try emitEntry(for: descriptors.trivial, in: machO))

            static let inlineStoredOffset = \(raw: try emitEntry(for: descriptors.inlineStoredOffset, in: machO))

            static let unresolvedFieldOffset = \(raw: try emitEntry(for: descriptors.unresolvedFieldOffset, in: machO))

            static let computedSettable = \(raw: try emitEntry(for: descriptors.computedSettable, in: machO))
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("PropertyDescriptorBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntry(
        for descriptor: PropertyDescriptor,
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> String {
        let storedFieldOffset = try descriptor.storedFieldOffset(in: machO)
        let computedBody = try descriptor.computedPropertyBody(in: machO)

        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(descriptor.offset)),
            headerRawValue: \(raw: BaselineEmitter.hex(descriptor.header.rawValue)),
            isTrivial: \(literal: descriptor.isTrivial),
            bodySize: \(literal: descriptor.bodySize),
            size: \(literal: descriptor.size),
            bodyOffset: \(raw: BaselineEmitter.hex(descriptor.bodyOffset)),
            inlineStoredFieldOffsetRawValue: \(raw: BaselineEmitter.optionalHex(descriptor.inlineStoredFieldOffset?.rawValue)),
            storedFieldOffsetRawValue: \(raw: BaselineEmitter.optionalHex(storedFieldOffset?.rawValue)),
            computedGetterOffset: \(raw: BaselineEmitter.optionalHex(computedBody?.getterOffset))
        )
        """
        return expr.description
    }
}
