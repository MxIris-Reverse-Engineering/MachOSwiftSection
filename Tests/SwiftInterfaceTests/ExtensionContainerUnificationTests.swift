@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
@_spi(Support) @testable import SwiftPrinting
import Foundation
import Testing
import MachOKit
@_spi(Support) @testable import SwiftInterface
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Coverage for the extension-container unification (evolution proposal 0007):
/// same-identity bucket merging, protocol attachment (a protocol's extension
/// block renders once, trailing its protocol declaration), and the
/// re-preparation idempotence the bucket reset provides.
@Suite(.serialized)
final class ExtensionContainerUnificationTests: MachOFileTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SymbolTestsCore }

    private func makeBuilder() throws -> SwiftInterfaceBuilder<MachOFile> {
        try SwiftInterfaceBuilder(configuration: .init(indexConfiguration: .init(showCImportedTypes: false)), eventHandlers: [], in: machOFile)
    }

    /// No two MEMBER-carrying eager definitions may share one (name,
    /// protocol, where-clause, retroactive) container identity across the
    /// four buckets — two such blocks are one source container printed twice,
    /// exactly the duplication issue #106 §5 reported (`grep -c` returned 3
    /// for one protocol's extension header).
    ///
    /// Typealias-only blocks are exempt: a bare `extension X { typealias … }`
    /// block (the P1-9 merge representative, filed in the conformance bucket
    /// for its assocwitness attribution) may share its header text with the
    /// type's member block. Merging the pair would move content across
    /// buckets, and the ABI-diff layer snapshots containers per bucket with a
    /// frozen format — a known cosmetic residual, not a duplicate container.
    @Test func memberCarryingContainerIdentitiesAreUnique() async throws {
        let builder = try makeBuilder()
        try await builder.prepare()
        _ = try await builder.printRoot()

        let allBuckets = [
            builder.indexer.typeExtensionDefinitions,
            builder.indexer.protocolExtensionDefinitions,
            builder.indexer.typeAliasExtensionDefinitions,
            builder.indexer.conformanceExtensionDefinitions,
        ]
        var seenIdentities: Set<String> = []
        var duplicatedIdentities: [String] = []
        for buckets in allBuckets {
            for (extensionName, definitions) in buckets {
                for definition in definitions where definition.protocolConformanceDescriptor == nil && definition.hasMembers {
                    let signatureText = await definition.genericSignature?.print(using: .default) ?? "-"
                    let protocolText = definition.conformingProtocolName?.name ?? "-"
                    let identity = "\(extensionName.name)|\(protocolText)|\(signatureText)|\(definition.isRetroactive)"
                    if !seenIdentities.insert(identity).inserted {
                        duplicatedIdentities.append(identity)
                    }
                }
            }
        }
        #expect(duplicatedIdentities.isEmpty, "duplicated member-carrying containers: \(duplicatedIdentities)")
    }

    /// A protocol's symbol-scan extension block is attached to the protocol
    /// definition and renders trailing the protocol declaration — once.
    @Test func protocolExtensionBlockTrailsItsProtocol() async throws {
        let builder = try makeBuilder()
        try await builder.prepare()
        let output = try await builder.printRoot().string

        let extensionHeader = "extension SymbolTestsCore.DefaultImplementationVariants.BasicDefaultProtocol {"
        #expect(output.components(separatedBy: extensionHeader).count - 1 == 1)

        // Trailing placement: the block renders after the protocol
        // declaration, inside the protocols region — i.e. before the
        // extensions block that used to host it, which is where the
        // conformance extensions (rendered with `extension X: P` headers)
        // start.
        let protocolRange = try #require(output.range(of: "protocol BasicDefaultProtocol"))
        let extensionRange = try #require(output.range(of: extensionHeader))
        #expect(protocolRange.lowerBound < extensionRange.lowerBound)

        // The attached definitions are flagged and excluded from the
        // top-level extensions block.
        let attachedDefinitions = builder.indexer.protocolExtensionDefinitions.values.flatMap { $0 }.filter(\.isAttachedToProtocolDefinition)
        #expect(!attachedDefinitions.isEmpty)
    }

    /// Same-identity merge: the nested-type discovery and the member-symbol
    /// scan both file signature-less blocks under one extension name; they
    /// must end up in a single `ExtensionDefinition` (and therefore a single
    /// printed block).
    @Test func sameIdentityContainersMergeWithinBuckets() async throws {
        let builder = try makeBuilder()
        try await builder.prepare()
        _ = try await builder.printRoot()

        for (extensionName, definitions) in builder.indexer.typeExtensionDefinitions {
            var seenIdentities: Set<String> = []
            for definition in definitions where definition.protocolConformanceDescriptor == nil {
                let signatureText = await definition.genericSignature?.print(using: .default) ?? "-"
                let protocolText = definition.conformingProtocolName?.name ?? "-"
                let identity = "\(protocolText)|\(signatureText)|\(definition.isRetroactive)"
                #expect(seenIdentities.insert(identity).inserted, "duplicate container identity \(identity) under \(extensionName.name)")
            }
        }
    }

    /// `updateConfiguration(_:)` round trip re-prepares for real (the
    /// `isPrepared` guard used to make it a silent no-op) and the bucket
    /// reset keeps the re-run from duplicating every appended extension
    /// block.
    @Test func configurationRoundTripDoesNotDuplicateExtensionBuckets() async throws {
        let builder = try makeBuilder()
        try await builder.prepare()

        func bucketCounts() -> [Int] {
            [
                builder.indexer.typeExtensionDefinitions.values.map(\.count).reduce(0, +),
                builder.indexer.protocolExtensionDefinitions.values.map(\.count).reduce(0, +),
                builder.indexer.typeAliasExtensionDefinitions.values.map(\.count).reduce(0, +),
                builder.indexer.conformanceExtensionDefinitions.values.map(\.count).reduce(0, +),
            ]
        }

        let initialCounts = bucketCounts()
        #expect(initialCounts.contains { $0 > 0 })

        try await builder.indexer.updateConfiguration(.init(showCImportedTypes: true))
        try await builder.indexer.updateConfiguration(.init(showCImportedTypes: false))

        #expect(bucketCounts() == initialCounts)
    }
}
