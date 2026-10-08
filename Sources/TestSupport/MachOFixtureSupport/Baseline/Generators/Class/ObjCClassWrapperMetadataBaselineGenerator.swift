import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
@testable import MachOSwiftSection

/// Emits `__Baseline__/ObjCClassWrapperMetadataBaseline.swift`.
///
/// Phase B3: `ObjCClassWrapperMetadata` is exercised as a real
/// InProcess test against `NSObject.self` — the Swift runtime allocates
/// kind 0x305 wrapper metadata for plain ObjC classes. Phase B3 added
/// `ObjCClassWrappers.swift` to the SymbolTestsCore fixture (so the
/// fixture itself contains NSObject-derived classes); however the
/// canonical `ObjCClassWrapperMetadata` carrier is NSObject's own
/// runtime metadata, which is allocated by Swift's bridging layer on
/// first use.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
package enum ObjCClassWrapperMetadataBaselineGenerator {
    package static func generate(outputDirectory: URL) throws {
        let pointer = InProcessMetadataPicker.foundationNSObjectWrapper
        let context = InProcessContext()
        let metadata = try ObjCClassWrapperMetadata.resolve(at: pointer, in: context)
        let kindRaw = metadata.layout.kind

        let registered = ["layout", "offset"]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: swift package --allow-writing-to-package-directory regen-baselines
        // Source: InProcess (`Foundation.NSObject.self`); no Mach-O section presence.
        //
        // ObjCClassWrapperMetadata is allocated by the Swift runtime on
        // first reference to a pure ObjC class. Phase B3 introduced the
        // SymbolTestsCore fixture's `ObjCClassWrapperFixtures` namespace
        // to surface NSObject-derived classes for the broader ObjC-interop
        // metadata Suites; the wrapper itself is canonically tested
        // against NSObject's runtime metadata.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum ObjCClassWrapperMetadataBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let kindRawValue: UInt64
            }

            static let foundationNSObject = Entry(
                kindRawValue: \(raw: BaselineEmitter.hex(kindRaw))
            )
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("ObjCClassWrapperMetadataBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
