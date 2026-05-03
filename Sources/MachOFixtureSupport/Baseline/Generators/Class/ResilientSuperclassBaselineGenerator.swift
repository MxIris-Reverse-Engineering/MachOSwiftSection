import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/ResilientSuperclassBaseline.swift`.
///
/// `ResilientSuperclass` is the trailing-object record carrying a
/// `RelativeDirectRawPointer` to the superclass when a class has
/// `hasResilientSuperclass == true`. The `Classes.ExternalSwiftSubclassTest`
/// (which inherits from the SymbolTestsHelper `Object` resilient root)
/// surfaces this record. We try to pick a class that exposes one; if
/// none is available we fall back to a name-only baseline.
package enum ResilientSuperclassBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        // Public members declared directly in ResilientSuperclass.swift.
        // `init(layout:offset:)` is filtered as memberwise-synthesized.
        let registered = [
            "layout",
            "offset",
        ]

        // Search every Class in the fixture for one whose wrapper exposes
        // a resilient superclass record. `Classes.ExternalSwiftSubclassTest`
        // inherits from a resilient `Object`, so we expect at least one hit.
        let classes = try machO.swift.typeContextDescriptors.compactMap(\.class)
        var resilientSuperclassOffset: Int? = nil
        var sourceClassOffset: Int? = nil
        for descriptor in classes where descriptor.hasResilientSuperclass {
            let classWrapper = try Class(descriptor: descriptor, in: machO)
            if let resilient = classWrapper.resilientSuperclass {
                resilientSuperclassOffset = resilient.offset
                sourceClassOffset = descriptor.offset
                break
            }
        }

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // ResilientSuperclass appears in classes with a resilient superclass.
        // The Suite picks the first such class via Class.resilientSuperclass
        // and asserts cross-reader agreement on the record offset.
        """

        let file: SourceFileSyntax
        if let resilientSuperclassOffset, let sourceClassOffset {
            file = """
            \(raw: header)

            enum ResilientSuperclassBaseline {
                static let registeredTestMethodNames: Set<String> = \(literal: registered)

                struct Entry {
                    let sourceClassOffset: Int
                    let offset: Int
                }

                static let firstResilientSuperclass = Entry(
                    sourceClassOffset: \(raw: BaselineEmitter.hex(sourceClassOffset)),
                    offset: \(raw: BaselineEmitter.hex(resilientSuperclassOffset))
                )
            }
            """
        } else {
            file = """
            \(raw: header)

            enum ResilientSuperclassBaseline {
                static let registeredTestMethodNames: Set<String> = \(literal: registered)
            }
            """
        }

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ResilientSuperclassBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
