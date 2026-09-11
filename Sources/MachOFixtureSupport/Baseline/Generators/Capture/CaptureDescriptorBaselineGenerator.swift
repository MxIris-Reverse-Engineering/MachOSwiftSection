import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import MachOFoundation
@testable import MachOSwiftSection

/// Emits `__Baseline__/CaptureDescriptorBaseline.swift`.
///
/// Three descriptors from `__swift5_capture`, picked by shape rather than by
/// position: a non-generic closure's context (no metadata sources), a closure
/// in a one-parameter generic function (one), and one in a two-parameter
/// generic function (two) — so the trailing arrays are pinned at length zero,
/// one and many.
package enum CaptureDescriptorBaselineGenerator {
    package static func generate(
        in machO: some MachOSwiftSectionRepresentableWithCache,
        outputDirectory: URL
    ) throws {
        let descriptors = try CaptureFixtureDescriptors(in: machO)

        let registered = [
            "actualSize",
            "captureTypeRecords",
            "captureTypeRecordsOffset",
            "layout",
            "metadataSourceRecords",
            "metadataSourceRecordsOffset",
            "offset",
        ]

        let header = """
        // AUTO-GENERATED — DO NOT EDIT.
        // Regenerate via: Scripts/regen-baselines.sh
        // Source fixture: SymbolTestsCore.framework
        //
        // Three capture descriptors, picked by shape: zero, one and two
        // metadata sources. Captured types are symbolic-reference-bearing
        // mangled names and are not embedded as literals; the metadata
        // SOURCE expressions are plain ASCII (closure-binding indices) and
        // are, because they are the one place the recipe language is
        // visible.
        """

        let file: SourceFileSyntax = """
        \(raw: header)

        enum CaptureDescriptorBaseline {
            static let registeredTestMethodNames: Set<String> = \(literal: registered)

            struct Entry {
                let offset: Int
                let numberOfCaptureTypes: Int
                let numberOfMetadataSources: Int
                let numberOfBindings: Int
                let actualSize: Int
                let captureTypeRecordsOffset: Int
                let metadataSourceRecordsOffset: Int
                let mangledMetadataSources: [String]
            }

            static let withoutMetadataSources = \(raw: try emitEntry(for: descriptors.withoutMetadataSources, in: machO))

            static let withSingleMetadataSource = \(raw: try emitEntry(for: descriptors.withSingleMetadataSource, in: machO))

            static let withMultipleMetadataSources = \(raw: try emitEntry(for: descriptors.withMultipleMetadataSources, in: machO))

            static let descriptorCount = \(literal: try BaselineFixturePicker.captureDescriptors(in: machO).count)
        }
        """

        let formatted = file.formatted().description + "\n"
        let outputURL = outputDirectory.appendingPathComponent("CaptureDescriptorBaseline.swift")
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private static func emitEntry(
        for descriptor: CaptureDescriptor,
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) throws -> String {
        let mangledMetadataSources = try descriptor.metadataSourceRecords(in: machO).map {
            try $0.mangledMetadataSource(in: machO).rawString
        }
        let expr: ExprSyntax = """
        Entry(
            offset: \(raw: BaselineEmitter.hex(descriptor.offset)),
            numberOfCaptureTypes: \(literal: descriptor.numberOfCaptureTypes),
            numberOfMetadataSources: \(literal: descriptor.numberOfMetadataSources),
            numberOfBindings: \(literal: descriptor.numberOfBindings),
            actualSize: \(literal: descriptor.actualSize),
            captureTypeRecordsOffset: \(raw: BaselineEmitter.hex(descriptor.captureTypeRecordsOffset)),
            metadataSourceRecordsOffset: \(raw: BaselineEmitter.hex(descriptor.metadataSourceRecordsOffset)),
            mangledMetadataSources: \(literal: mangledMetadataSources)
        )
        """
        return expr.description
    }
}
