import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
@testable import MachOSwiftSection

/// Emits `__Baseline__/ExistentialTypeFlagsBaseline.swift`.
///
/// Phase C3: emits ABI literals derived from in-process resolution of
/// stdlib existential metadata flags. Two metadata sources:
///   - `Any.self` flags (`0x80000000`) — `numberOfWitnessTables`,
///     `hasSuperclassConstraint`, `specialProtocol`, `rawValue`.
///   - `AnyObject.self` flags (`0x0`) — `classConstraint`. Required
///     because `Any.self`'s flags trap the source's
///     `UInt8(rawValue & 0x80000000)` accessor.
package enum ExistentialTypeFlagsBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let context = InProcessContext()

        let anyMetadata = try ExistentialTypeMetadata.resolve(
            at: InProcessMetadataPicker.stdlibAnyExistential,
            in: context
        )
        let anyFlags = anyMetadata.layout.flags
        let anyRawValue = anyFlags.rawValue
        let anyNumberOfWitnessTables = anyFlags.numberOfWitnessTables
        let anyHasSuperclassConstraint = anyFlags.hasSuperclassConstraint
        let anySpecialProtocolRaw = anyFlags.specialProtocol.rawValue

        let anyObjectMetadata = try ExistentialTypeMetadata.resolve(
            at: InProcessMetadataPicker.stdlibAnyObjectExistential,
            in: context
        )
        let anyObjectFlags = anyObjectMetadata.layout.flags
        let anyObjectRawValue = anyObjectFlags.rawValue
        let anyObjectClassConstraintRaw = anyObjectFlags.classConstraint.rawValue

        let registered = [
            "classConstraint",
            "hasSuperclassConstraint",
            "init(rawValue:)",
            "numberOfWitnessTables",
            "rawValue",
            "specialProtocol",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: swift package --allow-writing-to-package-directory regen-baselines
        // Source: InProcess (`Any.self` + `AnyObject.self`); no Mach-O section presence.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ExistentialTypeFlagsBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct AnyEntry {
                let rawValue: UInt32
                let numberOfWitnessTables: UInt32
                let hasSuperclassConstraint: Bool
                let specialProtocolRawValue: UInt8
            }

            struct AnyObjectEntry {
                let rawValue: UInt32
                let classConstraintRawValue: UInt8
            }

            static let stdlibAnyExistential = AnyEntry(
                rawValue: \(raw: BaselineEmitter.hex(anyRawValue)),
                numberOfWitnessTables: \(raw: BaselineEmitter.hex(anyNumberOfWitnessTables)),
                hasSuperclassConstraint: \(literal: anyHasSuperclassConstraint),
                specialProtocolRawValue: \(raw: BaselineEmitter.hex(anySpecialProtocolRaw))
            )

            static let stdlibAnyObjectExistential = AnyObjectEntry(
                rawValue: \(raw: BaselineEmitter.hex(anyObjectRawValue)),
                classConstraintRawValue: \(raw: BaselineEmitter.hex(anyObjectClassConstraintRaw))
            )
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ExistentialTypeFlagsBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
