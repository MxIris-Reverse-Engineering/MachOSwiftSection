import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
@testable import MachOSwiftSection

/// Emits `__Baseline__/ForeignClassMetadataBaseline.swift`.
///
/// Phase B6: `ForeignClassMetadata` is exercised as a real InProcess
/// test against `CFString.self` — the Swift compiler emits kind 0x203
/// foreign-class metadata for CoreFoundation types imported into Swift.
/// SymbolTestsCore's `ForeignTypeFixtures` references CFString /
/// CFArray to make the bridging usage visible at the fixture level,
/// but the canonical `ForeignClassMetadata` carrier is CoreFoundation's
/// own metadata which the runtime returns via
/// `unsafeBitCast(CFString.self, ...)`.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
package enum ForeignClassMetadataBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let pointer = InProcessMetadataPicker.coreFoundationCFString
        let context = InProcessContext()
        let metadata = try ForeignClassMetadata.resolve(at: pointer, in: context)
        let kindRaw = metadata.layout.kind

        let registered = [
            "classDescriptor",
            "layout",
            "offset",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: swift package --allow-writing-to-package-directory regen-baselines
        // Source: InProcess (`CoreFoundation.CFString.self`); no SymbolTestsCore section presence.
        //
        // ForeignClassMetadata is the metadata kind the Swift compiler
        // emits for CoreFoundation foreign classes (CFString, CFArray, etc.).
        // The metadata lives in CoreFoundation; Swift uses
        // `unsafeBitCast(CFString.self, to: UnsafeRawPointer.self)` to
        // obtain the metadata pointer at runtime. Phase B6 introduced
        // `ForeignTypeFixtures` to surface CFString/CFArray references
        // in SymbolTestsCore so the bridging usage is documented; the
        // canonical carrier is CoreFoundation's own runtime metadata.
        //
        // `init(layout:offset:)` is filtered as memberwise-synthesized.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ForeignClassMetadataBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let kindRawValue: UInt64
            }

            static let coreFoundationCFString = Entry(
                kindRawValue: \(raw: BaselineEmitter.hex(kindRaw))
            )
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ForeignClassMetadataBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
