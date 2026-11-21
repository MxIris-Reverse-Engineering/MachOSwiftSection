import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
import Demangling
@_spi(Internals) import SwiftInspection
import SwiftDeclarationRendering
import SwiftSectionFixtureSupport
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
    private struct StripError: Error, CustomStringConvertible {
        let diagnostics: String
        var description: String { "stripping the MergedAccessorProbe fixture failed:\n\(diagnostics)" }
    }

    private struct CompiledFixture {
        let libraryURL: URL
        let strippedLibraryURL: URL
    }

    private static let fixtureCompilationResult: Result<CompiledFixture, any Error> = {
        Result {
            // `Synchronization.Mutex` needs macOS 15; optimized so the
            // accessors take the shapes a shipping binary carries and the
            // optimizer merges them.
            let libraryURL = try FixtureCompiler.shared.dynamicLibrary(
                named: "MergedAccessorProbe",
                language: .swift,
                source: fixtureSource,
                arguments: [
                    "-O",
                    "-target", "arm64-apple-macosx15.0",
                    "-Xfrontend", "-disable-concrete-type-metadata-mangled-name-accessors",
                ]
            )
            // The compiled library is shared with every other request for it,
            // so the stripped variant is a copy in a directory of its own,
            // under the compiler's products directory the process removes at
            // exit.
            let strippedDirectory = FixtureCompiler.shared.productsDirectory
                .appendingPathComponent("MergedAccessorProbeStripped-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: strippedDirectory, withIntermediateDirectories: true)
            let strippedLibraryURL = strippedDirectory.appendingPathComponent("libMergedAccessorProbeStripped.dylib")
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
            throw StripError(diagnostics: String(decoding: diagnosticsData, as: UTF8.self))
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
        try HostSlice.machOFile(at: libraryURL)
    }

    /// Every kind-9 field of the fixture, keyed `Owner.field`, resolved
    /// through the same entry the dump and interface paths use.
    private func resolvedFieldTexts(in machOFile: MachOFile) throws -> [String: String] {
        var texts: [String: String] = [:]
        for wrapper in try machOFile.swift.typeContextDescriptors {
            let descriptor = wrapper.typeContextDescriptor
            guard let fieldDescriptor = try? descriptor.fieldDescriptor(in: machOFile.context) else { continue }
            let ownerLayout = AccessorThunkOwnerLayout(genericContext: try descriptor.genericContext(in: machOFile.context))
            let ownerName = try SymbolicDemangler.demangleContext(for: wrapper.asContextDescriptorWrapper, in: machOFile.context).print(using: .default)
            for record in try fieldDescriptor.records(in: machOFile.context) {
                guard let mangledTypeName = try? record.mangledTypeName(in: machOFile.context),
                      let typeNode = try? SymbolicDemangler.demangleType(for: mangledTypeName, in: machOFile.context),
                      typeNode.contains(Node.Kind.accessorFunctionReference)
                else { continue }
                let resolvedNode = typeNode.resolvingAccessorFunctionReferences(in: machOFile, ownerLayout: ownerLayout)
                texts["\(ownerName).\(try record.fieldName(in: machOFile.context))"] = resolvedNode.print(using: .default)
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
