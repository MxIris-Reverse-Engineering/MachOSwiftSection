import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/AsyncFunctionPointerBaseline.swift`.
///
/// An async function pointer record has no section to walk, so the three
/// entries are picked by `…Tu` symbol name (see
/// `AsyncFunctionPointerFixtureSymbol`). Both recorded values are pure
/// relative-pointer / header arithmetic, so both are identical across
/// readers.
package enum AsyncFunctionPointerBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let records = try AsyncFunctionPointerFixtureRecords(in: machO)

        let registered = [
            "expectedContextSize",
            "functionAddress",
            "functionOffset",
            "layout",
            "offset",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // Three async function pointer records, picked by `…Tu` symbol: a
        // top-level async function, an async class method a vtable slot
        // points at, and a distributed thunk (the largest async context in
        // the fixture).
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum AsyncFunctionPointerBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let functionOffset: Int?
                let expectedContextSize: UInt32
            }

            static let globalFunction = \(raw: emitEntry(for: records.globalFunction))

            static let vtableMethod = \(raw: emitEntry(for: records.vtableMethod))

            static let distributedThunk = \(raw: emitEntry(for: records.distributedThunk))
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("AsyncFunctionPointerBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntry(for record: AsyncFunctionPointer) -> String {
        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(record.offset)),
            functionOffset: \(raw: BaselineEmitter.optionalHex(record.functionOffset)),
            expectedContextSize: \(literal: record.expectedContextSize)
        )
        """
        return expr.description
    }
}
