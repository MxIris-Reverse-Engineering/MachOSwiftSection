import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/KeyPathComputedPropertyBodyBaseline.swift`.
///
/// The one computed fixture is a resilient class's settable property, so all
/// three words are present. Every offset is pure relative-pointer arithmetic
/// off the body's own location, so the values agree across readers.
package enum KeyPathComputedPropertyBodyBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptors = try KeyPathFixtureDescriptors(in: machO)
        let body = try required(descriptors.computedSettable.computedPropertyBody(in: machO))

        let registered = [
            "getter",
            "getterFieldOffset",
            "getterOffset",
            "header",
            "identifierFieldOffset",
            "identifierOffset",
            "offset",
            "rawIdentifier",
            "setter",
            "setterFieldOffset",
            "setterOffset",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // CodableTests.CodableClassTest.identifier — a settable computed
        // component, so identifier, getter and setter are all present.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum KeyPathComputedPropertyBodyBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let headerRawValue: UInt32
                let offset: Int
                let rawIdentifier: Int32
                let getterRelativeOffset: Int32
                let setterRelativeOffset: Int32?
                let identifierFieldOffset: Int
                let getterFieldOffset: Int
                let setterFieldOffset: Int?
                let identifierOffset: Int?
                let getterOffset: Int?
                let setterOffset: Int?
            }

            static let codableClassIdentifier = \(raw: emitEntry(for: body))
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("KeyPathComputedPropertyBodyBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntry(for body: KeyPathComputedPropertyBody) -> String {
        let expr: ExprSyntax = """
        Entry(
            headerRawValue: \(raw: BaselineEmitter.hex(body.header.rawValue)),
            offset: \(raw: BaselineEmitter.hex(body.offset)),
            rawIdentifier: \(literal: body.rawIdentifier),
            getterRelativeOffset: \(literal: body.getter.relativeOffset),
            setterRelativeOffset: \(raw: body.setter.map { String($0.relativeOffset) } ?? "nil"),
            identifierFieldOffset: \(raw: BaselineEmitter.hex(body.identifierFieldOffset)),
            getterFieldOffset: \(raw: BaselineEmitter.hex(body.getterFieldOffset)),
            setterFieldOffset: \(raw: BaselineEmitter.optionalHex(body.setterFieldOffset)),
            identifierOffset: \(raw: BaselineEmitter.optionalHex(body.identifierOffset)),
            getterOffset: \(raw: BaselineEmitter.optionalHex(body.getterOffset)),
            setterOffset: \(raw: BaselineEmitter.optionalHex(body.setterOffset))
        )
        """
        return expr.description
    }
}
