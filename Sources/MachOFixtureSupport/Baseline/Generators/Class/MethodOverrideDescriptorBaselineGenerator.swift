import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/MethodOverrideDescriptorBaseline.swift`.
///
/// `MethodOverrideDescriptor` is the row type for a class's override table.
/// We pick the first override entry from `Classes.SubclassTest` (which
/// overrides several methods inherited from `ClassTest`) and record the
/// descriptor offset and the implementation offset — pure relative-pointer
/// arithmetic, so both pin as literals. The resolved class / method
/// descriptors are not embedded; the Suite checks their presence across
/// readers at runtime.
package enum MethodOverrideDescriptorBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.class_SubclassTest(in: machO)
        let classWrapper = try Class(descriptor: descriptor, in: machO)
        let firstOverride = try required(classWrapper.methodOverrideDescriptors.first)

        let entryExpr = emitEntryExpr(for: firstOverride)
        let overrideCount = classWrapper.methodOverrideDescriptors.count

        // Public members declared directly in MethodOverrideDescriptor.swift
        // (across the main body and same-file extensions). Overload sets
        // collapse to a single MethodKey under PublicMemberScanner.
        let registered = [
            "classDescriptor",
            "implementationAddress",
            "implementationOffset",
            "layout",
            "methodDescriptor",
            "offset",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // The implementation offset is pure relative-pointer arithmetic, so
        // it is pinned as a literal (like MethodDescriptor's); the class /
        // method descriptor pointers resolve to live wrappers and are
        // checked for presence across readers at runtime instead.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum MethodOverrideDescriptorBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let implementationOffset: Int?
            }

            static let firstSubclassOverride = \(raw: entryExpr)

            static let subclassOverrideCount = \(literal: overrideCount)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("MethodOverrideDescriptorBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(for override: MethodOverrideDescriptor) -> String {
        let offset = override.offset
        let implementationOffset = override.implementationOffset

        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(offset)),
            implementationOffset: \(raw: BaselineEmitter.optionalHex(implementationOffset))
        )
        """
        return expr.description
    }
}
