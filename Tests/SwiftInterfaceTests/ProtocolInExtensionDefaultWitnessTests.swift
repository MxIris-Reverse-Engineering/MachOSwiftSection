import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
@_spi(Support) @testable import SwiftInterface
import Semantic
import SwiftSectionFixtureSupport

/// A protocol declared in an extension of another module's type prints its
/// default-implementation extensions in the interface's top-level block for
/// nested protocols (evolution proposal `nested-definition-regions`). That
/// block reads the protocol's `defaultImplementationExtensions` before the
/// protocol itself is printed: it is printed — and indexed — inside the
/// extension declaring it, in the last block.
///
/// An extension the module indexer attaches during `prepare()` is there by
/// then; one the protocol's own index pass synthesizes is not. Under library
/// evolution a requirement whose default comes from a parent protocol's
/// extension — `Labeled.describe()`, from `extension Base` — is implemented by
/// a default witness named after the requirement itself, which no
/// protocol-extension block holds, so only the index pass finds it. That
/// extension printed nowhere: not after the protocol, which no longer trails
/// its extensions, and not in the top-level block, which ran first.
@Suite(.serialized)
struct ProtocolInExtensionDefaultWitnessTests {
    /// `FixtureAnchor` is ballast: a fixture dylib with no class has no
    /// `__DATA` segment, which older MachOKit releases mis-walked.
    private static let source = """
    public final class FixtureAnchor {}

    public protocol Base {}

    extension Base {
        public func describe() -> String { "base" }
    }

    extension Int {
        public protocol Labeled: Base {
            func describe() -> String
        }
    }
    """

    private static func libraryURL() throws -> URL {
        try FixtureCompiler.shared.dynamicLibrary(
            named: "ProbeDefaultWitness",
            language: .swift,
            sourceFiles: [FixtureSourceFile(name: "ProtocolInExtensionDefaultWitness.swift", contents: source)],
            // Library evolution makes `Labeled` resilient, which is what
            // gives its requirement a default witness of its own.
            arguments: ["-swift-version", "5", "-O", "-enable-library-evolution", "-target", "arm64-apple-macosx15.0"]
        )
    }

    private func makeBuilder() async throws -> SwiftInterfaceBuilder<MachOFile> {
        let machOFile = try HostSlice.machOFile(at: Self.libraryURL())
        let builder = try SwiftInterfaceBuilder(configuration: .init(), eventHandlers: [], in: machOFile)
        try await builder.prepare()
        return builder
    }

    @Test("a default implementation only the protocol's own index finds prints in the interface")
    func defaultImplementationFoundByTheIndexPassPrints() async throws {
        let interface = try await makeBuilder().printRoot().string

        let topLevelExtensionLines = interface.split(separator: "\n").filter { $0.hasPrefix("extension ") }
        #expect(topLevelExtensionLines.contains { $0.contains("Int.Labeled") }, "\(interface)")
    }

    @Test("printing the same builder twice gives the same interface")
    func printingTwiceGivesTheSameInterface() async throws {
        let builder = try await makeBuilder()

        let firstInterface = try await builder.printRoot().string
        let secondInterface = try await builder.printRoot().string

        #expect(firstInterface == secondInterface)
    }
}
