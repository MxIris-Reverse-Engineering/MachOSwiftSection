import Foundation
import MachOKit
import SwiftSectionFixtureSupport
@testable import MachOSwiftSection
@_spi(Support) @testable import SwiftIndexing
import ObjCMetadataSource
import ObjCIndexing
import FoundationToolbox
import SwiftStdlibToolbox

/// Shared scaffolding for the maintainer-inspection dumps: the
/// single-version interfaces (`InterfaceDumpTests`), the two-version diffs
/// (`DiffDumpTests`) and the N-version evolutions (`EvolutionDumpTests`).
///
/// Every dump has the same shape — index the images (timed), run one
/// `swift-section` pipeline over them, then print the result or write it
/// next to the others — so the common machinery lives here once: the output
/// directory, the index configuration every pipeline shares, the
/// `prepare()` timer, the console and file sinks, and the file names that
/// identify the images. Like the dumps themselves, nothing here asserts.
protocol InspectionDumpTests {}

/// The metadata a pipeline reads: an image without it has nothing to index,
/// and indexing it anyway only logs extraction failures.
enum MetadataLanguage: Sendable {
    /// `__swift5_*` sections. AppKit kept its Swift API in
    /// `libswiftAppKit.dylib` until macOS 14, so a Swift axis of AppKit
    /// reaching further back starts at 14.0.
    case swift
    /// `__objc_*` sections, which AppKit carries in every cache.
    case objc

    func isCarried(by machOFile: MachOFile) -> Bool {
        let sectionNamePrefix = switch self {
        case .swift: "__swift5_"
        case .objc: "__objc_"
        }
        return machOFile.sections.contains(where: { $0.sectionName.hasPrefix(sectionNamePrefix) })
    }
}

/// Where a dump goes: printed for a quick look, or written next to the
/// other dumps for inspection.
enum DumpDestination: Sendable {
    case console
    case file
}

/// One file a dump writes, named
/// `<build version>-<image names>-<suffix>.<fileExtension>`.
struct DumpFile: Sendable {
    let suffix: String
    let fileExtension: String
    let text: String
}

/// What one pipeline produced: the text the console destination prints,
/// and the files the file destination writes.
struct DumpOutput: Sendable {
    let consoleText: String
    let files: [DumpFile]
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension InspectionDumpTests {
    /// The directory every dump is written under, shared so the interface,
    /// diff and evolution artifacts of the same binary co-locate for manual
    /// inspection.
    var rootDirectory: URL {
        .documentsDirectory.appending(path: "SwiftInterfaceTests")
    }

    /// How every pipeline indexes Swift metadata.
    var indexConfiguration: SwiftDeclarationIndexConfiguration {
        .init(showCImportedTypes: false)
    }

    /// Runs `prepare`, prints how long it took (unless running silently) and
    /// returns what it prepared. Callers pass the whole preparation step —
    /// for a diff that means preparing *both* binaries — so the printed
    /// duration covers the real work.
    func measuringPreparation<Prepared>(_ prepare: () async throws -> Prepared) async rethrows -> Prepared {
        let clock = ContinuousClock()
        let start = clock.now
        let prepared = try await prepare()
        #if !SILENT_TEST
        print(clock.now - start)
        #endif
        return prepared
    }

    /// Prints a rendered dump to the console, unless running silently.
    func printResult(_ string: String) {
        #if !SILENT_TEST
        print(string)
        #endif
    }

    /// Prints `output`'s console text, or hands each of its files to
    /// `writeFile`, which names it after the images the dump read.
    func deliver(_ output: DumpOutput, to destination: DumpDestination, writingFile writeFile: (DumpFile) throws -> Void) rethrows {
        switch destination {
        case .console:
            printResult(output.consoleText)
        case .file:
            for file in output.files {
                try writeFile(file)
            }
        }
    }

    /// Writes a rendered dump into `rootDirectory` under a name that identifies
    /// the binary by its build version and file name, so repeated runs overwrite
    /// in place and different binaries never collide.
    func write(
        _ string: String,
        for machO: some MachOSwiftSectionRepresentableWithCache,
        suffix: String,
        fileExtension: String = "swiftinterface"
    ) throws {
        try rootDirectory.createDirectoryIfNeeded()
        let fileName = "\(machO.loadCommands.buildVersionCommand!)-\(machO.imagePath.lastPathComponent)-\(suffix).\(fileExtension)"
        try string.write(to: rootDirectory.appending(path: fileName), atomically: true, encoding: .utf8)
    }

    /// `write(_:for:suffix:fileExtension:)` for one version of a version
    /// axis, which may be a group of images (evolution proposal
    /// `image-group-evolution`): named after the primary image's build
    /// version and every image of the version, joined by `+`
    /// (`…-SwiftUI+SwiftUICore-Evolution.txt`). A version of one image gets
    /// the name `write(_:for:…)` gives it.
    func write(
        _ string: String,
        forImageGroup images: [AxisImage],
        suffix: String,
        fileExtension: String = "swiftinterface"
    ) throws {
        guard let primaryImage = images.first else { return }
        try rootDirectory.createDirectoryIfNeeded()
        let imageGroupName = images.map { $0.machOFile.imagePath.lastPathComponent }.joined(separator: "+")
        let fileName = "\(primaryImage.machOFile.loadCommands.buildVersionCommand!)-\(imageGroupName)-\(suffix).\(fileExtension)"
        try string.write(to: rootDirectory.appending(path: fileName), atomically: true, encoding: .utf8)
    }
}

/// One image indexed the way the `objc` subcommands index it: the Swift
/// classes that keep no class object supplied from Swift metadata.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
func preparedObjCIndexer<MachO: ObjCMetadataSource & MachORepresentableWithCache>(of machO: MachO) async throws -> ObjCInterfaceIndexer<MachO> {
    let indexer = ObjCInterfaceIndexer(
        machO: machO,
        imagePath: machO.imagePath,
        suppliedClasses: ObjCSuppliedClass.swiftClassesWithoutClassObjects(in: machO)
    )
    try await indexer.prepare()
    return indexer
}

extension BuildVersionCommand: @retroactive CustomStringConvertible {
    public var description: String {
        "\(platform.stringValue)-\(sdk)"
    }
}

extension MachOKit.Platform {
    var stringValue: String {
        switch self {
        case .unknown:
            "Unknown"
        case .any:
            "Any"
        case .macOS:
            "macOS"
        case .iOS:
            "iOS"
        case .tvOS:
            "tvOS"
        case .watchOS:
            "watchOS"
        case .bridgeOS:
            "bridgeOS"
        case .macCatalyst:
            "macCatalyst"
        case .iOSSimulator:
            "iOSSimulator"
        case .tvOSSimulator:
            "tvOSSimulator"
        case .watchOSSimulator:
            "watchOSSimulator"
        case .driverKit:
            "DriverKit"
        case .visionOS:
            "visionOS"
        case .visionOSSimulator:
            "visionOSSimulator"
        case .firmware:
            "Firmware"
        case .sepOS:
            "sepOS"
        case .macOSExclaveCore:
            "macOSExclaveCore"
        case .macOSExclaveKit:
            "macOSExclaveKit"
        case .iOSExclaveCore:
            "iOSExclaveCore"
        case .iOSExclaveKit:
            "iOSExclaveKit"
        case .tvOSExclaveCore:
            "tvOSExclaveCore"
        case .tvOSExclaveKit:
            "tvOSExclaveKit"
        case .watchOSExclaveCore:
            "watchOSExclaveCore"
        case .watchOSExclaveKit:
            "watchOSExclaveKit"
        case .visionOSExclaveCore:
            "visionOSExclaveCore"
        case .visionOSExclaveKit:
            "visionOSExclaveKit"
        }
    }
}
