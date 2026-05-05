import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/ProtocolDescriptorRefBaseline.swift`.
///
/// `ProtocolDescriptorRef` is a tagged pointer wrapping a Swift
/// `ProtocolDescriptor` or an Objective-C protocol prefix, distinguished
/// by the low bit (`isObjC`). The fixture has no live `ProtocolDescriptorRef`
/// payload to source from (the type is a Runtime/ABI carrier reconstructed
/// on demand), so the baseline records canonical bit patterns for both
/// sides:
///   - Swift form: the storage is the descriptor pointer (low bit clear).
///   - ObjC form: the storage carries the low bit set.
/// The Suite (`ProtocolDescriptorRefTests`) constructs the refs via the
/// `forSwift(_:)` / `forObjC(_:)` factories and verifies the predicates
/// and accessors round-trip, plus an end-to-end `name(in:)` check via
/// the materialized ObjC inheriting protocol fixture.
package enum ProtocolDescriptorRefBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let objcPrefix = try BaselineFixturePicker.objcProtocolPrefix_first(in: machO)
        let objcPrefixOffset = objcPrefix.offset
        let objcName = try objcPrefix.name(in: machO)

        let swiftEntryExpr = emitSyntheticEntryExpr(storage: 0xDEAD_BEEF_0000, isObjC: false)
        let objcEntryExpr = emitSyntheticEntryExpr(storage: 0xDEAD_BEEF_0001, isObjC: true)
        let liveObjcExpr = emitLiveObjcEntryExpr(prefixOffset: objcPrefixOffset, name: objcName)

        // Public members declared directly in ProtocolDescriptorRef.swift.
        // Multiple overloads of `objcProtocol`/`swiftProtocol`/`name`
        // (MachO + InProcess + ReadingContext) collapse to single MethodKeys
        // under the scanner's name-based deduplication.
        let registered = [
            "dispatchStrategy",
            "forObjC",
            "forSwift",
            "init(storage:)",
            "isObjC",
            "name",
            "objcProtocol",
            "storage",
            "swiftProtocol",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // ProtocolDescriptorRef has no live carrier in SymbolTestsCore; the
        // baseline embeds synthetic storage bits to exercise the Swift/ObjC
        // tagged-pointer split. The `liveObjc` entry pins the resolved name
        // of the ObjC inheriting protocol's NSObjectProtocol witness.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ProtocolDescriptorRefBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let storage: UInt64
                let isObjC: Bool
                let dispatchStrategyRawValue: UInt8
            }

            struct LiveObjcEntry {
                let prefixOffset: Int
                let name: String
            }

            static let swift = \(raw: swiftEntryExpr)

            static let objc = \(raw: objcEntryExpr)

            static let liveObjc = \(raw: liveObjcExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ProtocolDescriptorRefBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitSyntheticEntryExpr(storage: UInt64, isObjC: Bool) -> String {
        let ref = isObjC
            ? ProtocolDescriptorRef.forObjC(StoredPointer(storage))
            : ProtocolDescriptorRef.forSwift(StoredPointer(storage))
        let dispatchStrategyRawValue = ref.dispatchStrategy.rawValue

        let expr: ExprSyntax = """
        Entry(
            storage: \(raw: BaselineEmitter.hex(ref.storage)),
            isObjC: \(literal: ref.isObjC),
            dispatchStrategyRawValue: \(raw: BaselineEmitter.hex(dispatchStrategyRawValue))
        )
        """
        return expr.description
    }

    private static func emitLiveObjcEntryExpr(prefixOffset: Int, name: String) -> String {
        let expr: ExprSyntax = """
        LiveObjcEntry(
            prefixOffset: \(raw: BaselineEmitter.hex(prefixOffset)),
            name: \(literal: name)
        )
        """
        return expr.description
    }
}
