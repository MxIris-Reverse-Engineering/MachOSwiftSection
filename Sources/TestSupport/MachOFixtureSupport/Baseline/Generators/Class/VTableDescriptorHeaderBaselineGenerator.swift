import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/VTableDescriptorHeaderBaseline.swift`.
///
/// `VTableDescriptorHeader` is the trailing-object header that announces a
/// class's vtable. We pick the header from `Classes.ClassTest` (which has
/// a non-empty vtable) and record both layout scalars: `vTableOffset` and
/// `vTableSize`.
package enum VTableDescriptorHeaderBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptor = try BaselineFixturePicker.class_ClassTest(in: machO)
        let classWrapper = try Class(descriptor: descriptor, in: machO)
        let header = try required(classWrapper.vTableDescriptorHeader)

        let entryExpr = emitEntryExpr(for: header)

        // Public members declared directly in VTableDescriptorHeader.swift.
        // `init(layout:offset:)` is filtered as memberwise-synthesized.
        let registered = [
            "layout",
            "offset",
        ]

        let headerComment = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: headerComment)

        enum VTableDescriptorHeaderBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let layoutVTableOffset: UInt32
                let layoutVTableSize: UInt32
            }

            static let classTest = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("VTableDescriptorHeaderBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(for header: VTableDescriptorHeader) -> String {
        let offset = header.offset
        let vTableOffset = header.layout.vTableOffset
        let vTableSize = header.layout.vTableSize

        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(offset)),
            layoutVTableOffset: \(literal: vTableOffset),
            layoutVTableSize: \(literal: vTableSize)
        )
        """
        return expr.description
    }
}
