import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
import SwiftInterface

/// The interface side of wrapped-property recovery for the two cases the
/// same-image suite (`PropertyWrapperSynthesizedMemberTests`) cannot show:
/// a wrapper defined in another image, and a wrapped property whose own
/// accessors are stripped. Two modules compiled on the fly (each with a
/// class, for the `__DATA` segment the pinned MachOKit needs): the kit
/// defines the wrappers, the client uses them and is linked with `-x`.
@Suite(.serialized)
struct StrippedWrappedPropertyRenderingTests {
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
        var description: String { "stripped wrapped-property fixture compilation failed:\n\(diagnostics)" }
    }

    private struct Products {
        let kitURL: URL
        let clientURL: URL
    }

    private static let kitSource = """
    public final class KitAnchor {}

    @propertyWrapper
    public struct Boxed<Value> {
        public var wrappedValue: Value
        public var projectedValue: Boxed<Value> { self }
        public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
    }

    @propertyWrapper
    public struct ReadOnly<Value> {
        public var wrappedValue: Value { storage }
        private let storage: Value
        public init(wrappedValue: Value) { storage = wrappedValue }
    }
    """

    private static let clientSource = """
    import ProbeRenderingWrapperKit

    public final class ClientAnchor {}

    public struct Panel {
        @Boxed public var title: String = ""
        @Boxed var subtitle: String = ""
        @ReadOnly var revision: Int = 0
        var _manual: Int = 0
        var manual: Int { _manual }
        public init() {}
    }
    """

    private static let compilationResult: Result<Products, Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("StrippedWrappedPropertyFixture-\(UUID().uuidString)")
            _ = WorkingDirectoryCleanup.registration
            WorkingDirectoryCleanup.directories.append(workingDirectory)
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            let kitSourceURL = workingDirectory.appendingPathComponent("Kit.swift")
            let clientSourceURL = workingDirectory.appendingPathComponent("Client.swift")
            try kitSource.write(to: kitSourceURL, atomically: true, encoding: .utf8)
            try clientSource.write(to: clientSourceURL, atomically: true, encoding: .utf8)
            let kitURL = workingDirectory.appendingPathComponent("libProbeRenderingWrapperKit.dylib")
            let clientURL = workingDirectory.appendingPathComponent("libProbeRenderingWrapperClient.dylib")
            try run(swiftcArguments: [
                "-O", "-emit-library", "-emit-module", "-module-name", "ProbeRenderingWrapperKit",
                "-target", "arm64-apple-macosx15.0",
                "-Xlinker", "-install_name", "-Xlinker", kitURL.path,
                kitSourceURL.path, "-o", kitURL.path,
            ])
            try run(swiftcArguments: [
                "-O", "-emit-library", "-module-name", "ProbeRenderingWrapperClient",
                "-target", "arm64-apple-macosx15.0",
                "-I", workingDirectory.path, "-L", workingDirectory.path, "-lProbeRenderingWrapperKit",
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

    private func renderOfflineInterface() async throws -> String {
        let products = try Self.compilationResult.get()
        let machOFile: MachOFile
        switch try File.loadFromFile(url: products.clientURL) {
        case .machO(let file):
            machOFile = file
        case .fat(let fatFile):
            machOFile = try #require(try fatFile.machOFiles().first { $0.header.cpuType == .arm64 })
        }
        let configuration = SwiftInterfaceBuilderConfiguration(
            indexConfiguration: .init(showCImportedTypes: false, dependencySearchPaths: [.machOFile(path: products.kitURL.path), .systemDyldSharedCache]),
            printConfiguration: .init()
        )
        let builder = try SwiftInterfaceBuilder(configuration: configuration, eventHandlers: [], in: machOFile)
        try await builder.prepare()
        return try await builder.printRoot().string
    }

    private func renderInProcessInterface() async throws -> String {
        let products = try Self.compilationResult.get()
        _ = products.kitURL.path.withCString { dlopen($0, RTLD_LAZY) }
        _ = products.clientURL.path.withCString { dlopen($0, RTLD_LAZY) }
        let machOImage = try #require(MachOImage(name: "libProbeRenderingWrapperClient"), "the client dylib did not load in-process")
        let builder = try SwiftInterfaceBuilder(configuration: .init(), eventHandlers: [], in: machOImage)
        try await builder.prepare()
        return try await builder.printRoot().string
    }

    private func assertPanelRendering(_ interface: String) {
        // Declared member, wrapper from the kit: the attribute names it.
        #expect(interface.contains("@ProbeRenderingWrapperKit.Boxed var title: Swift.String {"), "\(interface)")
        #expect(!interface.contains("_title"), "\(interface)")
        #expect(!interface.contains("$title"), "\(interface)")
        // Stripped accessors: synthesized in place of the backing field,
        // settable because `Boxed.wrappedValue` is a `var`.
        #expect(interface.contains("""
            // synthesized from the backing storage `_subtitle`; the property's own accessors are stripped
            @ProbeRenderingWrapperKit.Boxed var subtitle: Swift.String {
                get
                set
            }
        """), "\(interface)")
        // Read-only wrapper: no setter to synthesize.
        #expect(interface.contains("""
            // synthesized from the backing storage `_revision`; the property's own accessors are stripped
            @ProbeRenderingWrapperKit.ReadOnly var revision: Swift.Int {
                get
            }
        """), "\(interface)")
        #expect(!interface.contains("var _subtitle"), "\(interface)")
        #expect(!interface.contains("var _revision"), "\(interface)")
        // A hand-written `_manual` keeps rendering: `Int` is no wrapper.
        #expect(interface.contains("var _manual: Swift.Int"), "\(interface)")
    }

    @Test func theOfflineReaderRecoversWrappedPropertiesThroughTheSearchPath() async throws {
        assertPanelRendering(try await renderOfflineInterface())
    }

    @Test func theInProcessReaderRecoversWrappedPropertiesThroughTheLoadedImages() async throws {
        assertPanelRendering(try await renderInProcessInterface())
    }
}
