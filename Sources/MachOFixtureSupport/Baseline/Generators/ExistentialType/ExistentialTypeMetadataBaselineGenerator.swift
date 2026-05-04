import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
@testable import MachOSwiftSection

/// Emits `__Baseline__/ExistentialTypeMetadataBaseline.swift`.
///
/// Phase C3: emits ABI literals derived from in-process resolution of two
/// stdlib existential metadata sources:
///   - `Any.self` — maximally-general existential, kind 0x303, flags
///     `0x80000000` (`classConstraint == .any`), zero protocols. Anchors
///     `layout`, `offset`, `numberOfProtocols`, `superclassConstraint`,
///     `protocols`.
///   - `AnyObject.self` — class-bounded existential with zero witness
///     tables (flags `0x0`). Required for `isClassBounded` / `isObjC` /
///     `representation` because `Any.self`'s flags decode to a value that
///     traps the source's `UInt8(rawValue & 0x80000000)` accessor.
///
/// Registered names track the wrapper's directly-declared public surface
/// (`layout`, `offset`, `isClassBounded`, `isObjC`, `representation`,
/// `superclassConstraint`, `protocols`).
package enum ExistentialTypeMetadataBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let context = InProcessContext()

        let anyMetadata = try ExistentialTypeMetadata.resolve(
            at: InProcessMetadataPicker.stdlibAnyExistential,
            in: context
        )
        let anyKindRaw = anyMetadata.kind.rawValue
        let anyFlagsRaw = anyMetadata.layout.flags.rawValue
        let anyNumProtocols = anyMetadata.layout.numberOfProtocols

        let anyObjectMetadata = try ExistentialTypeMetadata.resolve(
            at: InProcessMetadataPicker.stdlibAnyObjectExistential,
            in: context
        )
        let anyObjectIsClassBounded = anyObjectMetadata.isClassBounded
        let anyObjectIsObjC = anyObjectMetadata.isObjC

        let registered = [
            "isClassBounded",
            "isObjC",
            "layout",
            "offset",
            "protocols",
            "representation",
            "superclassConstraint",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: swift package --allow-writing-to-package-directory regen-baselines
        // Source: InProcess (`Any.self` + `AnyObject.self`); no Mach-O section presence.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ExistentialTypeMetadataBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let kindRawValue: UInt32
                let flagsRawValue: UInt32
                let numberOfProtocols: UInt32
                let isClassBounded: Bool
                let isObjC: Bool
            }

            static let stdlibAnyExistential = Entry(
                kindRawValue: \(raw: BaselineEmitter.hex(anyKindRaw)),
                flagsRawValue: \(raw: BaselineEmitter.hex(anyFlagsRaw)),
                numberOfProtocols: \(raw: BaselineEmitter.hex(anyNumProtocols)),
                isClassBounded: false,
                isObjC: false
            )

            static let stdlibAnyObjectExistential = Entry(
                kindRawValue: \(raw: BaselineEmitter.hex(anyMetadata.kind.rawValue)),
                flagsRawValue: \(raw: BaselineEmitter.hex(anyObjectMetadata.layout.flags.rawValue)),
                numberOfProtocols: \(raw: BaselineEmitter.hex(anyObjectMetadata.layout.numberOfProtocols)),
                isClassBounded: \(literal: anyObjectIsClassBounded),
                isObjC: \(literal: anyObjectIsObjC)
            )
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ExistentialTypeMetadataBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
