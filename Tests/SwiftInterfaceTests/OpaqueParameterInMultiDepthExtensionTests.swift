import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
@_spi(Support) @testable import SwiftInterface
import Semantic
import SwiftSectionFixtureSupport

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
    private struct MissingConstraint: Swift.Error, CustomStringConvertible {
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

    private static func libraryURL() throws -> URL {
        try FixtureCompiler.shared.dynamicLibrary(
            named: "ProbeOpaqueExtensionDepth",
            language: .swift,
            sourceFiles: [FixtureSourceFile(name: "OpaqueParameterExtensionDepth.swift", contents: source)],
            arguments: ["-swift-version", "5", "-O", "-target", "arm64-apple-macosx15.0"]
        )
    }

    /// The fixture's interface with the opaque type provider attached, as
    /// `interface --parse-opaque-return-type` and RuntimeViewer print it; it
    /// throws unless the opaque result names its constraint.
    static func printInterfaceNamingTheOpaqueConstraint() async throws {
        let machOFile = try HostSlice.machOFile(at: libraryURL())
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
