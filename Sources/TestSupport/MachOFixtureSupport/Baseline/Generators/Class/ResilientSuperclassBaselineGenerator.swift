import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/ResilientSuperclassBaseline.swift`.
///
/// `ResilientSuperclass` is the trailing-object record carrying a
/// `RelativeDirectRawPointer` to the superclass when a class has
/// `hasResilientSuperclass == true`. The fixture `ResilientChild`
/// (whose parent `SymbolTestsHelper.ResilientBase` lives in a different
/// module) is the canonical carrier — Phase B2 introduced it to give
/// `ResilientSuperclassTests` a stably-named, deterministic subject.
package enum ResilientSuperclassBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        // Public members declared directly in ResilientSuperclass.swift.
        // `init(layout:offset:)` is filtered as memberwise-synthesized;
        // `superclass` is the inner Layout's stored field, exercised
        // transitively via the `layout` test.
        let registered = [
            "layout",
            "offset",
        ]

        let descriptor = try BaselineFixturePicker.class_ResilientChild(in: machO)
        let classWrapper = try Class(descriptor: descriptor, in: machO)
        let resilientSuperclass = try required(classWrapper.resilientSuperclass)

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // ResilientSuperclass is the trailing-object record on a class
        // whose parent lives in a different module. The Suite drives
        // `ResilientClassFixtures.ResilientChild` (parent
        // `SymbolTestsHelper.ResilientBase`) and asserts cross-reader
        // agreement on the record offset and the superclass reference's
        // relative-offset scalar.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ResilientSuperclassBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let sourceClassOffset: Int
                let offset: Int
                let layoutSuperclassRelativeOffset: Int32
            }

            static let resilientChild = Entry(
                sourceClassOffset: \(raw: BaselineEmitter.hex(descriptor.offset)),
                offset: \(raw: BaselineEmitter.hex(resilientSuperclass.offset)),
                layoutSuperclassRelativeOffset: \(literal: resilientSuperclass.layout.superclass.relativeOffset)
            )
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ResilientSuperclassBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
