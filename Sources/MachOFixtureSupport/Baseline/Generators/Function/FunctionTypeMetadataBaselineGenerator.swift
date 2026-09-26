import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
@testable import MachOSwiftSection

/// Emits `__Baseline__/FunctionTypeMetadataBaseline.swift`.
///
/// Function type metadata is runtime-allocated and appears in no Mach-O
/// section, so the carriers are live in-process types and the recorded
/// values are the flag words and counts — never addresses, which move with
/// every launch. The Suite compares the trailing types against the metadata
/// of the very types the carriers name, which is a stronger check than any
/// literal could be.
package enum FunctionTypeMetadataBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let context = InProcessContext()

        func entry(for pointer: UnsafeRawPointer) throws -> String {
            let metadata = try FunctionTypeMetadata.resolve(at: pointer, in: context)
            let extendedFlags = try metadata.extendedFlags(in: context)
            let expr: ExprSyntax = """
            Entry(
                kindRawValue: \(raw: BaselineEmitter.hex(metadata.kind.rawValue)),
                flagsRawValue: \(raw: BaselineEmitter.hex(metadata.layout.flags.rawValue)),
                numberOfParameters: \(literal: metadata.numberOfParameters),
                hasParameterFlags: \(literal: metadata.flags.hasParameterFlags),
                isDifferentiable: \(literal: metadata.flags.isDifferentiable),
                hasGlobalActor: \(literal: metadata.flags.hasGlobalActor),
                hasExtendedFlags: \(literal: metadata.flags.hasExtendedFlags),
                extendedFlagsRawValue: \(raw: BaselineEmitter.optionalHex(extendedFlags?.rawValue)),
                isTypedThrows: \(literal: extendedFlags?.isTypedThrows ?? false)
            )
            """
            return expr.description
        }

        let intToVoid = try entry(for: InProcessMetadataPicker.stdlibFunctionIntToVoid)
        let intStringToBool = try entry(for: InProcessMetadataPicker.stdlibFunctionIntStringToBool)
        let inOutIntToVoid = try entry(for: InProcessMetadataPicker.stdlibFunctionInOutIntToVoid)
        let mainActorTypedThrows: String
        if #available(macOS 15.0, *) {
            mainActorTypedThrows = try entry(for: InProcessMetadataPicker.stdlibFunctionMainActorTypedThrows)
        } else {
            mainActorTypedThrows = "nil"
        }

        let registered = [
            "differentiabilityKind",
            "differentiabilityKindOffset",
            "extendedFlags",
            "extendedFlagsOffset",
            "globalActorOffset",
            "globalActorType",
            "layout",
            "numberOfParameters",
            "offset",
            "parameterFlags",
            "parameterFlagsOffset",
            "parameters",
            "parametersOffset",
            "thrownErrorType",
            "thrownErrorTypeOffset",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: swift package --allow-writing-to-package-directory regen-baselines
        // Source: live in-process function types; no Mach-O section presence.
        //
        // Only flag words and counts are recorded. Metadata addresses move
        // with every launch, and the trailing TYPES are checked in the Suite
        // against the metadata of the types the carriers name.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum FunctionTypeMetadataBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let kindRawValue: UInt32
                let flagsRawValue: UInt64
                let numberOfParameters: Int
                let hasParameterFlags: Bool
                let isDifferentiable: Bool
                let hasGlobalActor: Bool
                let hasExtendedFlags: Bool
                let extendedFlagsRawValue: UInt32?
                let isTypedThrows: Bool
            }

            static let stdlibFunctionIntToVoid = \(raw: intToVoid)

            static let stdlibFunctionIntStringToBool = \(raw: intStringToBool)

            static let stdlibFunctionInOutIntToVoid = \(raw: inOutIntToVoid)

            /// `nil` when the baseline was generated below macOS 15, where
            /// the typed-throws carrier cannot be formed.
            static let stdlibFunctionMainActorTypedThrows: Entry? = \(raw: mainActorTypedThrows)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("FunctionTypeMetadataBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
