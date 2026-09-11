import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftDeclarationRendering
import Demangling
@_spi(Internals) import SwiftInspection
@_spi(Internals) import MachOSymbols

/// A declaration may produce more than one opaque type — `-> Pair<some P, some P>`
/// is two — and the demangled `opaqueType` node says which one it is in its
/// second child, the **ordinal**. The opaque type descriptor's underlying-type
/// array is indexed by exactly that ordinal.
///
/// The rewriter used to read element 0 unconditionally, so every `some` of such
/// a declaration rendered as its first one. Nothing raised and nothing looked
/// degraded: the output was a real, fully-qualified, wrong type.
///
/// Pinned against a compiled fixture rather than a system framework because
/// SwiftUI and SwiftUICore have no such shape — every opaque reference in their
/// associated-type records carries ordinal 0, which is precisely why the defect
/// survived a full dump of both.
@Suite
struct OpaqueTypeOrdinalTests {
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

    /// `Anchor` keeps a `__DATA` segment in the dylib (see AGENTS.md,
    /// "On-the-fly-compiled fixture dylibs need a class").
    ///
    /// `makeOpaquePair` is the whole point: ONE declaration, TWO `some`
    /// results, with deliberately different underlying types so an
    /// ordinal-blind read is visible rather than coincidentally right.
    private static let fixtureSource = """
    public final class Anchor {}

    public protocol ProbeView {
        associatedtype Body: ProbeView
        var body: Body { get }
    }

    public struct ProbeNever: ProbeView {
        public var body: ProbeNever { fatalError() }
    }

    public struct ProbeLeafA: ProbeView {
        public init() {}
        public var body: ProbeNever { fatalError() }
    }

    public struct ProbeLeafB: ProbeView {
        public init() {}
        public var body: ProbeNever { fatalError() }
    }

    public struct ProbePair<First: ProbeView, Second: ProbeView>: ProbeView {
        public var first: First
        public var second: Second
        public init(first: First, second: Second) {
            self.first = first
            self.second = second
        }
        public var body: ProbeNever { fatalError() }
    }

    public func makeOpaquePair() -> ProbePair<some ProbeView, some ProbeView> {
        ProbePair(first: ProbeLeafA(), second: ProbeLeafB())
    }
    """

    private static let fixtureCompilationResult: Result<URL, Swift.Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("OpaqueTypeOrdinalFixture-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            _ = FixtureWorkingDirectoryCleanup.registration
            FixtureWorkingDirectoryCleanup.directories.append(workingDirectory)

            let sourceURL = workingDirectory.appendingPathComponent("OpaqueTypeOrdinalFixture.swift")
            let libraryURL = workingDirectory.appendingPathComponent("libOpaqueTypeOrdinalFixture.dylib")
            try fixtureSource.write(to: sourceURL, atomically: true, encoding: .utf8)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = [
                "swiftc", "-emit-library", "-module-name", "OpaqueTypeOrdinalFixture",
                "-target", "arm64-apple-macosx15.0",
                sourceURL.path, "-o", libraryURL.path,
            ]
            let standardErrorPipe = Pipe()
            process.standardError = standardErrorPipe
            try process.run()
            // Drain BEFORE waitUntilExit — see LegacyDyldInfoBindTests.
            let diagnosticsData = standardErrorPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw FixtureCompilationError(diagnostics: String(decoding: diagnosticsData, as: UTF8.self))
            }
            return libraryURL
        }
    }()

    private struct FixtureCompilationError: Swift.Error, CustomStringConvertible {
        let diagnostics: String
        var description: String { "opaque-type-ordinal fixture compilation failed:\n\(diagnostics)" }
    }

    private func loadFixtureMachOFile() throws -> MachOFile {
        let libraryURL = try Self.fixtureCompilationResult.get()
        switch try MachOKit.loadFromFile(url: libraryURL) {
        case .machO(let machOFile):
            return machOFile
        case .fat(let fatFile):
            let machOFile = try fatFile.machOFiles().first { $0.header.cpuType == .arm64 }
            return try #require(machOFile, "fixture unexpectedly missing an arm64 slice")
        }
    }

    /// `…QOMQ` is the opaque type descriptor's own symbol; `makeOpaquePair`'s
    /// mangles its two results as `Qr` and `QR_`, which is what makes it the
    /// two-ordinal fixture.
    private func opaqueTypeDescriptorOffset(in machOFile: MachOFile) throws -> Int {
        let symbols = SymbolIndexStore.shared.symbols(of: .opaqueTypeDescriptor, in: machOFile)
        // Taken as the only one rather than matched by name: `makeOpaquePair`
        // is not a substring of its own symbol, because the mangler
        // substitutes the repeated module prefix and spells it `04makeA4Pair`.
        // The fixture declares exactly one opaque-producing declaration, and
        // the count assertion is what keeps that true if it ever gains another.
        #expect(
            symbols.count == 1,
            Comment(rawValue: "the fixture must declare exactly one opaque-producing declaration, found \(symbols.map(\.name))")
        )
        return try #require(symbols.first, "the fixture carries no opaque type descriptor symbol").offset
    }

    /// The layout the ordinal indexes into: every replacement type first, then
    /// the conformances — the order IRGen writes the underlying substitution
    /// map in and the order the runtime's `_getOpaqueTypeMetadata` reads back.
    @MainActor
    @Test func underlyingTypeArgumentsAreOrderedTypesFirstThenConformances() async throws {
        let machOFile = try loadFixtureMachOFile()
        let descriptor = try OpaqueTypeDescriptor.resolve(from: opaqueTypeDescriptorOffset(in: machOFile), in: machOFile)
        let opaqueType = try OpaqueType(descriptor: descriptor, in: machOFile)

        #expect(
            descriptor.numUnderlyingTypeArugments == 4,
            "two opaque results with one conformance each: \(descriptor.numUnderlyingTypeArugments)"
        )

        var rendered: [String] = []
        for mangledName in opaqueType.underlyingTypeArgumentMangledNames {
            let node = try SymbolicDemangler.demangleType(for: mangledName, in: machOFile)
            rendered.append(await node.print(using: DemangleOptions.default))
        }

        #expect(rendered.count >= 2, "expected at least the two underlying types, got \(rendered)")
        #expect(
            rendered[0] == "OpaqueTypeOrdinalFixture.ProbeLeafA",
            "ordinal 0's underlying type must be the FIRST `some` result, got \(rendered[0])"
        )
        #expect(
            rendered[1] == "OpaqueTypeOrdinalFixture.ProbeLeafB",
            "ordinal 1's underlying type must be the SECOND `some` result, got \(rendered[1])"
        )
        #expect(
            rendered[0] != rendered[1],
            "the fixture must keep the two results distinguishable, else an ordinal-blind read passes by luck"
        )
    }

    /// The end-to-end consequence: resolving the opaque type at ordinal 1 must
    /// yield the second result. Driven through `resolveOpaqueType(in:)` on a
    /// hand-built node, because the compiler substitutes the underlying types
    /// straight into its own reflection records — a fixture cannot produce an
    /// associated-type record that still references the descriptor.
    @MainActor
    @Test func resolvingByOrdinalYieldsThatOrdinalsUnderlyingType() async throws {
        let machOFile = try loadFixtureMachOFile()
        let descriptorOffset = try opaqueTypeDescriptorOffset(in: machOFile)

        func resolvedOpaqueType(ordinal: UInt64) async throws -> String {
            let opaqueTypeNode = Node.create(
                kind: .type,
                children: [
                    Node.create(
                        kind: .opaqueType,
                        children: [
                            Node.create(kind: .opaqueTypeDescriptorSymbolicReference, index: UInt64(descriptorOffset)),
                            Node.create(kind: .index, index: ordinal),
                            Node.create(kind: .typeList, children: []),
                        ]
                    ),
                ]
            )
            return await (try opaqueTypeNode.resolveOpaqueType(in: machOFile)).print(using: DemangleOptions.default)
        }

        #expect(try await resolvedOpaqueType(ordinal: 0) == "OpaqueTypeOrdinalFixture.ProbeLeafA")
        #expect(
            try await resolvedOpaqueType(ordinal: 1) == "OpaqueTypeOrdinalFixture.ProbeLeafB",
            "ordinal 1 resolving to ProbeLeafA is the defect: the array is read at 0 regardless of the ordinal"
        )
    }
}
