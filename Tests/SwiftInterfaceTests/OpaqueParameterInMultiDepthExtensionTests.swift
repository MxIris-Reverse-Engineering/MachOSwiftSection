import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
@_spi(Support) @testable import SwiftInterface

/// `SwiftInterfaceBuilderOpaqueTypeProvider` finds an opaque result's
/// constraint at the depth of the opaque parameters, which it counts from the
/// descriptor's parent chain: one depth per ancestor whose generic context
/// adds parameters. An extension of a nested generic type adds two depths at
/// once — `extension Outer.SecondMiddle where A: Hashable` carries `Outer`'s
/// `A` and `SecondMiddle`'s `C` — so the count came out one short, and the
/// constraint on `τ_2_0` lay beyond it. A debug build trapped on the
/// `assertionFailure` that guards that impossible depth; a release build
/// printed a bare `some`. The runtime counts depths through the extended
/// type for exactly this reason (`_gatherGenericParameterCounts`).
///
/// An exit test, because the defect traps.
@Suite(.serialized)
struct OpaqueParameterInMultiDepthExtensionTests {
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
        var description: String { "opaque-parameter extension-depth fixture compilation failed:\n\(diagnostics)" }
    }

    private struct MissingConstraint: Error, CustomStringConvertible {
        let interface: String
        var description: String { "the opaque result did not print its constraint:\n\(interface)" }
    }

    /// The class is ballast: a struct-only fixture dylib has no `__DATA`
    /// segment and MachOKit before 0.52.103 mis-walked its chained-fixup pages.
    private static let source = """
    public final class FixtureAnchor {}

    public struct Outer<A> {
        public struct SecondMiddle<C> {
            public init() {}
        }
    }

    extension Outer.SecondMiddle where A: Hashable {
        public var body: some Sequence { [1] }

        // A generic declaration's signature lives in an anonymous context
        // between the descriptor and the extension: one depth more.
        public func elements<Element>(_ element: Element) -> some Sequence { [element] }
    }
    """

    private static let fixtureCompilationResult: Result<URL, Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("OpaqueParameterExtensionDepthFixture-\(UUID().uuidString)")
            _ = FixtureWorkingDirectoryCleanup.registration
            FixtureWorkingDirectoryCleanup.directories.append(workingDirectory)
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            let sourceURL = workingDirectory.appendingPathComponent("OpaqueParameterExtensionDepth.swift")
            try source.write(to: sourceURL, atomically: true, encoding: .utf8)
            let libraryURL = workingDirectory.appendingPathComponent("libProbeOpaqueExtensionDepth.dylib")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = [
                "swiftc", "-swift-version", "5", "-O", "-emit-library", "-module-name", "ProbeOpaqueExtensionDepth",
                "-target", "arm64-apple-macosx15.0",
                sourceURL.path, "-o", libraryURL.path,
            ]
            let standardErrorPipe = Pipe()
            process.standardError = standardErrorPipe
            try process.run()
            // Drain before waiting, or a long diagnostic deadlocks both sides.
            let diagnosticsData = standardErrorPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw FixtureCompilationError(diagnostics: String(decoding: diagnosticsData, as: UTF8.self))
            }
            return libraryURL
        }
    }()

    /// The fixture's interface with the opaque type provider attached, as
    /// `interface --parse-opaque-return-type` and RuntimeViewer print it; it
    /// throws unless the opaque result names its constraint.
    static func printInterfaceNamingTheOpaqueConstraint() async throws {
        let libraryURL = try fixtureCompilationResult.get()
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
        let interface = try await builder.printRoot().string
        guard interface.contains("var body: some Swift.Sequence {"), interface.contains("func elements<A2>(_: A2) -> some Swift.Sequence") else {
            throw MissingConstraint(interface: interface)
        }
    }

    @Test("opaque results in an extension spanning two depths name their constraints")
    func opaqueResultsInAnExtensionSpanningTwoDepthsNameTheirConstraints() async {
        await #expect(processExitsWith: .success) {
            do {
                try await OpaqueParameterInMultiDepthExtensionTests.printInterfaceNamingTheOpaqueConstraint()
            } catch {
                // An error thrown out of an exit test ends the child on a
                // trap too; exiting keeps a missing constraint apart from the
                // provider's own trap.
                exit(EXIT_FAILURE)
            }
        }
    }
}
