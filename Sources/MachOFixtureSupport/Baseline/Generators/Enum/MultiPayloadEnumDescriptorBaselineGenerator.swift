import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/MultiPayloadEnumDescriptorBaseline.swift` from the
/// `SymbolTestsCore` fixture via the MachOFile reader.
///
/// `MultiPayloadEnumDescriptor` lives in the `__swift5_mpenum` section and
/// carries variable-length spare-bit metadata for multi-payload enums. The
/// descriptor's public surface mixes:
///   - `offset` / `layout` ivars (the `init(layout:offset:)` initializer is
///     filtered as memberwise-synthesized)
///   - method overloads that resolve runtime data (`mangledTypeName`,
///     `contents`, `payloadSpareBits`, `payloadSpareBitMaskByteOffset`,
///     `payloadSpareBitMaskByteCount` — each appears in three flavors:
///     MachO + InProcess + ReadingContext, all collapsing to one MethodKey)
///   - derived bit-twiddling accessors (`contentsSizeInWord`, `flags`,
///     `usesPayloadSpareBits`, the index family, and the
///     `TopLevelDescriptor` conformance's `actualSize`)
///
/// We use the multi-payload picker (`Enums.MultiPayloadEnumTests`) which
/// has 4 cases, 3 of them with payloads — a canonical multi-payload
/// descriptor.
package enum MultiPayloadEnumDescriptorBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.multiPayloadEnumDescriptor_MultiPayloadEnumTest(in: machO)

        let multiPayloadExpr = try emitEntryExpr(for: descriptor, in: machO)

        // Members directly declared in MultiPayloadEnumDescriptor.swift
        // (across the main body and three same-file extensions, plus the
        // `TopLevelDescriptor` extension carrying `actualSize`). Method
        // overloads (MachO + InProcess + ReadingContext) collapse to a
        // single MethodKey under the scanner's name-based deduplication.
        let registered = [
            "actualSize",
            "contents",
            "contentsSizeInWord",
            "flags",
            "layout",
            "mangledTypeName",
            "offset",
            "payloadSpareBitMaskByteCount",
            "payloadSpareBitMaskByteCountIndex",
            "payloadSpareBitMaskByteOffset",
            "payloadSpareBits",
            "payloadSpareBitsIndex",
            "sizeFlagsIndex",
            "usesPayloadSpareBits",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum MultiPayloadEnumDescriptorBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let layoutSizeFlags: UInt32
                let mangledTypeNameRawString: String
                let contentsSizeInWord: UInt32
                let flags: UInt32
                let usesPayloadSpareBits: Bool
                let sizeFlagsIndex: Int
                let payloadSpareBitMaskByteCountIndex: Int
                let payloadSpareBitsIndex: Int
                let actualSize: Int
                let contentsCount: Int
                let payloadSpareBitsCount: Int
                let payloadSpareBitMaskByteOffset: UInt32
                let payloadSpareBitMaskByteCount: UInt32
            }

            static let multiPayloadEnumTest = \(raw: multiPayloadExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("MultiPayloadEnumDescriptorBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(
        for descriptor: MultiPayloadEnumDescriptor,
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> String {
        let offset = descriptor.offset
        let layoutSizeFlags = descriptor.layout.sizeFlags
        let mangledTypeName = try descriptor.mangledTypeName(in: machO)
        let mangledTypeNameRawString = mangledTypeName.rawString
        let contentsSizeInWord = descriptor.contentsSizeInWord
        let flags = descriptor.flags
        let usesPayloadSpareBits = descriptor.usesPayloadSpareBits
        let sizeFlagsIndex = descriptor.sizeFlagsIndex
        let payloadSpareBitMaskByteCountIndex = descriptor.payloadSpareBitMaskByteCountIndex
        let payloadSpareBitsIndex = descriptor.payloadSpareBitsIndex
        let actualSize = descriptor.actualSize
        let contentsCount = try descriptor.contents(in: machO).count
        let payloadSpareBitsCount = try descriptor.payloadSpareBits(in: machO).count
        let payloadSpareBitMaskByteOffset = try descriptor.payloadSpareBitMaskByteOffset(in: machO)
        let payloadSpareBitMaskByteCount = try descriptor.payloadSpareBitMaskByteCount(in: machO)

        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(offset)),
            layoutSizeFlags: \(raw: BaselineEmitter.hex(layoutSizeFlags)),
            mangledTypeNameRawString: \(literal: mangledTypeNameRawString),
            contentsSizeInWord: \(raw: BaselineEmitter.hex(contentsSizeInWord)),
            flags: \(raw: BaselineEmitter.hex(flags)),
            usesPayloadSpareBits: \(literal: usesPayloadSpareBits),
            sizeFlagsIndex: \(literal: sizeFlagsIndex),
            payloadSpareBitMaskByteCountIndex: \(literal: payloadSpareBitMaskByteCountIndex),
            payloadSpareBitsIndex: \(literal: payloadSpareBitsIndex),
            actualSize: \(literal: actualSize),
            contentsCount: \(literal: contentsCount),
            payloadSpareBitsCount: \(literal: payloadSpareBitsCount),
            payloadSpareBitMaskByteOffset: \(raw: BaselineEmitter.hex(payloadSpareBitMaskByteOffset)),
            payloadSpareBitMaskByteCount: \(raw: BaselineEmitter.hex(payloadSpareBitMaskByteCount))
        )
        """
        return expr.description
    }
}
