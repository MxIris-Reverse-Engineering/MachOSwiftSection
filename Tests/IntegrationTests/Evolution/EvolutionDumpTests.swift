import Foundation
import Testing
import MachOKit
import SwiftSectionFixtureSupport
import SwiftSectionTestingSupport
@testable import MachOSwiftSection
import SwiftDeclarationRendering
@_spi(Support) @testable import SwiftInterface
@_spi(Support) @testable import SwiftIndexing
import SwiftDiffing
import ObjCMetadataSource
import ObjCIndexing
import ObjCInterface
import ObjCDiffing
import Semantic

/// The four evolution outputs `swift-section` produces, each the pipeline of
/// one subcommand.
enum EvolutionDumpKind: Sendable {
    /// `swift-section evolution`: the lineage report (`-Evolution.txt`) and
    /// its machine-readable form (`-Evolution.json`).
    case swiftReport
    /// `swift-section evolution --interface`: the union interface with
    /// lifecycle annotations (`-EvolutionInterface.swiftinterface`).
    case swiftInterface
    /// `swift-section objc evolution`: the lineage report
    /// (`-ObjCEvolution.txt`) and its JSON (`-ObjCEvolution.json`).
    case objcReport
    /// `swift-section objc evolution --interface`: the union header with
    /// lifecycle annotations (`-ObjCEvolutionInterface.h`).
    case objcInterface

    var language: EvolutionMetadataLanguage {
        switch self {
        case .swiftReport, .swiftInterface: .swift
        case .objcReport, .objcInterface: .objc
        }
    }
}

/// Where a dump goes: printed for a quick look, or written next to the
/// other dumps for inspection.
enum EvolutionDumpDestination: Sendable {
    case console
    case file
}

/// What one pipeline produced.
struct EvolutionDumpOutput: Sendable {
    /// The file-name suffix, after the build version and the image names.
    let suffix: String
    /// What a maintainer reads: the report, or the annotated interface.
    let text: String
    let textFileExtension: String
    /// The machine-readable form a report also writes; `nil` for an
    /// interface.
    let json: String?
}

/// The evolution dumps: an *ordered series* of versions of one image — or
/// of one group of images per version (evolution proposal
/// `image-group-evolution`) — run through the pipelines of `swift-section
/// evolution` and `swift-section objc evolution`, with and without
/// `--interface`.
///
/// The report pipelines freeze every version into a snapshot document
/// round-tripped through the persisted JSON form, so the codec and the
/// format-version gate run on real-world data. The interface pipelines
/// render the versions merged into one interface, each declaration's
/// lifecycle annotated; read one against the report of the same axis — the
/// annotations are the same lineages.
///
/// A conforming suite supplies the axis each pipeline runs over. Like its
/// siblings this is a maintainer-inspection dump: it prints / writes results
/// without assertions.
protocol EvolutionDumpTests: SwiftInterfaceDumpTests {
    func evolutionAxis(for language: EvolutionMetadataLanguage) -> EvolutionAxis
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension EvolutionDumpTests {
    var indexConfiguration: SwiftDeclarationIndexConfiguration {
        .init(showCImportedTypes: false)
    }

    /// Runs one pipeline over this suite's axis for the pipeline's language,
    /// then prints the text, or writes the text — and a report's JSON —
    /// named after the newest version's images.
    func dump(_ kind: EvolutionDumpKind, to destination: EvolutionDumpDestination) async throws {
        let axis = evolutionAxis(for: kind.language)
        let output: EvolutionDumpOutput
        switch kind {
        case .swiftReport:
            output = try await swiftReport(over: axis)
        case .swiftInterface:
            output = try await swiftInterface(over: axis)
        case .objcReport:
            output = try await objcReport(over: axis)
        case .objcInterface:
            output = try await objcInterface(over: axis)
        }
        switch destination {
        case .console:
            printResult(output.text)
        case .file:
            guard let newestVersion = axis.versions.last else { return }
            try write(output.text, forImageGroup: newestVersion.images, suffix: output.suffix, fileExtension: output.textFileExtension)
            if let json = output.json {
                try write(json, forImageGroup: newestVersion.images, suffix: output.suffix, fileExtension: "json")
            }
        }
    }

    // MARK: - Swift

    /// One image indexed the way `swift-section snapshot` indexes it and
    /// frozen into a labeled snapshot document, round-tripped through the
    /// persisted form: what the evolution consumes is exactly what a saved
    /// baseline would decode to.
    private func swiftSnapshotDocument(of image: EvolutionImage, label: String) async throws -> ABISnapshotDocument {
        let builder = SwiftDiffableInterfaceBuilder(configuration: indexConfiguration, in: image.machOFile)
        try await builder.prepare()
        let document = ABISnapshotDocument(
            provenance: ABIProvenance(
                label: label,
                binaryPath: image.machOFile.imagePath,
                generatorVersion: "IntegrationTests",
                createdAt: Date()
            ),
            snapshot: builder.snapshot()
        )
        return try ABISnapshotDocument.decode(from: document.encoded())
    }

    /// The lineage report and its JSON. The timed step covers indexing every
    /// image of every version — the real cost; the lineage math afterwards
    /// is milliseconds.
    private func swiftReport(over axis: EvolutionAxis) async throws -> EvolutionDumpOutput {
        var documentsByVersion: [[ABISnapshotDocument]] = []
        try await measuringPreparation {
            for version in axis.versions {
                var documents: [ABISnapshotDocument] = []
                for image in version.images {
                    documents.append(try await swiftSnapshotDocument(of: image, label: version.label))
                }
                documentsByVersion.append(documents)
            }
        }
        let evolution: ABIEvolution
        var report: String
        if axis.comparesImageGroups {
            let imageGroups = zip(axis.versions, documentsByVersion).map { version, documents in
                zip(version.images, documents).map { image, document in
                    ABIImageSnapshot(imageName: image.imageName, snapshot: document.snapshot)
                }
            }
            evolution = try ABIEvolutionBuilder().evolution(
                ofImageGroups: imageGroups,
                versions: axis.versions.map { ABIVersionDescriptor(label: $0.label) }
            )
            report = ABIEvolutionReporter().report(evolution)
        } else {
            let documents = documentsByVersion.flatMap { $0 }
            evolution = try ABIEvolutionBuilder().evolution(of: documents)
            report = ABIEvolutionReporter().report(evolution)
            // For a two-version series the lineage events must match the
            // two-sided differ verbatim — print both verdicts so the manual
            // inspection can eyeball the consistency on real-world data.
            if documents.count == 2, let oldDocument = documents.first, let newDocument = documents.last {
                let diff = ABIDiffer().diff(old: oldDocument, new: newDocument)
                report += "\n\nPairwise cross-check — evolution ABI-breaking: \(evolution.hasBreakingChange) · diff ABI-breaking: \(diff.hasBreakingChange)"
            }
        }
        return EvolutionDumpOutput(
            suffix: "Evolution",
            text: report,
            textFileExtension: "txt",
            json: String(decoding: try ABIJSON.encoder().encode(evolution), as: UTF8.self)
        )
    }

    /// The annotated union interface plus the per-axis verdict line, so the
    /// manual inspection can eyeball the CI-gate input next to the
    /// rendering. The timed step covers indexing every version; the lineage
    /// join and rendering afterwards are cheap by comparison.
    private func swiftInterface(over axis: EvolutionAxis) async throws -> EvolutionDumpOutput {
        let labels = axis.versions.map(\.label)
        let availabilityAnnotationPlatform = axis.availabilityPlatform?.swiftSpelling
        let builder: AnySwiftEvolutionInterfaceBuilder
        if axis.comparesImageGroups {
            // Each version's images render as one interface, every
            // declaration through the image that indexed it.
            builder = try AnySwiftEvolutionInterfaceBuilder(
                configuration: indexConfiguration,
                imageGroups: axis.versions.map { version in
                    version.images.map { SwiftEvolutionInterfaceImage(imageName: $0.imageName, machO: $0.machOFile) }
                },
                labels: labels,
                availabilityAnnotationPlatform: availabilityAnnotationPlatform
            )
        } else {
            builder = try AnySwiftEvolutionInterfaceBuilder(
                configuration: indexConfiguration,
                versions: axis.versions.map(\.primaryImage.machOFile),
                labels: labels,
                availabilityAnnotationPlatform: availabilityAnnotationPlatform
            )
        }
        try await measuringPreparation {
            try await builder.prepare()
        }
        var report = try await builder.printAnnotatedInterface().string
        if let evolution = builder.evolution {
            report += "\n\n// ABI-breaking on this axis: \(evolution.hasBreakingChange)"
        }
        return EvolutionDumpOutput(suffix: "EvolutionInterface", text: report, textFileExtension: "swiftinterface", json: nil)
    }

    // MARK: - Objective-C

    /// One image indexed the way `swift-section objc snapshot` indexes it and
    /// frozen into a labeled snapshot document, round-tripped through the
    /// persisted form.
    private func objcSnapshotDocument(of image: EvolutionImage, label: String) async throws -> ObjCAPISnapshotDocument {
        let indexer = try await preparedObjCIndexer(of: image.machOFile)
        let document = ObjCAPISnapshotDocument(
            provenance: ObjCAPIProvenance(
                label: label,
                binaryPath: image.machOFile.imagePath,
                generatorVersion: "IntegrationTests",
                createdAt: Date()
            ),
            snapshot: ObjCAPISnapshotBuilder(indexer: indexer).snapshot()
        )
        return try ObjCAPISnapshotDocument.decode(from: document.encoded())
    }

    /// The lineage report and its JSON, as `swiftReport(over:)` builds the
    /// Swift ones.
    private func objcReport(over axis: EvolutionAxis) async throws -> EvolutionDumpOutput {
        var documentsByVersion: [[ObjCAPISnapshotDocument]] = []
        try await measuringPreparation {
            for version in axis.versions {
                var documents: [ObjCAPISnapshotDocument] = []
                for image in version.images {
                    documents.append(try await objcSnapshotDocument(of: image, label: version.label))
                }
                documentsByVersion.append(documents)
            }
        }
        let evolution: ObjCAPIEvolution
        var report: String
        if axis.comparesImageGroups {
            let imageGroups = zip(axis.versions, documentsByVersion).map { version, documents in
                zip(version.images, documents).map { image, document in
                    ObjCAPIImageSnapshot(imageName: image.imageName, snapshot: document.snapshot)
                }
            }
            evolution = try ObjCAPIEvolutionBuilder().evolution(
                ofImageGroups: imageGroups,
                versions: axis.versions.map { ObjCAPIVersionDescriptor(label: $0.label) }
            )
            report = ObjCAPIEvolutionReporter().report(evolution)
        } else {
            let documents = documentsByVersion.flatMap { $0 }
            evolution = try ObjCAPIEvolutionBuilder().evolution(of: documents)
            report = ObjCAPIEvolutionReporter().report(evolution)
            if documents.count == 2, let oldDocument = documents.first, let newDocument = documents.last {
                let diff = ObjCAPIDiffer().diff(old: oldDocument, new: newDocument)
                report += "\n\nPairwise cross-check — evolution API-breaking: \(evolution.hasBreakingChange) · diff API-breaking: \(diff.hasBreakingChange)"
            }
        }
        return EvolutionDumpOutput(
            suffix: "ObjCEvolution",
            text: report,
            textFileExtension: "txt",
            json: String(decoding: try ObjCAPIJSON.encoder().encode(evolution), as: UTF8.self)
        )
    }

    /// The annotated union header plus the per-axis verdict line. Every
    /// version is indexed the way `objc evolution --interface` indexes it and
    /// handed to the builder, which keeps what it rendered and snapshotted,
    /// never the indexer; a group's images go in together, the primary image
    /// first, so a class that moved between them stays one declaration.
    private func objcInterface(over axis: EvolutionAxis) async throws -> EvolutionDumpOutput {
        var builder = ObjCEvolutionInterfaceBuilder()
        try await measuringPreparation {
            for version in axis.versions {
                let versionDescriptor = ObjCAPIVersionDescriptor(label: version.label)
                if axis.comparesImageGroups {
                    var images: [ObjCEvolutionInterfaceImage<MachOFile>] = []
                    for image in version.images {
                        let indexer = try await preparedObjCIndexer(of: image.machOFile)
                        images.append(ObjCEvolutionInterfaceImage(imageName: image.imageName, indexer: indexer, machO: image.machOFile))
                    }
                    builder.addVersion(images: images, version: versionDescriptor)
                } else {
                    let image = version.primaryImage
                    let indexer = try await preparedObjCIndexer(of: image.machOFile)
                    builder.addVersion(indexer: indexer, machO: image.machOFile, version: versionDescriptor)
                }
            }
        }
        let evolutionInterface = try builder.build(availabilityPlatform: axis.availabilityPlatform?.objcSpelling)
        return EvolutionDumpOutput(
            suffix: "ObjCEvolutionInterface",
            text: evolutionInterface.interface.string + "\n\n// API-breaking on this axis: \(evolutionInterface.evolution.hasBreakingChange)",
            textFileExtension: "h",
            json: nil
        )
    }
}

/// One image indexed the way the `objc` subcommands index it: the Swift
/// classes that keep no class object supplied from Swift metadata.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
private func preparedObjCIndexer(of machO: MachOFile) async throws -> ObjCInterfaceIndexer<MachOFile> {
    let indexer = ObjCInterfaceIndexer(
        machO: machO,
        imagePath: machO.imagePath,
        suppliedClasses: ObjCSuppliedClass.swiftClassesWithoutClassObjects(in: machO)
    )
    try await indexer.prepare()
    return indexer
}
