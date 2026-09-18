import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
@_spi(Support) @testable import SwiftInterface

/// The spelling of an opaque result type's constraints beyond the plain
/// `some Protocol<Argument>` shape the fixture covers.
///
/// The Swift generics book (`docs/Generics/chapters/opaque-result-types.tex`)
/// names two constraint forms for an opaque result type: a conformance
/// requirement, and — when the constraint type is a class — a **superclass**
/// requirement. `SwiftInterfaceBuilderOpaqueTypeProvider` read only the first,
/// so `some Base` rendered as a bare `some` and `some Base & P` as `some P`,
/// silently dropping the class (measured 2026-09-18 on a probe dylib; the
/// fixture has no class-constrained `some`, so no baseline ever moved).
///
/// The other two shapes are the same defect at a different site: the
/// provider printed a primary-associated-type argument through the upstream
/// `NodePrinter` with `.opaqueTypeBuilderOnly`, an option set made for
/// printing a type's *name*. That printer spells out the protocol that
/// qualifies each associated type — `A.Probe.Walkable.Next` for the book's
/// own `some Sequence<T.A.A>` example — which is not Swift; and the set
/// carries `removeBoundGeneric`, so `some Sequence<GenericBase<Int>>` lost
/// its `<Int>` and `Set<Int>` printed as `Swift.Set`.
@Suite(.serialized)
struct OpaqueConstraintRenderingTests {
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
        var description: String { "opaque-constraint fixture compilation failed:\n\(diagnostics)" }
    }

    private static let fixtureCompilationResult: Result<URL, Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("OpaqueConstraintFixture-\(UUID().uuidString)")
            _ = FixtureWorkingDirectoryCleanup.registration
            FixtureWorkingDirectoryCleanup.directories.append(workingDirectory)
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            let sourceURL = workingDirectory.appendingPathComponent("OpaqueConstraints.swift")
            try source.write(to: sourceURL, atomically: true, encoding: .utf8)
            let libraryURL = workingDirectory.appendingPathComponent("libProbeOpaqueConstraint.dylib")
            try run(swiftcArguments: [
                "-O", "-emit-library", "-module-name", "ProbeOpaqueConstraint",
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

    /// The classes double as ballast: a struct-only fixture dylib has no
    /// `__DATA` segment and the pinned MachOKit mis-walks its chained-fixup
    /// pages.
    private static let source = """
    public class Base {}
    public protocol Describable {}
    public final class Derived: Base, Describable {}
    public class GenericBase<Element> {}
    public final class GenericDerived: GenericBase<Int>, Describable {}

    public struct Holder {
        public init() {}
        public func superclassOnly() -> some Base { Derived() }
        public func superclassAndProtocol() -> some Base & Describable { Derived() }
        public func genericSuperclass() -> some GenericBase<Int> & Describable { GenericDerived() }
        public func sequenceOfBoundGeneric() -> some Sequence<GenericBase<Int>> { [GenericBase<Int>]() }
        public func sequenceOfSet() -> some Sequence<Set<Int>> { [Set<Int>]() }
    }

    public protocol Walkable {
        associatedtype Next: Walkable
    }
    public func sequenceOfOuterMember<Walker: Walkable>(_: Walker) -> some Sequence<Walker.Next> { [Walker.Next]() }
    public func sequenceOfNestedOuterMember<Walker: Walkable>(_: Walker) -> some Sequence<Walker.Next.Next> { [Walker.Next.Next]() }
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

    /// A superclass requirement is the descriptor's only constraint on the
    /// parameter; it used to render as a bare `some`.
    @Test func aSuperclassConstraintIsRendered() async throws {
        let interface = try await renderInterface()
        #expect(interface.contains("func superclassOnly() -> some ProbeOpaqueConstraint.Base\n"), "\(interface)")
    }

    /// The compiler's own interface printer puts the class first in a
    /// composition (`some Probe.Base & Probe.P`); a generic superclass keeps
    /// its arguments.
    @Test func aSuperclassPrecedesTheProtocolsOfItsComposition() async throws {
        let interface = try await renderInterface()
        #expect(interface.contains("func superclassAndProtocol() -> some ProbeOpaqueConstraint.Base & ProbeOpaqueConstraint.Describable\n"), "\(interface)")
        #expect(interface.contains("func genericSuperclass() -> some ProbeOpaqueConstraint.GenericBase<Swift.Int> & ProbeOpaqueConstraint.Describable\n"), "\(interface)")
    }

    /// The mangling qualifies each associated type with its declaring
    /// protocol (`Walker.[Walkable]Next`); Swift source does not.
    @Test func anOuterDependentMemberArgumentDropsItsProtocolQualifiers() async throws {
        let interface = try await renderInterface()
        #expect(interface.contains("-> some Swift.Sequence<A.Next> where A: ProbeOpaqueConstraint.Walkable"), "\(interface)")
        #expect(interface.contains("-> some Swift.Sequence<A.Next.Next> where A: ProbeOpaqueConstraint.Walkable"), "\(interface)")
    }

    /// `removeBoundGeneric` belongs to printing a type's name, not a type.
    @Test func aBoundGenericArgumentKeepsItsGenericArguments() async throws {
        let interface = try await renderInterface()
        #expect(interface.contains("func sequenceOfBoundGeneric() -> some Swift.Sequence<ProbeOpaqueConstraint.GenericBase<Swift.Int>>\n"), "\(interface)")
        #expect(interface.contains("func sequenceOfSet() -> some Swift.Sequence<Swift.Set<Swift.Int>>\n"), "\(interface)")
    }
}
