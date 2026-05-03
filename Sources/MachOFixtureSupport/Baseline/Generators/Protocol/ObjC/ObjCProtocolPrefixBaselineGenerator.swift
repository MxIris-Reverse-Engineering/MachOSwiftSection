import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/ObjCProtocolPrefixBaseline.swift`.
///
/// `ObjCProtocolPrefix` is the in-memory prefix of an Objective-C
/// `protocol_t` record (the `isa` slot plus the name pointer). We
/// materialize one via the fixture's ObjC inheriting protocol
/// (`Protocols.ObjCInheritingProtocolTest: NSObjectProtocol`), which
/// synthesizes an ObjC reference whose prefix resolves to
/// `NSObject` (the runtime backing of the `NSObjectProtocol`).
package enum ObjCProtocolPrefixBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let prefix = try BaselineFixturePicker.objcProtocolPrefix_first(in: machO)
        let name = try prefix.name(in: machO)
        let entryExpr = emitEntryExpr(offset: prefix.offset, name: name)

        // Public members declared directly in ObjCProtocolPrefix.swift.
        // The `name(in:)` and `mangledName(in:)` overloads (MachO + InProcess
        // + ReadingContext) collapse to single MethodKeys under the
        // scanner's name-based deduplication. `init(layout:offset:)` is
        // filtered as memberwise-synthesized.
        let registered = [
            "layout",
            "mangledName",
            "name",
            "offset",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ObjCProtocolPrefixBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let name: String
            }

            static let firstPrefix = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ObjCProtocolPrefixBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(offset: Int, name: String) -> String {
        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(offset)),
            name: \(literal: name)
        )
        """
        return expr.description
    }
}
