import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
import Demangling
@_spi(Internals) import SwiftInspection
import SwiftDeclarationRendering
@testable import SwiftThunkAnalysis

/// A kind-9 accessor thunk names the type it instantiates by the accessor it
/// calls: the type's descriptor, and one key argument per generic parameter
/// of the type's whole context. The node builder counted the parameters of the
/// type contexts on the declaration chain only and stopped at any other parent
/// — an extension — so a generic type declared in a generic extension
/// (`extension Outer where A: Hashable { struct Inner<B> }`) counted one key
/// parameter where its accessor takes two, `Outer`'s `A` and its own `B`. The
/// field read `accessor function at …` in dump and interface. The extension
/// walk `GenericArgumentEnvironment` gained in evolution proposal
/// `offline-generic-specialization` is the reading side of the same shape.
@Suite(.serialized)
struct AccessorThunkTypeInGenericExtensionTests {
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
        var description: String { "accessor-thunk generic-extension fixture compilation failed:\n\(diagnostics)" }
    }

    /// `Inner` is `~Copyable`, so a field of it is instantiated by a thunk
    /// that first asks whether the runtime supports noncopyable types — a
    /// kind-9 accessor function reference in the field record. The class is
    /// ballast: a struct-only fixture dylib has no `__DATA` segment, which
    /// older MachOKit releases mis-walked.
    private static let fixtureSource = """
    public final class FixtureAnchor {}

    public struct Outer<A> {}

    extension Outer where A: Hashable {
        public struct Inner<B>: ~Copyable {
            public var value: Int
        }
    }

    public struct Holder<T: Hashable, U>: ~Copyable {
        public var inner: Outer<T>.Inner<U>
    }

    public struct SameTypeOuter<A> {}

    extension SameTypeOuter where A == Int {
        public struct Inner<B>: ~Copyable {
            public var value: Int
        }
    }

    public struct SameTypeHolder<U>: ~Copyable {
        public var inner: SameTypeOuter<Int>.Inner<U>
    }
    """

    private static let fixtureCompilationResult: Result<URL, Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("AccessorThunkGenericExtensionFixture-\(UUID().uuidString)")
            _ = FixtureWorkingDirectoryCleanup.registration
            FixtureWorkingDirectoryCleanup.directories.append(workingDirectory)
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            let sourceURL = workingDirectory.appendingPathComponent("AccessorThunkGenericExtension.swift")
            let libraryURL = workingDirectory.appendingPathComponent("libProbeThunkExtension.dylib")
            try fixtureSource.write(to: sourceURL, atomically: true, encoding: .utf8)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            // Optimized so the thunk takes the shape a shipping binary carries.
            process.arguments = [
                "swiftc", "-swift-version", "5", "-O", "-emit-library", "-module-name", "ProbeThunkExtension",
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

    private func loadFixture() throws -> MachOFile {
        let libraryURL = try Self.fixtureCompilationResult.get()
        switch try File.loadFromFile(url: libraryURL) {
        case .machO(let machOFile):
            return machOFile
        case .fat(let fatFile):
            return try #require(try fatFile.machOFiles().first { $0.header.cpuType == .arm64 })
        }
    }

    /// The `inner` field's type of the holder named `holderName`, read
    /// through the entry the indexer uses for a kind-9 field: the thunk's
    /// arguments named as the holder's parameters.
    private func resolvedInnerFieldType(ofHolderNamed holderName: String) throws -> String {
        let machOFile = try loadFixture()
        let holder = try #require(
            try machOFile.swift.typeContextDescriptors.first { try $0.namedContextDescriptor.name(in: machOFile.context) == holderName }
        )
        let genericContext = try #require(try holder.typeContextDescriptor.genericContext(in: machOFile.context))
        let ownerLayout = AccessorThunkOwnerLayout(
            genericContext: genericContext,
            depthLayout: GenericParameterDepthLayout.make(for: genericContext, ownedBy: holder.asContextDescriptorWrapper, in: machOFile.context)
        )
        let record = try #require(
            try holder.typeContextDescriptor.fieldDescriptor(in: machOFile.context).records(in: machOFile.context).first { try $0.fieldName(in: machOFile.context) == "inner" }
        )
        let typeNode = try SymbolicDemangler.demangleType(for: try record.mangledTypeName(in: machOFile.context), in: machOFile.context)
        try #require(typeNode.contains(.accessorFunctionReference), "the field must be read through a thunk for this test to mean anything: \(typeNode.print(using: .default))")
        return typeNode.resolvingAccessorFunctionReferences(in: machOFile, ownerLayout: ownerLayout).print(using: .default)
    }

    @Test("a thunk instantiating a generic type declared in a generic extension is named")
    func thunkInstantiatingATypeInAGenericExtensionIsNamed() throws {
        let fieldType = try resolvedInnerFieldType(ofHolderNamed: "Holder")

        #expect(!fieldType.contains("accessor function"), "\(fieldType)")
        #expect(fieldType.contains("Outer<A>") && fieldType.contains("Inner<B>"), "\(fieldType)")
    }

    /// A type in a same-type-constrained extension receives the arguments of
    /// its own parameters alone — the parameter the extension fixes takes no
    /// key argument — and the walk of the type contexts names it. Naming the
    /// instantiation from the whole context cannot, so it must not take over
    /// there: doing so turned this field into `accessor function at …`.
    @Test("a thunk instantiating a generic type declared in a same-type-constrained extension stays named")
    func thunkInstantiatingATypeInASameTypeConstrainedExtensionStaysNamed() throws {
        let fieldType = try resolvedInnerFieldType(ofHolderNamed: "SameTypeHolder")

        #expect(!fieldType.contains("accessor function"), "\(fieldType)")
        #expect(fieldType.contains("SameTypeOuter< where A == Swift.Int>.Inner<A>"), "\(fieldType)")
    }
}
