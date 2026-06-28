import Foundation
import Testing
import SwiftDeclarationRendering
import MachOKit
import MachOExtensions
import MachOFixtureSupport
import MachOTestingSupport
@testable import MachOSwiftSection
@testable import SwiftInterface
@_spi(Support) @testable import SwiftIndexing
import SwiftDiffing

/// The ABI-diff analogue of ``SwiftInterfaceBuilderTests``.
///
/// Where the interface builder tests index *one* binary and render it, these
/// index a *pair* of binaries and run them through the diff pipeline:
/// `ABIDiffer` (the machine-readable change list) and
/// `SwiftDiffableInterfaceRenderer` (the full interface annotated with inline
/// `+`/`-` markers). Like its sibling it is a maintainer-inspection dump — it
/// prints / writes results without assertions.
protocol SwiftDiffableInterfaceBuilderTests: SwiftInterfaceDumpTests {}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension SwiftDiffableInterfaceBuilderTests {
    var indexConfiguration: SwiftDeclarationIndexConfiguration {
        .init(showCImportedTypes: false)
    }

    /// Builds and `prepare()`s both binaries in one timed step — the differ needs
    /// both sides indexed before it can compare them, so the printed duration
    /// covers the whole preparation.
    private func preparedBuilders<Old: FieldLayoutRenderable, New: FieldLayoutRenderable>(
        old: Old,
        new: New,
    ) async throws -> (old: SwiftDiffableInterfaceBuilder<Old>, new: SwiftDiffableInterfaceBuilder<New>) {
        let oldBuilder = SwiftDiffableInterfaceBuilder(configuration: indexConfiguration, in: old)
        let newBuilder = SwiftDiffableInterfaceBuilder(configuration: indexConfiguration, in: new)
        try await measuringPreparation {
            try await oldBuilder.prepare()
            try await newBuilder.prepare()
        }
        return (oldBuilder, newBuilder)
    }

    /// The machine-readable change list plus the one-line compatibility verdict,
    /// mirroring `swift-section diff`'s text report.
    private func changeListReport<Old: FieldLayoutRenderable, New: FieldLayoutRenderable>(
        old: SwiftDiffableInterfaceBuilder<Old>,
        new: SwiftDiffableInterfaceBuilder<New>,
    ) -> String {
        let diff = ABIDiffer().diff(old: old.abiModule(), new: new.abiModule())
        let verdict = "ABI-breaking: \(diff.hasBreakingChange) · backward-compatible: \(diff.isBackwardCompatible)"
        return ABIDiffReporter().report(diff) + "\n\n" + verdict
    }

    /// The full interface annotated with inline `+`/`-` markers, mirroring
    /// `swift-section diff --interface`.
    private func annotatedInterface<Old: FieldLayoutRenderable, New: FieldLayoutRenderable>(
        old: SwiftDiffableInterfaceBuilder<Old>,
        new: SwiftDiffableInterfaceBuilder<New>,
        format: DiffFormat = .inline,
    ) async -> String {
        await SwiftDiffableInterfaceRenderer(old: old, new: new).printAnnotatedInterface(format: format).string
    }

    /// Console analogue of `buildString`: prepares both binaries, then prints the
    /// change list and the annotated interface.
    func diffString<Old: FieldLayoutRenderable, New: FieldLayoutRenderable>(
        old: Old,
        new: New,
    ) async throws {
        let (oldBuilder, newBuilder) = try await preparedBuilders(old: old, new: new)
        printResult(changeListReport(old: oldBuilder, new: newBuilder))
        await printResult(annotatedInterface(old: oldBuilder, new: newBuilder))
    }

    /// File analogue of `buildFile`: writes the change list (`-Diff.txt`) and the
    /// annotated interface (`-AnnotatedInterface.swiftinterface`) next to the
    /// single-binary interface dumps, both named after the *new* binary.
    func diffFile<Old: FieldLayoutRenderable, New: FieldLayoutRenderable>(
        old: Old,
        new: New,
    ) async throws {
        let (oldBuilder, newBuilder) = try await preparedBuilders(old: old, new: new)
        try write(changeListReport(old: oldBuilder, new: newBuilder), for: newBuilder.machO, suffix: "Diff", fileExtension: "txt")
        try await write(annotatedInterface(old: oldBuilder, new: newBuilder, format: .inline), for: newBuilder.machO, suffix: "AnnotatedInterface-Inline")
        try await write(annotatedInterface(old: oldBuilder, new: newBuilder, format: .unified()), for: newBuilder.machO, suffix: "AnnotatedInterface-Unified")
    }
}

/// Selects the preferred-architecture slice from a loaded `File`, mirroring the
/// loading convention of `MachOTestingSupport`'s single-binary base classes.
/// Shared by every cross-version base class below so the fat/thin handling lives
/// in one place.
private func selectMachOFile(from file: File, architecture: CPUType) throws -> MachOFile {
    switch file {
    case .fat(let fatFile):
        return try required(fatFile.machOFiles().first(where: { $0.header.cpuType == architecture }) ?? fatFile.machOFiles().first)
    case .machO(let machO):
        return machO
    @unknown default:
        fatalError()
    }
}

enum SwiftDiffableInterfaceBuilderTestSuite {
    /// Loads a fixed `(old, new)` pair of `MachOFile`s by name — the two-binary
    /// counterpart of `MachOTestingSupport.MachOFileTests`, which only loads one.
    @TestActor
    class CrossVersionMachOFileTests: Sendable {
        let oldMachOFile: MachOFile
        let newMachOFile: MachOFile

        class var oldFileName: MachOFileName { .iOS_18_5_Simulator_SwiftUICore }
        class var newFileName: MachOFileName { .iOS_26_5_Simulator_SwiftUICore }
        class var preferredArchitecture: CPUType { .arm64 }

        init() async throws {
            self.oldMachOFile = try selectMachOFile(from: loadFromFile(named: Self.oldFileName), architecture: Self.preferredArchitecture)
            self.newMachOFile = try selectMachOFile(from: loadFromFile(named: Self.newFileName), architecture: Self.preferredArchitecture)
        }
    }

    /// Extracts the same image from two dyld shared caches — the two-binary,
    /// two-cache counterpart of `MachOTestingSupport.DyldCacheTests`. The caches are
    /// retained because the extracted `MachOFile`s resolve cross-image references
    /// (into Foundation, libswiftCore, …) through them while indexing.
    @TestActor
    class CrossVersionDyldCacheImageTests: Sendable {
        let oldCache: DyldCache
        let newCache: DyldCache
        let oldMachOFileInCache: MachOFile
        let newMachOFileInCache: MachOFile

        class var oldCachePath: DyldSharedCachePath { .macOS_26_5_1 }
        class var newCachePath: DyldSharedCachePath { .macOS_27_0_beta_1 }
        class var cacheImageName: MachOImageName { .AppKit }

        init() async throws {
            let oldCache = try DyldCache(path: Self.oldCachePath)
            let newCache = try DyldCache(path: Self.newCachePath)
            self.oldCache = oldCache
            self.newCache = newCache
            self.oldMachOFileInCache = try #require(oldCache.machOFile(named: Self.cacheImageName))
            self.newMachOFileInCache = try #require(newCache.machOFile(named: Self.cacheImageName))
        }
    }

    /// Loads the same shared framework from two installed Xcode applications. The
    /// shared `XcodeMachOFileName` fixture hardcodes a single Xcode, so this loads
    /// by path directly — the local-loading counterpart that lets the diff compare
    /// two Xcode versions without changing the fixture.
    @TestActor
    class CrossVersionXcodeFrameworkTests: Sendable {
        let oldMachOFile: MachOFile
        let newMachOFile: MachOFile

        class var oldXcodeApplicationPath: String { "/Applications/Xcode-26.3.0.app" }
        class var newXcodeApplicationPath: String { "/Applications/Xcode-26.4.0.app" }
        class var sharedFrameworkName: String { "DVTProductsUI" }
        class var preferredArchitecture: CPUType { .arm64 }

        init() async throws {
            self.oldMachOFile = try Self.loadSharedFramework(inXcodeAt: Self.oldXcodeApplicationPath)
            self.newMachOFile = try Self.loadSharedFramework(inXcodeAt: Self.newXcodeApplicationPath)
        }

        private class func loadSharedFramework(inXcodeAt xcodeApplicationPath: String) throws -> MachOFile {
            let name = sharedFrameworkName
            let binaryPath = "\(xcodeApplicationPath)/Contents/SharedFrameworks/\(name).framework/Versions/A/\(name)"
            return try selectMachOFile(from: File.loadFromFile(url: URL(fileURLWithPath: binaryPath)), architecture: preferredArchitecture)
        }
    }

    /// SwiftUICore across two simulator runtimes (iOS 18.5 → 26.2).
    final class SwiftUICoreTests: CrossVersionMachOFileTests, SwiftDiffableInterfaceBuilderTests, @unchecked Sendable {
        override class var oldFileName: MachOFileName { .iOS_18_5_Simulator_SwiftUICore }
        override class var newFileName: MachOFileName { .iOS_26_5_Simulator_SwiftUICore }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func `diff file`() async throws {
            try await diffFile(old: oldMachOFile, new: newMachOFile)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func `diff string`() async throws {
            try await diffString(old: oldMachOFile, new: newMachOFile)
        }
    }

    /// SwiftUI across two simulator runtimes (iOS 18.5 → 26.2).
    final class SwiftUITests: CrossVersionMachOFileTests, SwiftDiffableInterfaceBuilderTests, @unchecked Sendable {
        override class var oldFileName: MachOFileName { .iOS_18_5_Simulator_SwiftUI }
        override class var newFileName: MachOFileName { .iOS_26_5_Simulator_SwiftUI }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func diffFile() async throws {
            try await diffFile(old: oldMachOFile, new: newMachOFile)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func diffString() async throws {
            try await diffString(old: oldMachOFile, new: newMachOFile)
        }
    }

    /// The same macOS image (SwiftUI) extracted from two dyld shared caches
    /// (macOS 15.5 → current). Cross-image references resolve through each cache.
    final class DyldCacheTests: CrossVersionDyldCacheImageTests, SwiftDiffableInterfaceBuilderTests, @unchecked Sendable {
        override class var oldCachePath: DyldSharedCachePath { .macOS_26_5_1 }
        override class var newCachePath: DyldSharedCachePath { .macOS_27_0_beta_1 }
        override class var cacheImageName: MachOImageName { .AppKit }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func diffFile() async throws {
            try await diffFile(old: oldMachOFileInCache, new: newMachOFileInCache)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func diffString() async throws {
            try await diffString(old: oldMachOFileInCache, new: newMachOFileInCache)
        }
    }

    /// The DVTProductsUI shared framework across two installed Xcode versions
    /// (26.3 → 26.4) — mirrors the framework the interface builder tests use,
    /// loaded by path so the diff can compare two Xcodes.
    final class XcodeFrameworkTests: CrossVersionXcodeFrameworkTests, SwiftDiffableInterfaceBuilderTests, @unchecked Sendable {
        override class var oldXcodeApplicationPath: String { "/Applications/Xcode-26.3.0.app" }
        override class var newXcodeApplicationPath: String { "/Applications/Xcode-26.4.0.app" }
        override class var sharedFrameworkName: String { "DVTProductsUI" }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func diffFile() async throws {
            try await diffFile(old: oldMachOFile, new: newMachOFile)
        }

        @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
        @Test func diffString() async throws {
            try await diffString(old: oldMachOFile, new: newMachOFile)
        }
    }
}
