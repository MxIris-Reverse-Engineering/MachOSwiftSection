import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/MethodDescriptorBaseline.swift`.
///
/// `MethodDescriptor` is the row type for a class's vtable. We pick the
/// first vtable entry from the `Classes.ClassTest` picker — which has a
/// non-empty vtable — and record the `flags.rawValue` plus the descriptor
/// offset, plus the implementation offset the descriptor's relative pointer
/// resolves to (a pure-arithmetic value, identical across readers).
package enum MethodDescriptorBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.class_ClassTest(in: machO)
        let classWrapper = try Class(descriptor: descriptor, in: machO)
        let firstMethod = try required(classWrapper.methodDescriptors.first)

        let entryExpr = emitEntryExpr(for: firstMethod)
        let methodCount = classWrapper.methodDescriptors.count

        // Public members declared directly in MethodDescriptor.swift.
        // Symbol attribution (`implementationSymbols(in:)`) moved to
        // SwiftInspection (evolution proposal `self-contained-abi-layer`);
        // the ABI layer exposes the implementation's offset and address.
        let registered = [
            "implementationAddress",
            "implementationOffset",
            "layout",
            "offset",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // The implementation offset is pure relative-pointer arithmetic, so
        // it is pinned as a literal; the companion Suite
        // (MethodDescriptorTests) also verifies cross-reader agreement.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum MethodDescriptorBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let layoutFlagsRawValue: UInt32
                let implementationOffset: Int?
            }

            static let firstClassTestMethod = \(raw: entryExpr)

            static let classTestMethodCount = \(literal: methodCount)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("MethodDescriptorBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(for method: MethodDescriptor) -> String {
        let offset = method.offset
        let flagsRaw = method.layout.flags.rawValue
        let implementationOffset = method.implementationOffset

        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(offset)),
            layoutFlagsRawValue: \(raw: BaselineEmitter.hex(flagsRaw)),
            implementationOffset: \(raw: BaselineEmitter.optionalHex(implementationOffset))
        )
        """
        return expr.description
    }
}
