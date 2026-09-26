import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
import Demangling
@_spi(Internals) import SwiftInspection
import SwiftDeclarationRendering
@testable import SwiftThunkAnalysis

/// A kind-9 field thunk that calls a **compiler-merged accessor** — the
/// shape SwiftUICore's `PlatformAccessibilitySettingsDefinition.cache` and
/// `NamedImage.Cache.data` have, reproduced with the current toolchain.
///
/// The compiler folds every "probe this cache, else call this accessor with
/// this argument" body into one function (`…MaTm`) whose parameters are the
/// cache slot, the argument and the accessor, so the merged body carries no
/// type of its own and its symbol names just one of the bodies folded into
/// it. It is emitted here by turning off the mangled-name instantiation the
/// toolchain otherwise prefers for a concrete `Mutex<…>`
/// (`-disable-concrete-type-metadata-mangled-name-accessors`), which makes
/// three same-shaped lazy accessors, which the optimizer merges. Reading the
/// fields means following the call into the merged body with the caller's
/// registers, so a copy with its local symbols stripped must read the same.
///
/// Measured before the evaluator followed calls: all three fields were
/// `accessor function at N`, with and without symbols.
@Suite(.serialized)
struct MergedAccessorFixtureTests {
    private enum FixtureWorkingDirectoryCleanup {
        nonisolated(unsafe) static var directories: [URL] = []
        static let registration: Void = {
            atexit {
                for directory in FixtureWorkingDirectoryCleanup.directories {
                    try? FileManager.default.removeItem(at: directory)
                }
            }
        }()
    }

    private struct FixtureCompilationError: Error, CustomStringConvertible {
        let diagnostics: String
        var description: String { "MergedAccessorProbe fixture compilation failed:\n\(diagnostics)" }
    }

    private struct CompiledFixture {
        let libraryURL: URL
        let strippedLibraryURL: URL
    }

    private static let fixtureCompilationResult: Result<CompiledFixture, Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("MergedAccessorProbeFixture-\(UUID().uuidString)")
            _ = FixtureWorkingDirectoryCleanup.registration
            FixtureWorkingDirectoryCleanup.directories.append(workingDirectory)
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            let sourceURL = workingDirectory.appendingPathComponent("MergedAccessorProbe.swift")
            try fixtureSource.write(to: sourceURL, atomically: true, encoding: .utf8)
            let libraryURL = workingDirectory.appendingPathComponent("libMergedAccessorProbe.dylib")
            let strippedLibraryURL = workingDirectory.appendingPathComponent("libMergedAccessorProbeStripped.dylib")

            // `Synchronization.Mutex` needs macOS 15; optimized so the
            // accessors take the shapes a shipping binary carries and the
            // optimizer merges them.
            try run(tool: "swiftc", arguments: [
                "-O", "-emit-library", "-module-name", "MergedAccessorProbe",
                "-target", "arm64-apple-macosx15.0",
                "-Xfrontend", "-disable-concrete-type-metadata-mangled-name-accessors",
                sourceURL.path, "-o", libraryURL.path,
            ])
            try FileManager.default.copyItem(at: libraryURL, to: strippedLibraryURL)
            // `-x` removes the local symbols — every `…MaTm` and specialized
            // accessor name — the way a shipping app is stripped.
            try run(tool: "strip", arguments: ["-x", strippedLibraryURL.path])
            return CompiledFixture(libraryURL: libraryURL, strippedLibraryURL: strippedLibraryURL)
        }
    }()

    private static func run(tool: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [tool] + arguments
        let standardErrorPipe = Pipe()
        process.standardError = standardErrorPipe
        try process.run()
        // Drain before waiting, or a long diagnostic deadlocks both sides.
        let diagnosticsData = standardErrorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw FixtureCompilationError(diagnostics: String(decoding: diagnosticsData, as: UTF8.self))
        }
    }

    /// Three holders whose `Mutex<…>` accessors differ only in their
    /// constants, so the optimizer merges the bodies. The class is
    /// deliberate: a struct-only fixture dylib has no `__DATA` segment and
    /// MachOKit before 0.52.103 mis-walked its chained-fixup pages.
    private static let fixtureSource = """
    import Foundation
    import Synchronization

    public final class ProbeAnchor {}

    struct FirstStorage { var count: Int = 0 }
    struct SecondStorage { var name: String = "" }
    struct ThirdStorage { var values: [Int] = [] }

    public struct FirstHolder: ~Copyable {
        let cache: Mutex<FirstStorage>
        public init() { cache = Mutex(FirstStorage()) }
    }

    public struct SecondHolder: ~Copyable {
        let data: Mutex<SecondStorage>
        public init() { data = Mutex(SecondStorage()) }
    }

    public struct ThirdHolder: ~Copyable {
        let data: Mutex<ThirdStorage>
        public init() { data = Mutex(ThirdStorage()) }
    }
    """

    private func load(_ libraryURL: URL) throws -> MachOFile {
        switch try File.loadFromFile(url: libraryURL) {
        case .machO(let machOFile):
            return machOFile
        case .fat(let fatFile):
            return try #require(try fatFile.machOFiles().first { $0.header.cpuType == .arm64 })
        }
    }

    /// Every kind-9 field of the fixture, keyed `Owner.field`, resolved
    /// through the same entry the dump and interface paths use.
    private func resolvedFieldTexts(in machOFile: MachOFile) throws -> [String: String] {
        var texts: [String: String] = [:]
        for wrapper in try machOFile.swift.typeContextDescriptors {
            let descriptor = wrapper.typeContextDescriptor
            guard let fieldDescriptor = try? descriptor.fieldDescriptor(in: machOFile) else { continue }
            let ownerLayout = AccessorThunkOwnerLayout(genericContext: try descriptor.genericContext(in: machOFile))
            let ownerName = try SymbolicDemangler.demangleContext(for: wrapper.asContextDescriptorWrapper, in: machOFile).print(using: .default)
            for record in try fieldDescriptor.records(in: machOFile) {
                guard let mangledTypeName = try? record.mangledTypeName(in: machOFile),
                      let typeNode = try? SymbolicDemangler.demangleType(for: mangledTypeName, in: machOFile),
                      typeNode.contains(Node.Kind.accessorFunctionReference)
                else { continue }
                let resolvedNode = typeNode.resolvingAccessorFunctionReferences(in: machOFile, ownerLayout: ownerLayout)
                texts["\(ownerName).\(try record.fieldName(in: machOFile))"] = resolvedNode.print(using: .default)
            }
        }
        return texts
    }

    private static let expectedFieldTexts: [String: String] = [
        "MergedAccessorProbe.FirstHolder.cache": "Synchronization.Mutex<MergedAccessorProbe.FirstStorage>",
        "MergedAccessorProbe.SecondHolder.data": "Synchronization.Mutex<MergedAccessorProbe.SecondStorage>",
        "MergedAccessorProbe.ThirdHolder.data": "Synchronization.Mutex<MergedAccessorProbe.ThirdStorage>",
    ]

    /// The fixture really has the shape: a merged accessor symbol, which the
    /// symbol-naming route must keep refusing — the answer has to come from
    /// following the call, not from this name.
    @Test func theFixtureCarriesAMergedAccessor() throws {
        let machOFile = try load(try Self.fixtureCompilationResult.get().libraryURL)
        let mergedAccessorNames = (machOFile.symbols64?.map(\.name) ?? []).filter { $0.hasSuffix("MaTm") }
        #expect(!mergedAccessorNames.isEmpty, "the toolchain no longer merges the fixture's accessors; the fixture needs a new shape")
        for name in mergedAccessorNames {
            #expect(!MachOThunkEnvironment.isConcreteTypeAccessorSymbol(try demangleAsNodeTransient(name)), "\(name)")
        }
    }

    @Test func theFieldsAreReadThroughTheMergedBody() throws {
        let machOFile = try load(try Self.fixtureCompilationResult.get().libraryURL)
        let texts = try resolvedFieldTexts(in: machOFile)
        #expect(texts == Self.expectedFieldTexts)
    }

    /// With every local symbol stripped there is nothing to name the merged
    /// body or the accessors by; following the call does not need a name.
    @Test func theFieldsAreReadWithoutLocalSymbolsToo() throws {
        let machOFile = try load(try Self.fixtureCompilationResult.get().strippedLibraryURL)
        #expect((machOFile.symbols64?.map(\.name) ?? []).allSatisfy { !$0.hasSuffix("MaTm") })
        let texts = try resolvedFieldTexts(in: machOFile)
        #expect(texts == Self.expectedFieldTexts)
    }
}
