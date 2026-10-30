import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
@_spi(Internals) import SwiftInspection
import SwiftDeclarationRendering
@_spi(Support) @testable import SwiftInterface

/// The depth of an opaque result's parameters: the innermost depth of the
/// descriptor's own layout, counted over every context above it that adds
/// parameters, anonymous ones included.
///
/// `swiftc -g -Onone` — every Xcode Debug build — adds
/// `-enable-anonymous-context-mangled-names`, and under it IRGen parents a
/// PROPERTY's opaque type descriptor on an anonymous context named after the
/// property (`OpaqueTypeDescriptorBuilder::getParent`). That context carries
/// the generic signature of the type or extension the property belongs to,
/// but its own parent is that type's parent — the module, for a top-level
/// type — so the type is nowhere on the descriptor's parent chain.
/// `SwiftInterfaceBuilderOpaqueTypeProvider` passed anonymous contexts over,
/// found no type or extension above, and put the opaque parameter of
/// `KeychainStorage<Value>.publisher` at depth 0 where the descriptor
/// constrains `τ_1_0`. A debug build trapped on the assertion guarding that
/// impossible depth — RuntimeViewer did, building its Find corpus over a test
/// bundle that links FoundationToolbox — and a release one printed a bare
/// `some`, or, for a `some Any` whose type has a constrained parameter, read
/// that parameter's constraint as the opaque one's: `some Storable`.
///
/// A property in an extension is the harder half. An extension's parent is
/// the module too, so its property's context adds every parameter of the
/// extended type at once, `Outer`'s `A` and `Inner`'s `B` alike, and only the
/// extended type's descriptor tells the two depths apart. When another image
/// declares that type — `ProbeOpaqueDepthCore`'s `Nest.Inner` here — a file
/// reader has no descriptor to split with and leaves the result bare, while
/// an image loaded in the process finds the one that image exports.
///
/// The provider also took a declaration to open a depth of its own whenever
/// its type carries a generic signature. A contextual `where` clause gives a
/// function one without a parameter, so in every build the opaque result of
/// `static func build() -> some Sequence<Value> where Value: Hashable` was
/// looked up one depth too deep and printed a bare `some` — SwiftUICore's
/// `KeyframesBuilder.buildBlock()` among them.
///
/// Exit tests, because the defect traps.
@Suite(.serialized)
struct OpaqueParameterDepthTests {
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
        var description: String { "opaque-parameter depth fixture compilation failed:\n\(diagnostics)" }
    }

    private struct UnexpectedInterface: Error, CustomStringConvertible {
        let interface: String
        var description: String { "the opaque results did not print their own constraints:\n\(interface)" }
    }

    private static let moduleName = "ProbeOpaqueDebugDepth"

    private static let coreModuleName = "ProbeOpaqueDepthCore"

    /// A nested generic type for the fixture to extend from another module,
    /// and the class every on-the-fly fixture carries as ballast: a
    /// struct-only dylib has no `__DATA` segment, and MachOKit before 0.52.103
    /// mis-walked its chained-fixup pages.
    private static let coreSource = """
    public final class CoreAnchor {}

    public struct Nest<A> {
        public struct Inner<B> {
            public init() {}
        }
    }
    """

    /// `Storage` has the shape of FoundationToolbox's `KeychainStorage`.
    private static let source = """
    import Combine
    import \(coreModuleName)

    public protocol Storable {}

    public final class Storage<Value: Storable>: @unchecked Sendable {
        private let subject = PassthroughSubject<Value, Never>()
        public init() {}
        public var publisher: some Publisher<Value, Never> { subject }
        // Constrains no opaque parameter, while the descriptor carries the
        // requirement on `Value` at the coordinate a depth-0 reading looks at.
        public var anything: some Any { 0 }
    }

    public struct Outer<A> {
        public struct Inner<B> {
            public init() {}
            // The context's parent is `Outer`: one depth short, not two.
            public var values: some Sequence<B> { [B]() }
        }
    }

    extension Outer.Inner where A: Hashable {
        public var pairs: some Sequence<B> { [B]() }
        // A function's context sits in the extension in every build.
        public func elements<Element>(_ element: Element) -> some Sequence<Element> { [element] }
    }

    extension Outer.Inner {
        public var outerValues: some Sequence<A> { [A]() }
    }

    public struct Builder<Value> {
        // A generic signature of its own, and no parameter of its own.
        public static func build() -> some Sequence<Value> where Value: Hashable { [Value]() }
    }

    // The extended type's descriptor is in the other image.
    extension Nest.Inner {
        public var foreignValues: some Sequence<B> { [B]() }
    }
    """

    /// Each opaque result's line in the interface, its constraint spelled by
    /// the parameter names its own depth gives it. `build`'s is matched from
    /// its result on: what its header prints is not this suite's business.
    private static let expectedInterfaceLines = [
        "final var publisher: some Combine.Publisher<A, Swift.Never> {",
        "final var anything: some {",
        "var values: some Swift.Sequence<A1> {",
        "var pairs: some Swift.Sequence<A1> {",
        "var outerValues: some Swift.Sequence<A> {",
        "func elements<A2>(_: A2) -> some Swift.Sequence<A2>",
        "-> some Swift.Sequence<A> where A: Swift.Hashable",
    ]

    /// `foreignValues` read from the file: the core image's descriptor is out
    /// of reach, so the depths cannot be told and the result stays bare.
    private static let fileReaderExpectedInterfaceLine = "var foreignValues: some {"

    /// `foreignValues` read in-process: the loader finds the descriptor the
    /// core image exports.
    private static let inProcessReaderExpectedInterfaceLine = "var foreignValues: some Swift.Sequence<A1> {"

    private static let fixtureCompilationResult: Result<URL, Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("OpaqueParameterDepthFixture-\(UUID().uuidString)")
            _ = FixtureWorkingDirectoryCleanup.registration
            FixtureWorkingDirectoryCleanup.directories.append(workingDirectory)
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            let coreSourceURL = workingDirectory.appendingPathComponent("OpaqueParameterDepthCore.swift")
            let sourceURL = workingDirectory.appendingPathComponent("OpaqueParameterDepth.swift")
            try coreSource.write(to: coreSourceURL, atomically: true, encoding: .utf8)
            try source.write(to: sourceURL, atomically: true, encoding: .utf8)
            let libraryURL = workingDirectory.appendingPathComponent("lib\(moduleName).dylib")
            try run(swiftcArguments: [
                "-swift-version", "5", "-Onone", "-emit-library", "-emit-module", "-module-name", coreModuleName,
                "-target", "arm64-apple-macosx15.0",
                "-Xlinker", "-install_name", "-Xlinker", "@rpath/lib\(coreModuleName).dylib",
                coreSourceURL.path, "-o", workingDirectory.appendingPathComponent("lib\(coreModuleName).dylib").path,
            ])
            try run(swiftcArguments: [
                // `-g -Onone` is what makes the driver pass
                // `-enable-anonymous-context-mangled-names`.
                "-swift-version", "5", "-g", "-Onone", "-emit-library", "-module-name", moduleName,
                "-target", "arm64-apple-macosx15.0",
                "-I", workingDirectory.path, "-L", workingDirectory.path, "-l\(coreModuleName)",
                "-Xlinker", "-rpath", "-Xlinker", workingDirectory.path,
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

    private static func machOFile() throws -> MachOFile {
        let libraryURL = try fixtureCompilationResult.get()
        switch try File.loadFromFile(url: libraryURL) {
        case .machO(let file):
            return file
        case .fat(let fatFile):
            return try #require(try fatFile.machOFiles().first { $0.header.cpuType == .arm64 })
        }
    }

    /// The fixture loaded into the process, read the way RuntimeViewer reads
    /// an image. Only ever called in an exit test's child.
    private static func loadedImage() throws -> MachOImage {
        let libraryURL = try fixtureCompilationResult.get()
        _ = libraryURL.path.withCString { dlopen($0, RTLD_NOW) }
        return try #require(MachOImage(name: libraryURL.deletingPathExtension().lastPathComponent), "the fixture dylib did not load in-process")
    }

    /// The opaque type descriptor of the declaration whose mangled name
    /// contains `fragment` — the identifier with its length, which no other
    /// declaration of the fixture shares.
    private static func opaqueTypeDescriptor(containing fragment: String, in machOFile: MachOFile) throws -> OpaqueTypeDescriptor {
        let symbol = try #require(
            machOFile.symbols.first { $0.nlist.flags?.stab == nil && $0.name.hasSuffix("QOMQ") && $0.name.contains(fragment) },
            "the fixture carries no opaque type descriptor for \(fragment)"
        )
        return try OpaqueTypeDescriptor.resolve(at: symbol.offset, in: machOFile.context)
    }

    /// The fixture's interface with the opaque type provider attached, as
    /// `interface --parse-opaque-return-type` and RuntimeViewer print it; it
    /// throws unless every opaque result prints its own constraint and none
    /// prints one of its type's parameters.
    static func printInterfaceNamingEachOpaqueConstraint<MachO: MachOFieldLayoutRenderable & Sendable>(of machO: MachO, readerExpectedLine: String) async throws {
        let builder = try SwiftInterfaceBuilder(configuration: .init(), eventHandlers: [], in: machO)
        builder.addExtraDataProvider(SwiftInterfaceBuilderOpaqueTypeProvider(machO: machO))
        try await builder.prepare()
        let interface = try await builder.printRoot().string
        guard (expectedInterfaceLines + [readerExpectedLine]).allSatisfy(interface.contains), !interface.contains("some \(moduleName).Storable") else {
            throw UnexpectedInterface(interface: interface)
        }
    }

    @Test("the fixture parents a property's opaque type on an anonymous context")
    func fixtureHasTheDebugBuildShape() throws {
        let machOFile = try Self.machOFile()
        for fragment in ["9publisherQr", "6valuesQr", "5pairsQr", "11outerValuesQr"] {
            let descriptor = try Self.opaqueTypeDescriptor(containing: fragment, in: machOFile)
            let parent = try #require(try descriptor.parent(in: machOFile.context)?.resolved)
            #expect(parent.isAnonymous, "\(fragment): the opaque type's parent is no longer the property's anonymous context; the fixture no longer has the shape this suite is about")
        }
    }

    @Test("an opaque type's depths count every context that adds parameters")
    func opaqueTypeDepthsCountEveryContextAddingParameters() throws {
        let machOFile = try Self.machOFile()
        let expectedCountsByFragment: KeyValuePairs<String, [Int]?> = [
            "9publisherQr": [1, 1],
            "8anythingQr": [1, 1],
            "6valuesQr": [1, 1, 1],
            // The extended type's descriptor splits `A` and `B`.
            "5pairsQr": [1, 1, 1],
            "11outerValuesQr": [1, 1, 1],
            "8elements": [1, 1, 1, 1],
            "5buildQr": [1, 1],
            // No descriptor to split them with: no answer rather than a guess.
            "13foreignValuesQr": nil,
        ]
        for (fragment, expectedCounts) in expectedCountsByFragment {
            let descriptor = try Self.opaqueTypeDescriptor(containing: fragment, in: machOFile)
            let genericContext = try #require(try OpaqueType(descriptor: descriptor, in: machOFile.context).genericContext)
            let depthLayout = GenericParameterDepthLayout.make(forOpaqueType: descriptor, genericContext: genericContext, in: machOFile.context)
            #expect(depthLayout?.parameterCountsByDepth == expectedCounts, "\(fragment): \(String(describing: depthLayout?.parameterCountsByDepth))")
        }
    }

    @Test("opaque results name their own constraints, read from the file")
    func opaqueResultsNameTheirConstraintsReadFromTheFile() async {
        await #expect(processExitsWith: .success) {
            do {
                try await OpaqueParameterDepthTests.printInterfaceNamingEachOpaqueConstraint(
                    of: OpaqueParameterDepthTests.machOFile(),
                    readerExpectedLine: OpaqueParameterDepthTests.fileReaderExpectedInterfaceLine
                )
            } catch {
                // An error thrown out of an exit test ends the child on a
                // trap too; exiting keeps a wrong interface apart from the
                // provider's own trap.
                exit(EXIT_FAILURE)
            }
        }
    }

    @Test("opaque results name their own constraints, read in-process")
    func opaqueResultsNameTheirConstraintsReadInProcess() async {
        await #expect(processExitsWith: .success) {
            do {
                try await OpaqueParameterDepthTests.printInterfaceNamingEachOpaqueConstraint(
                    of: OpaqueParameterDepthTests.loadedImage(),
                    readerExpectedLine: OpaqueParameterDepthTests.inProcessReaderExpectedInterfaceLine
                )
            } catch {
                exit(EXIT_FAILURE)
            }
        }
    }
}
