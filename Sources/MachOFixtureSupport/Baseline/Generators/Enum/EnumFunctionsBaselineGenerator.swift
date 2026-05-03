import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
@testable import MachOSwiftSection

/// Emits `__Baseline__/EnumFunctionsBaseline.swift`.
///
/// `EnumFunctions.swift` declares the value type `EnumTagCounts` (with two
/// public stored ivars) and one top-level helper function
/// `getEnumTagCounts(payloadSize:emptyCases:payloadCases:)`.
///
/// Top-level free functions do not have an enclosing type, so
/// `PublicMemberScanner` cannot emit a `MethodKey` for them; they are
/// covered indirectly by the consumers that exercise the helper. The
/// registered set therefore captures only `EnumTagCounts.numTags` and
/// `EnumTagCounts.numTagBytes`.
///
/// We compute the baseline via a deterministic input set so the literal is
/// reader-independent — `getEnumTagCounts` is a pure function with no
/// MachO dependency.
package enum EnumFunctionsBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        // Public ivars declared on EnumTagCounts in EnumFunctions.swift.
        let registered = [
            "numTagBytes",
            "numTags",
        ]

        // Pure-function baseline: we evaluate `getEnumTagCounts` against a
        // small set of inputs covering each branch (no empty cases,
        // payload < 4 bytes, payload >= 4 bytes, large numTags) so the
        // companion Suite can re-evaluate and assert literal equality.
        let counts = [
            // (payloadSize, emptyCases, payloadCases)
            (UInt64(0), UInt32(0), UInt32(0)),
            (UInt64(0), UInt32(4), UInt32(0)),     // small payload, emptyCases > 0
            (UInt64(1), UInt32(256), UInt32(1)),   // payload 1, casesPerTagBitValue path
            (UInt64(4), UInt32(1), UInt32(2)),     // payload >= 4, +1 path
            (UInt64(8), UInt32(65536), UInt32(0)), // large numTags → 4-byte tag bytes
        ]
        let entries: [(input: (UInt64, UInt32, UInt32), output: EnumTagCounts)] = counts.map { input in
            let output = getEnumTagCounts(payloadSize: input.0, emptyCases: input.1, payloadCases: input.2)
            return (input: input, output: output)
        }
        let entriesExpr = emitEntriesExpr(for: entries)

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // EnumFunctions baselines are reader-independent: the helper
        // `getEnumTagCounts` is a pure function. The Suite asserts literal
        // equality against the cases below.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum EnumFunctionsBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let payloadSize: UInt64
                let emptyCases: UInt32
                let payloadCases: UInt32
                let numTags: UInt32
                let numTagBytes: UInt32
            }

            static let cases: [Entry] = \(raw: entriesExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("EnumFunctionsBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntriesExpr(
        for entries: [(input: (UInt64, UInt32, UInt32), output: EnumTagCounts)]
    ) -> String {
        let lines = entries.map { entry -> String in
            let (payloadSize, emptyCases, payloadCases) = entry.input
            return """
            Entry(
                payloadSize: \(BaselineEmitter.hex(payloadSize)),
                emptyCases: \(BaselineEmitter.hex(emptyCases)),
                payloadCases: \(BaselineEmitter.hex(payloadCases)),
                numTags: \(BaselineEmitter.hex(entry.output.numTags)),
                numTagBytes: \(BaselineEmitter.hex(entry.output.numTagBytes))
            )
            """
        }
        return "[\n\(lines.joined(separator: ",\n"))\n]"
    }
}
