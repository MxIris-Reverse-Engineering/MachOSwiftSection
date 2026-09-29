import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
import MachOKit
@testable import MachOSwiftSection

/// Emits `__Baseline__/ProtocolRecordBaseline.swift`.
///
/// `ProtocolRecord` is the one-pointer entry stored in the
/// `__swift5_protos` section. We pick the first record from the fixture
/// (which always exists, since `SymbolTestsCore` declares many protocols)
/// and record its offset plus the resolved descriptor offset.
package enum ProtocolRecordBaselineGenerator {
    package static func generate(
        in machO: MachOFile,
        outputDirectory: URL
    ) throws {
        let record = try BaselineFixturePicker.protocolRecord_first(in: machO)
        let resolvedDescriptor = try required(record.protocolDescriptor(in: machO))
        let resolvedDescriptorOffset = resolvedDescriptor.offset
        let resolvedDescriptorName = try resolvedDescriptor.name(in: machO)

        let entryExpr = emitEntryExpr(
            recordOffset: record.offset,
            resolvedDescriptorOffset: resolvedDescriptorOffset,
            resolvedDescriptorName: resolvedDescriptorName
        )

        // Public members declared directly in ProtocolRecord.swift.
        // The two `protocolDescriptor(in:)` overloads (MachO + ReadingContext)
        // collapse to a single MethodKey under the scanner's name-based
        // deduplication. `init(layout:offset:)` is filtered as memberwise-
        // synthesized.
        let registered = [
            "layout",
            "offset",
            "protocolDescriptor",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ProtocolRecordBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let resolvedDescriptorOffset: Int
                let resolvedDescriptorName: String
            }

            static let firstRecord = \(raw: entryExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ProtocolRecordBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntryExpr(
        recordOffset: Int,
        resolvedDescriptorOffset: Int,
        resolvedDescriptorName: String
    ) -> String {
        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(recordOffset)),
            resolvedDescriptorOffset: \(raw: BaselineEmitter.hex(resolvedDescriptorOffset)),
            resolvedDescriptorName: \(literal: resolvedDescriptorName)
        )
        """
        return expr.description
    }
}
