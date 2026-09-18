import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
@_spi(Support) @testable import SwiftInterface

/// An opaque parameter that carries no runtime-visible protocol requirement.
///
/// `some Sendable` is the shape that crashed RuntimeViewer on macOS 26.7's
/// `PhotosUIFoundation.PhotosGroupingItemListManager.GroupItem.value`
/// (2026-09-18): marker protocols are never recorded in generic requirements
/// (`GenMeta.cpp`, "Marker protocols do not record generic requirements at
/// all"), so the opaque type descriptor declares the parameter and nothing
/// about it. `SwiftInterfaceBuilderOpaqueTypeProvider` grouped the protocol
/// requirements per parameter and picked the group *positionally* —
/// `elements[0]`, or `elements[index + 1]` for the second `some` of a tuple —
/// and an empty or short list trapped with `Index out of range`, taking the
/// whole process down. `some Any` and `some AnyObject` (a layout requirement,
/// which the provider does not read) reach the same state.
///
/// The provider now looks the parameter up by its coordinate in the generic
/// signature and answers nil when nothing constrains it, so the printer emits
/// a bare `some` — the same honest degradation the file reader already
/// produced for a requirement it could not read. The generic-type cases pin
/// the coordinate arithmetic: every enclosing depth the descriptor inherits
/// plus one for a generic member's own parameters.
@Suite(.serialized)
struct OpaqueParameterWithoutProtocolRequirementTests {
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
        var description: String { "opaque-parameter fixture compilation failed:\n\(diagnostics)" }
    }

    private static let fixtureCompilationResult: Result<URL, Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("OpaqueParameterFixture-\(UUID().uuidString)")
            _ = FixtureWorkingDirectoryCleanup.registration
            FixtureWorkingDirectoryCleanup.directories.append(workingDirectory)
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            let sourceURL = workingDirectory.appendingPathComponent("OpaqueParameters.swift")
            try source.write(to: sourceURL, atomically: true, encoding: .utf8)
            let libraryURL = workingDirectory.appendingPathComponent("libProbeOpaqueParameter.dylib")
            try run(swiftcArguments: [
                "-O", "-emit-library", "-module-name", "ProbeOpaqueParameter",
                "-target", "arm64-apple-macosx15.0",
                sourceURL.path, "-o", libraryURL.path,
            ])
            return libraryURL
        }
    }()

    private static func run(swiftcArguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["swiftc"] + swiftcArguments
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

    /// The class is ballast: a struct-only fixture dylib has no `__DATA`
    /// segment and the pinned MachOKit mis-walks its chained-fixup pages.
    private static let source = """
    public final class FixtureAnchor {}

    public struct Holder {
        public init() {}
        public var markerOnly: some Sendable { 1 }
        public func pair() -> (some Equatable, some Sendable) { (1, "x") }
        public func object() -> some AnyObject { FixtureAnchor() }
        public var unconstrained: some Any { 1 }
    }

    public struct Outer<Element> {
        public init() {}
        public var plain: some Equatable { 1 }
        public func generic<Argument>(_ argument: Argument) -> some Equatable { 1 }
        public struct Inner {
            public init() {}
            public var nested: some Equatable { 1 }
        }
    }
    """

    private func renderInterface() async throws -> String {
        let libraryURL = try Self.fixtureCompilationResult.get()
        let machOFile: MachOFile
        switch try File.loadFromFile(url: libraryURL) {
        case .machO(let file):
            machOFile = file
        case .fat(let fatFile):
            machOFile = try #require(try fatFile.machOFiles().first { $0.header.cpuType == .arm64 })
        }
        let builder = try SwiftInterfaceBuilder(configuration: .init(), eventHandlers: [], in: machOFile)
        builder.addExtraDataProvider(SwiftInterfaceBuilderOpaqueTypeProvider(machO: machOFile))
        try await builder.prepare()
        return try await builder.printRoot().string
    }

    /// The crash shape: the only requirement the descriptor could carry is a
    /// marker protocol, which it does not, so the grouped list is empty.
    @Test func aMarkerOnlyOpaqueParameterRendersAsBareSome() async throws {
        let interface = try await renderInterface()
        #expect(interface.contains("var markerOnly: some {"), "\(interface)")
        #expect(interface.contains("var unconstrained: some {"), "\(interface)")
    }

    /// The `QR0` shape: the first parameter has a requirement, the second has
    /// none, so the grouped list is one short of the ordinal.
    @Test func theSecondOpaqueParameterOfATupleRendersAsBareSome() async throws {
        let interface = try await renderInterface()
        #expect(interface.contains("func pair() -> (some Swift.Equatable, some)"), "\(interface)")
    }

    /// A class-layout requirement is not a protocol requirement either.
    @Test func aLayoutOnlyOpaqueParameterRendersAsBareSome() async throws {
        let interface = try await renderInterface()
        #expect(interface.contains("func object() -> some\n"), "\(interface)")
    }

    /// The coordinate arithmetic: a member of a generic type inherits one
    /// depth, a generic member adds one of its own, and a non-generic nested
    /// type adds none.
    @Test func opaqueParametersOfGenericTypesResolveAtTheirOwnDepth() async throws {
        let interface = try await renderInterface()
        #expect(interface.contains("var plain: some Swift.Equatable {"), "\(interface)")
        #expect(interface.contains("-> some Swift.Equatable\n"), "\(interface)")
        #expect(interface.contains("var nested: some Swift.Equatable {"), "\(interface)")
    }
}
