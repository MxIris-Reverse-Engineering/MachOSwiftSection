import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/MethodDescriptorFlagsBaseline.swift`.
///
/// `MethodDescriptorFlags` is a 32-bit packed flag word stored in each
/// `MethodDescriptor.layout.flags`. We extract the live flags from the
/// first vtable entry of `Classes.ClassTest` and record the raw value
/// plus all derived booleans / fields. This catches accidental changes
/// to the bit layout.
package enum MethodDescriptorFlagsBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.class_ClassTest(in: machO)
        let classWrapper = try Class(descriptor: descriptor, in: machO)
        let firstMethod = try required(classWrapper.methodDescriptors.first)
        let flags = firstMethod.layout.flags

        let entryExpr = emitEntryExpr(for: flags)

        // Public members declared directly in MethodDescriptorFlags.swift.
        let registered = [
            "_hasAsyncBitSet",
            "extraDiscriminator",
            "init(rawValue:)",
            "isAsync",
            "isCalleeAllocatedCoroutine",
            "isCoroutine",
            "isData",
            "isDynamic",
            "isInstance",
            "kind",
            "rawValue",
        ]

        let headerComment = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: headerComment)

        enum MethodDescriptorFlagsBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let rawValue: UInt32
                let kindRawValue: UInt8
                let isDynamic: Bool
                let isInstance: Bool
                let hasAsyncBitSet: Bool
                let isAsync: Bool
                let isCoroutine: Bool
                let isCalleeAllocatedCoroutine: Bool
                let isData: Bool
                let extraDiscriminator: UInt16
            }

            static let firstClassTestMethod = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("MethodDescriptorFlagsBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(for flags: MethodDescriptorFlags) -> String {
        let rawValue = flags.rawValue
        let kindRawValue = flags.kind.rawValue
        let isDynamic = flags.isDynamic
        let isInstance = flags.isInstance
        let hasAsyncBitSet = flags._hasAsyncBitSet
        let isAsync = flags.isAsync
        let isCoroutine = flags.isCoroutine
        let isCalleeAllocatedCoroutine = flags.isCalleeAllocatedCoroutine
        let isData = flags.isData
        let extraDiscriminator = flags.extraDiscriminator

        let expr: ExprSyntax = """
        Entry(
            rawValue: \(raw: BaselineEmitter.hex(rawValue)),
            kindRawValue: \(raw: BaselineEmitter.hex(kindRawValue)),
            isDynamic: \(literal: isDynamic),
            isInstance: \(literal: isInstance),
            hasAsyncBitSet: \(literal: hasAsyncBitSet),
            isAsync: \(literal: isAsync),
            isCoroutine: \(literal: isCoroutine),
            isCalleeAllocatedCoroutine: \(literal: isCalleeAllocatedCoroutine),
            isData: \(literal: isData),
            extraDiscriminator: \(raw: BaselineEmitter.hex(extraDiscriminator))
        )
        """
        return expr.description
    }
}
