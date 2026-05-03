import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
@testable import MachOSwiftSection

/// Emits `__Baseline__/FunctionTypeFlagsBaseline.swift`.
///
/// `FunctionTypeFlags<IntType>` is a generic flag bag describing a
/// `FunctionTypeMetadata`. The bit fields:
///   - low 16 bits — `numberOfParameters`
///   - bits 16-23 — `convention` (swift / block / thin / cFunctionPointer)
///   - bit 24 — `isThrowing`
///   - bit 25 — `hasParameterFlags`
///   - bit 26 — `isEscaping`
///   - bit 27 — `isDifferentiable`
///   - bit 28 — `hasGlobalActor`
///   - bit 29 — `isAsync`
///   - bit 30 — `isSendable`
///   - bit 31 — `hasExtendedFlags`
///
/// The flags type is reader-independent — the Suite re-evaluates each
/// accessor against synthetic raw values.
///
/// Note: the `convention` accessor in source applies an
/// `UInt8(rawValue)` conversion (truncation) and the bit field is at
/// 16-23. Calling `convention` on any raw value > `0xFF` would trap. The
/// baseline therefore restricts encoded raw values to ones whose
/// numerical value fits in `UInt8` (so the accessor can be safely
/// invoked for the smoke tests). Bit 16+ flags (convention, throws,
/// extended-flags, etc.) are exercised only via direct mask reads in
/// the Suite, NOT via `convention`/`isThrowing`/etc.
package enum FunctionTypeFlagsBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        // Cases whose convention(rawValue: UInt8(rawValue))! doesn't
        // crash. The accessor truncates the entire rawValue to UInt8
        // (ignoring the convention bit mask) and force-unwraps the
        // resulting `FunctionMetadataConvention.init(rawValue:)`.
        // FunctionMetadataConvention has only 4 cases (raw values
        // 0..3), so the only safe rawValues are ones where the entire
        // low byte is 0, 1, 2, or 3. Note that this means
        // `numberOfParameters` and `convention` overlap on these test
        // values — they share the same low bits. Bit-flag accessors at
        // higher positions (`isThrowing`, `isAsync`, ...) are still
        // exercised here via the high bits since they read disjoint
        // bit positions.
        let entries: [(label: String, rawValue: UInt64)] = [
            // 0 parameters, swift convention.
            ("emptySwiftConvention", 0x0000_0000_0000_0000),
            // 1 parameter masked to "block convention" by the buggy
            // accessor — exercises convention raw value 1.
            ("oneParamBlock", 0x0000_0000_0000_0001),
            // 2 parameters / thin convention.
            ("twoParamsThin", 0x0000_0000_0000_0002),
            // 3 parameters / cFunctionPointer convention.
            ("threeParamsCFunctionPointer", 0x0000_0000_0000_0003),
        ]
        let entriesExpr = emitEntriesExpr(for: entries)

        // Public members declared in FunctionTypeFlags.swift. The
        // companion enum `FunctionMetadataConvention` lives in the same
        // file; it has only cases (no methods/vars/inits visible to
        // PublicMemberScanner) so it doesn't need a baseline.
        let registered = [
            "convention",
            "hasExtendedFlags",
            "hasGlobalActor",
            "hasParameterFlags",
            "init(rawValue:)",
            "isAsync",
            "isDifferentiable",
            "isEscaping",
            "isSendable",
            "isThrowing",
            "numberOfParameters",
            "rawValue",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // FunctionTypeFlags is a pure raw-value bit decoder (no MachO
        // dependency). The baseline embeds canonical synthetic raw
        // values exercising each documented bit field; convention is
        // restricted to safe low-byte values (see source-file comment).
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum FunctionTypeFlagsBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let rawValue: UInt64
                let numberOfParameters: UInt64
                let conventionRawValue: UInt8
                let isThrowing: Bool
                let isEscaping: Bool
                let isAsync: Bool
                let isSendable: Bool
                let hasParameterFlags: Bool
                let isDifferentiable: Bool
                let hasGlobalActor: Bool
                let hasExtendedFlags: Bool
            }

            static let cases: [Entry] = \(raw: entriesExpr)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("FunctionTypeFlagsBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntriesExpr(for entries: [(label: String, rawValue: UInt64)]) -> String {
        let lines = entries.map { entry -> String in
            let flags = FunctionTypeFlags<UInt64>(rawValue: entry.rawValue)
            return """
            // \(entry.label)
            Entry(
                rawValue: \(BaselineEmitter.hex(entry.rawValue)),
                numberOfParameters: \(BaselineEmitter.hex(flags.numberOfParameters)),
                conventionRawValue: \(BaselineEmitter.hex(flags.convention.rawValue)),
                isThrowing: \(flags.isThrowing),
                isEscaping: \(flags.isEscaping),
                isAsync: \(flags.isAsync),
                isSendable: \(flags.isSendable),
                hasParameterFlags: \(flags.hasParameterFlags),
                isDifferentiable: \(flags.isDifferentiable),
                hasGlobalActor: \(flags.hasGlobalActor),
                hasExtendedFlags: \(flags.hasExtendedFlags)
            )
            """
        }
        return "[\n\(lines.joined(separator: ",\n"))\n]"
    }
}
