import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/AccessibleFunctionRecordBaseline.swift`.
///
/// Two of the fixture's four `__swift5_acfuncs` records: a non-generic
/// distributed target and the one generic target, which is what makes the
/// nullable generic environment pointer testable in both states.
///
/// Live `MangledName` payloads are not embedded as literals (same rule as
/// `FieldRecordBaseline`); the Suite checks the function type resolves
/// consistently across readers against the presence flag recorded here.
package enum AccessibleFunctionRecordBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let nonGeneric = try BaselineFixturePicker.accessibleFunctionRecord_nonGeneric(in: machO)
        let generic = try BaselineFixturePicker.accessibleFunctionRecord_generic(in: machO)

        let registered = [
            "flags",
            "functionAddress",
            "functionOffset",
            "functionType",
            "genericEnvironment",
            "genericEnvironmentOffset",
            "isDistributed",
            "layout",
            "name",
            "offset",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // Two accessible function records: a non-generic distributed target
        // (null generic environment) and the one generic target (non-null).
        // Live MangledName payloads aren't embedded as literals; the
        // companion Suite verifies the function type resolves
        // cross-reader-consistently against the presence flag recorded here.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum AccessibleFunctionRecordBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let name: String
                let functionOffset: Int?
                let genericEnvironmentOffset: Int?
                let flagsRawValue: UInt32
                let isDistributed: Bool
                let hasFunctionType: Bool
            }

            static let nonGeneric = \(raw: try emitEntry(for: nonGeneric, in: machO))

            static let generic = \(raw: try emitEntry(for: generic, in: machO))

            static let recordCount = \(literal: try BaselineFixturePicker.accessibleFunctionRecords(in: machO).count)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("AccessibleFunctionRecordBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntry(
        for record: AccessibleFunctionRecord,
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> String {
        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(record.offset)),
            name: \(literal: try record.name(in: machO)),
            functionOffset: \(raw: BaselineEmitter.optionalHex(record.functionOffset)),
            genericEnvironmentOffset: \(raw: BaselineEmitter.optionalHex(record.genericEnvironmentOffset)),
            flagsRawValue: \(raw: BaselineEmitter.hex(record.flags.rawValue)),
            isDistributed: \(literal: record.isDistributed),
            hasFunctionType: \(literal: !(try record.functionType(in: machO).isEmpty))
        )
        """
        return expr.description
    }
}
