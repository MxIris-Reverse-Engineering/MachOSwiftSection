import Foundation
import Testing
import MachOKit
import MachOFoundation
import Demangling
import MachOSwiftSection
@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing

/// Two modules compiled on the fly, each carrying a class (a struct-only
/// fixture dylib has no `__DATA` segment and MachOKit before 0.52.103 mis-walked
/// its chained-fixup pages):
///
/// - `ProbeWrapperKit` defines the wrappers — two public, one internal —
///   and uses them itself, with every symbol kept.
/// - `ProbeWrapperClient` links the kit, uses its public wrappers, and is
///   linked with `-x`, so its internal properties lose their accessor
///   symbols the way a shipped framework's do.
///
/// A separate type on purpose: a `@Suite(.enabled(if:))` condition that
/// reads a static of the suite it decorates is a circular macro reference.
enum WrappedPropertyFixture {
    private enum WorkingDirectoryCleanup {
        nonisolated(unsafe) static var directories: [URL] = []
        static let registration: Void = {
            atexit {
                for directory in WorkingDirectoryCleanup.directories {
                    try? FileManager.default.removeItem(at: directory)
                }
            }
        }()
    }

    private struct CompilationError: Error, CustomStringConvertible {
        let diagnostics: String
        var description: String { "wrapped-property fixture compilation failed:\n\(diagnostics)" }
    }

    static let kitModuleName = "ProbeWrapperKit"
    static let clientModuleName = "ProbeWrapperClient"

    private static let kitSource = """
    public final class KitAnchor {}

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

    @propertyWrapper
    struct Hidden {
        var wrappedValue: Int
        init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
    }

    public struct Owner {
        @Hidden var secret: Int = 1
        @Boxed public var label: String = ""
        public init() {}
    }
    """

    private static let clientSource = """
    import ProbeWrapperKit

    public final class ClientAnchor {}

    public struct Panel {
        @Boxed public var title: String = ""
        @Boxed var subtitle: String = ""
        @Tagged<String, Int> var count: Int = 0
        var _manual: Int = 0
        var manual: Int { _manual }
        public init() {}
    }
    """

    struct Products {
        let kitURL: URL
        let clientURL: URL
    }

    static let compilationResult: Result<Products, Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("WrappedPropertyFixture-\(UUID().uuidString)")
            _ = WorkingDirectoryCleanup.registration
            WorkingDirectoryCleanup.directories.append(workingDirectory)
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            let kitSourceURL = workingDirectory.appendingPathComponent("Kit.swift")
            let clientSourceURL = workingDirectory.appendingPathComponent("Client.swift")
            try kitSource.write(to: kitSourceURL, atomically: true, encoding: .utf8)
            try clientSource.write(to: clientSourceURL, atomically: true, encoding: .utf8)
            let kitURL = workingDirectory.appendingPathComponent("lib\(kitModuleName).dylib")
            let clientURL = workingDirectory.appendingPathComponent("lib\(clientModuleName).dylib")
            // The kit's install name is its absolute path, so the client's
            // load command resolves both in-process (`dlopen`) and offline
            // (the file locator registers the file under that name).
            try run(swiftcArguments: [
                "-O", "-emit-library", "-emit-module", "-module-name", kitModuleName,
                "-target", "arm64-apple-macosx15.0",
                "-Xlinker", "-install_name", "-Xlinker", kitURL.path,
                kitSourceURL.path, "-o", kitURL.path,
            ])
            try run(swiftcArguments: [
                "-O", "-emit-library", "-module-name", clientModuleName,
                "-target", "arm64-apple-macosx15.0",
                "-I", workingDirectory.path, "-L", workingDirectory.path, "-l\(kitModuleName)",
                // Strip local symbols: internal accessors vanish, exports stay.
                "-Xlinker", "-x",
                clientSourceURL.path, "-o", clientURL.path,
            ])
            return Products(kitURL: kitURL, clientURL: clientURL)
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
            throw CompilationError(diagnostics: String(decoding: diagnosticsData, as: UTF8.self))
        }
    }

    static func machOFile(at url: URL) throws -> MachOFile {
        switch try File.loadFromFile(url: url) {
        case .machO(let machOFile):
            return machOFile
        case .fat(let fatFile):
            return try #require(try fatFile.machOFiles().first { $0.header.cpuType == .arm64 })
        }
    }

    /// Loads both dylibs into the test process (the kit first, so the
    /// client's load command resolves) and returns the client's image.
    static func loadedClientImage() throws -> MachOImage {
        let products = try compilationResult.get()
        _ = products.kitURL.path.withCString { dlopen($0, RTLD_LAZY) }
        _ = products.clientURL.path.withCString { dlopen($0, RTLD_LAZY) }
        return try #require(MachOImage(name: "lib\(clientModuleName)"), "the client dylib did not load in-process")
    }

    /// The indexed definition named `typeName` in an image, or a failure.
    static func indexedTypeDefinition(named typeName: String, in machO: some MachOSwiftSectionRepresentableWithCache, dependencySearchPaths: [DependencySearchPath] = [.systemDyldSharedCache]) async throws -> TypeDefinition {
        let indexer = SwiftDeclarationIndexer(configuration: .init(showCImportedTypes: false, dependencySearchPaths: dependencySearchPaths), eventHandlers: [], in: machO)
        try await indexer.prepare()
        let definition = try #require(indexer.allTypeDefinitions.values.first { $0.typeName.name.hasSuffix(".\(typeName)") }, "no type named \(typeName)")
        try await definition.index(in: machO)
        return definition
    }
}

/// `TypeDefinition.wrappedProperties` is recovered at index time from the
/// compiler-synthesized `_x` / `$x`: a stored `_x` whose type has
/// `wrappedValue` accessors — in this image's own symbols, or exported by
/// an image the dependency closure reaches — is a wrapper's storage. When
/// `x` still has accessors it is the declared member; when they are
/// stripped the declaration is synthesized from the wrapper's `wrappedValue`
/// type with the field's generic arguments substituted.
@Suite(.serialized)
struct WrappedPropertyRecoveryTests {
    private func attributeSpelling(of wrappedProperty: WrappedPropertyDefinition) -> String {
        wrappedProperty.attributeTypeNode.print(using: .default)
    }

    private func synthesizedDeclaredType(of wrappedProperty: WrappedPropertyDefinition) -> (type: String, hasSetter: Bool)? {
        guard case .synthesized(let declaredTypeNode, let hasSetter) = wrappedProperty.origin else { return nil }
        return (declaredTypeNode.print(using: .default), hasSetter)
    }

    @Test func aWrapperDefinedInTheSameImageIsRecognizedThroughItsOwnSymbolsEvenWhenInternal() async throws {
        let products = try WrappedPropertyFixture.compilationResult.get()
        let owner = try await WrappedPropertyFixture.indexedTypeDefinition(named: "Owner", in: try WrappedPropertyFixture.machOFile(at: products.kitURL))

        let byName = Dictionary(uniqueKeysWithValues: owner.wrappedProperties.map { ($0.name, $0) })
        #expect(Set(byName.keys) == ["secret", "label"])
        // The internal wrapper's `wrappedValue` accessors are local symbols
        // the kit keeps, so `secret` is recognized; its accessors are kept
        // too, so it is the declared member.
        let secret = try #require(byName["secret"])
        #expect(secret.backingFieldName == "_secret")
        #expect(secret.projectionName == "$secret")
        if case .declaredMember = secret.origin {} else { Issue.record("secret should be a declared member") }
        #expect(attributeSpelling(of: secret) == "ProbeWrapperKit.Hidden")
        // `Boxed<String>` behind `label: String`: one argument equal to the
        // wrapped type, so the attribute is bare.
        let label = try #require(byName["label"])
        #expect(attributeSpelling(of: label) == "ProbeWrapperKit.Boxed")
        // The model keeps what the binary has; only the interface hides it.
        #expect(owner.fields.contains { $0.name == "_secret" })
    }

    @Test func aWrapperFromAnotherImageIsRecognizedThroughThatImagesExports() async throws {
        let products = try WrappedPropertyFixture.compilationResult.get()
        let panel = try await WrappedPropertyFixture.indexedTypeDefinition(
            named: "Panel",
            in: try WrappedPropertyFixture.machOFile(at: products.clientURL),
            dependencySearchPaths: [.machOFile(path: products.kitURL.path), .systemDyldSharedCache]
        )
        try assertPanelRecovery(panel)
    }

    @Test func theInProcessReaderRecoversTheSameProperties() async throws {
        let clientImage = try WrappedPropertyFixture.loadedClientImage()
        let panel = try await WrappedPropertyFixture.indexedTypeDefinition(named: "Panel", in: clientImage)
        try assertPanelRecovery(panel)
    }

    /// Without the kit on any search path, the client's `_title` is just a
    /// stored field of an unknown type: no wrapper is recognized and nothing
    /// is synthesized — an honest "unknown", never a guess.
    @Test func aWrapperNoSearchPathReachesIsNotRecognized() async throws {
        let products = try WrappedPropertyFixture.compilationResult.get()
        let panel = try await WrappedPropertyFixture.indexedTypeDefinition(
            named: "Panel",
            in: try WrappedPropertyFixture.machOFile(at: products.clientURL),
            dependencySearchPaths: []
        )
        #expect(panel.wrappedProperties.isEmpty)
    }

    private func assertPanelRecovery(_ panel: TypeDefinition) throws {
        let byName = Dictionary(uniqueKeysWithValues: panel.wrappedProperties.map { ($0.name, $0) })
        #expect(Set(byName.keys) == ["title", "subtitle", "count"], "\(byName.keys)")
        // `title` is public: its accessors are exported and survive `-x`.
        let title = try #require(byName["title"])
        if case .declaredMember = title.origin {} else { Issue.record("title should be a declared member") }
        #expect(attributeSpelling(of: title) == "ProbeWrapperKit.Boxed")
        // `subtitle` is internal: its accessors are stripped, so the
        // declaration comes from `Boxed<String>.wrappedValue: Value` with
        // `Value := String`; `wrappedValue` is a `var`, so it is settable.
        let subtitle = try #require(byName["subtitle"])
        let subtitleDeclaration = try #require(synthesizedDeclaredType(of: subtitle), "subtitle should be synthesized")
        #expect(subtitleDeclaration.type == "Swift.String")
        #expect(subtitleDeclaration.hasSetter == true)
        #expect(attributeSpelling(of: subtitle) == "ProbeWrapperKit.Boxed")
        // `count` is wrapped by a two-parameter wrapper: the attribute keeps
        // both arguments, and `Value` is the second of them.
        let count = try #require(byName["count"])
        let countDeclaration = try #require(synthesizedDeclaredType(of: count), "count should be synthesized")
        #expect(countDeclaration.type == "Swift.Int")
        #expect(attributeSpelling(of: count) == "ProbeWrapperKit.Tagged<Swift.String, Swift.Int>")
        // A hand-written `_manual` / `manual` pair: `Int` is no wrapper.
        #expect(byName["manual"] == nil)
    }
}
