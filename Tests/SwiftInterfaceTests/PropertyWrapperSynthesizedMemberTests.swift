import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
@_spi(Support) @testable import SwiftInterface

/// `@Wrapper var x: Int` makes the compiler synthesize a stored `_x` of the
/// wrapper type and, when the wrapper projects, a computed `$x`. The source
/// declares only `x`, so the interface shows only `x` — once it can see that
/// `_x`'s type really is a property wrapper. A hand-written `_manual` behind a
/// computed `manual` has no such evidence and keeps rendering.
///
/// One module compiled on the fly (it carries a class: a struct-only fixture
/// dylib has no `__DATA` segment and MachOKit before 0.52.103 mis-walked its
/// chained-fixup pages).
@Suite(.serialized)
struct PropertyWrapperSynthesizedMemberTests {
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
        var description: String { "property-wrapper fixture compilation failed:\n\(diagnostics)" }
    }

    private static let fixtureCompilationResult: Result<URL, Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("PropertyWrapperFixture-\(UUID().uuidString)")
            _ = FixtureWorkingDirectoryCleanup.registration
            FixtureWorkingDirectoryCleanup.directories.append(workingDirectory)
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            let sourceURL = workingDirectory.appendingPathComponent("Wrappers.swift")
            try source.write(to: sourceURL, atomically: true, encoding: .utf8)
            let libraryURL = workingDirectory.appendingPathComponent("libProbeWrappers.dylib")
            try run(swiftcArguments: [
                "-O", "-emit-library", "-module-name", "ProbeWrappers",
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

    private static let source = """
    public final class ProbeAnchor {}

    @propertyWrapper
    public struct Clamped {
        public var wrappedValue: Int
        public var projectedValue: Clamped { self }
        public init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
    }

    @propertyWrapper
    public struct Boxed<Value> {
        public var wrappedValue: Value
        public var projectedValue: Boxed<Value> { self }
        public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
    }

    @propertyWrapper
    public struct Tagged<Tag, Value> {
        public var wrappedValue: Value
        public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
    }

    public struct Settings {
        @Clamped public var volume: Int = 3
        @Boxed public var title: String = ""
        @Tagged<String, Int> public var count: Int = 0
        public var _manual: Int = 0
        public var manual: Int { _manual }
        public init() {}
    }
    """

    private func loadFixture() throws -> MachOFile {
        let libraryURL = try Self.fixtureCompilationResult.get()
        switch try File.loadFromFile(url: libraryURL) {
        case .machO(let machOFile):
            return machOFile
        case .fat(let fatFile):
            return try #require(try fatFile.machOFiles().first { $0.header.cpuType == .arm64 })
        }
    }

    @Test func theInterfaceShowsTheDeclaredPropertyNotItsSynthesizedMembers() async throws {
        let machOFile = try loadFixture()
        let builder = try SwiftInterfaceBuilder(configuration: .init(), eventHandlers: [], in: machOFile)
        try await builder.prepare()
        let interface = try await builder.printRoot().string

        // The wrapper type itself is still a type of the module.
        #expect(interface.contains("@propertyWrapper\nstruct Clamped"), "\(interface)")
        // The declared property stays, as the computed property the binary
        // has, with the wrapper printed as its attribute.
        #expect(interface.contains("@ProbeWrappers.Clamped var volume: Swift.Int {"), "\(interface)")
        // The compiler-synthesized backing storage and projection are gone.
        #expect(!interface.contains("_volume"), "\(interface)")
        #expect(!interface.contains("$volume"), "\(interface)")
        // A hand-written `_manual` / `manual` pair carries no wrapper evidence.
        #expect(interface.contains("var _manual: Swift.Int"), "\(interface)")
        #expect(interface.contains("var manual: Swift.Int {"), "\(interface)")
        #expect(!interface.contains("@ProbeWrappers.Clamped var manual"), "\(interface)")
    }

    /// The binary records only the backing field's full type; the attribute
    /// omits the generic arguments exactly when the compiler would infer
    /// them (one argument, equal to the wrapped property's type) and keeps
    /// them otherwise. `@_projectedValueProperty` is compiler-internal and
    /// never printed.
    @Test func theWrapperAttributeSpellsGenericArgumentsOnlyWhenTheyAreNotInferable() async throws {
        let machOFile = try loadFixture()
        let builder = try SwiftInterfaceBuilder(configuration: .init(), eventHandlers: [], in: machOFile)
        try await builder.prepare()
        let interface = try await builder.printRoot().string

        // `_title: Boxed<String>` behind `title: String` — inferable, bare.
        #expect(interface.contains("@ProbeWrappers.Boxed var title: Swift.String {"), "\(interface)")
        #expect(!interface.contains("_title"), "\(interface)")
        #expect(!interface.contains("$title"), "\(interface)")
        // `_count: Tagged<String, Int>` behind `count: Int` — two arguments, kept.
        #expect(interface.contains("@ProbeWrappers.Tagged<Swift.String, Swift.Int> var count: Swift.Int {"), "\(interface)")
        #expect(!interface.contains("_count"), "\(interface)")
        #expect(!interface.contains("@_projectedValueProperty"), "\(interface)")
    }

    /// The in-process reader takes the same path: recovery happens at index
    /// time (`TypeDefinition.wrappedProperties`) from field records and
    /// member symbols, which read the same off a loaded image — so a host
    /// that drives `SwiftDeclarationPrinter` directly, as RuntimeViewer
    /// does, gets the hiding and the attribute without any wiring.
    @Test func theInProcessReaderRendersTheSameWrapperAttribute() async throws {
        let libraryURL = try Self.fixtureCompilationResult.get()
        _ = libraryURL.path.withCString { dlopen($0, RTLD_LAZY) }
        // `MachOImage(name:)` matches the loaded image by its bare file name.
        let machOImage = try #require(MachOImage(name: "libProbeWrappers"), "the fixture dylib did not load in-process")
        let builder = try SwiftInterfaceBuilder(configuration: .init(), eventHandlers: [], in: machOImage)
        try await builder.prepare()
        let interface = try await builder.printRoot().string

        #expect(interface.contains("@ProbeWrappers.Clamped var volume: Swift.Int {"), "\(interface)")
        #expect(interface.contains("@ProbeWrappers.Boxed var title: Swift.String {"), "\(interface)")
        #expect(interface.contains("@ProbeWrappers.Tagged<Swift.String, Swift.Int> var count: Swift.Int {"), "\(interface)")
        #expect(!interface.contains("_volume"), "\(interface)")
        #expect(!interface.contains("$volume"), "\(interface)")
        #expect(interface.contains("var _manual: Swift.Int"), "\(interface)")
    }
}
