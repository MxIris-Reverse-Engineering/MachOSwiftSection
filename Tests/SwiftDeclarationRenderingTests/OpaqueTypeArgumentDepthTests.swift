import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftDeclarationRendering
import Demangling
@_spi(Internals) import SwiftInspection
@_spi(Internals) import MachOSymbols

/// An opaque type reference spells its generic arguments as one list per
/// declaration around the opaque result, outermost first, and the mangler
/// writes a list for EVERY such declaration — an empty one for a level that
/// declares no parameter (`ASTMangler::appendBoundGenericArgs`). A parameter's
/// depth counts only the levels that declare parameters, so a list's position
/// is not its depth: the runtime flattens the lists and regroups them by the
/// descriptor's own depths (`resolveOpaqueType` → `_gatherGenericParameters`).
///
/// Taking the position for the depth left the parameter of a generic function
/// in a non-generic type unsubstituted — Xcodes' `MainToolbarModifier.Body`
/// printed `SwiftUI.TupleToolbarContent<A>` inside a type that has no
/// parameters — and, with a generic type nested in a non-generic one, read the
/// type's argument as the function's: a real, wrong type.
///
/// Driven through `resolveOpaqueType(in:)` on a hand-built node, as
/// `OpaqueTypeOrdinalTests` does: the compiler substitutes an opaque type it
/// can see through into the module's own reflection records, so a fixture
/// cannot produce a record that still references the descriptor. The node
/// carries the argument lists the mangler writes for these declarations.
@Suite
struct OpaqueTypeArgumentDepthTests {
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

    private struct FixtureCompilationError: Swift.Error, CustomStringConvertible {
        let diagnostics: String
        var description: String { "opaque-type-argument-depth fixture compilation failed:\n\(diagnostics)" }
    }

    private static let moduleName = "OpaqueTypeArgumentDepthFixture"

    /// `FixtureAnchor` is ballast: a fixture dylib with no class has no
    /// `__DATA` segment, which older MachOKit releases mis-walked.
    ///
    /// `ProbeNamespace` declares no parameter, so the mangler writes an empty
    /// list for it in front of every list below it: `makeWrapper`'s lists are
    /// `[[], [Element]]`, and `Box.makePair`'s are `[[], [Boxed], [Extra]]`.
    private static let fixtureSource = """
    public final class FixtureAnchor {}

    public protocol ProbeShape {}

    public struct ProbeWrapper<Wrapped>: ProbeShape {
        public var wrapped: Wrapped
        public init(wrapped: Wrapped) { self.wrapped = wrapped }
    }

    public struct ProbePair<First, Second>: ProbeShape {
        public var first: First
        public var second: Second
        public init(first: First, second: Second) {
            self.first = first
            self.second = second
        }
    }

    public enum ProbeNamespace {
        public static func makeWrapper<Element>(_ element: Element) -> some ProbeShape {
            ProbeWrapper(wrapped: element)
        }

        public struct Box<Boxed> {
            public var boxed: Boxed
            public init(boxed: Boxed) { self.boxed = boxed }

            public func makePair<Extra>(_ extra: Extra) -> some ProbeShape {
                ProbePair(first: boxed, second: extra)
            }
        }
    }
    """

    private static let fixtureCompilationResult: Result<URL, Swift.Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(moduleName)-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            _ = FixtureWorkingDirectoryCleanup.registration
            FixtureWorkingDirectoryCleanup.directories.append(workingDirectory)

            let sourceURL = workingDirectory.appendingPathComponent("\(moduleName).swift")
            let libraryURL = workingDirectory.appendingPathComponent("lib\(moduleName).dylib")
            try fixtureSource.write(to: sourceURL, atomically: true, encoding: .utf8)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = [
                "swiftc", "-swift-version", "5", "-emit-library", "-module-name", moduleName,
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

    /// The offset of the opaque type descriptor of the declaration named
    /// `declarationName`, found by its demangled symbol.
    private func opaqueTypeDescriptorOffset(ofDeclarationNamed declarationName: String, in machOFile: MachOFile) throws -> Int {
        let symbols = SymbolIndexStore.shared.symbols(of: .opaqueTypeDescriptor, in: machOFile)
        let symbol = symbols.first { $0.demangledNode.materialize().print(using: .default).contains(declarationName) }
        return try #require(symbol, "no opaque type descriptor names \(declarationName): \(symbols.map { $0.demangledNode.materialize().print(using: .default) })").offset
    }

    /// The underlying type of `declarationName`'s opaque result, resolved for
    /// a reference carrying `argumentListsByLevel` — one list per declaration
    /// around the result, as the mangler writes them.
    private func resolvedUnderlyingType(ofDeclarationNamed declarationName: String, argumentListsByLevel: [[Node]]) async throws -> String {
        let machOFile = try loadFixtureMachOFile()
        let descriptorOffset = try opaqueTypeDescriptorOffset(ofDeclarationNamed: declarationName, in: machOFile)
        let opaqueTypeNode = Node.create(
            kind: .type,
            children: [
                Node.create(
                    kind: .opaqueType,
                    children: [
                        Node.create(kind: .opaqueTypeDescriptorSymbolicReference, index: UInt64(descriptorOffset)),
                        Node.create(kind: .index, index: 0),
                        Node.create(kind: .typeList, children: argumentListsByLevel.map { Node.create(kind: .typeList, children: $0) }),
                    ]
                ),
            ]
        )
        return await (try opaqueTypeNode.resolveOpaqueType(in: machOFile)).print(using: DemangleOptions.default)
    }

    @Test("a generic function's argument is substituted when its type declares no parameter")
    func argumentOfAGenericFunctionInANonGenericTypeIsSubstituted() async throws {
        let integerType = try await demangleAsNode("Si", isType: true)

        let resolved = try await resolvedUnderlyingType(ofDeclarationNamed: "makeWrapper", argumentListsByLevel: [[], [integerType]])

        #expect(resolved == "\(Self.moduleName).ProbeWrapper<Swift.Int>")
    }

    @Test("each argument substitutes its own parameter when a level declaring none comes first")
    func eachArgumentSubstitutesItsOwnParameter() async throws {
        let integerType = try await demangleAsNode("Si", isType: true)
        let stringType = try await demangleAsNode("SS", isType: true)

        let resolved = try await resolvedUnderlyingType(ofDeclarationNamed: "makePair", argumentListsByLevel: [[], [integerType], [stringType]])

        #expect(resolved == "\(Self.moduleName).ProbePair<Swift.Int, Swift.String>")
    }
}
