import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@_spi(Internals) import SwiftInspection
@testable import SwiftLayout
import Demangling

/// The static expanded field-offset tree names a member of a concrete type by
/// the type its conformance's witness record names (evolution proposal
/// `offline-generic-specialization`): `[Swift.Int].Element` reads `Swift.Int`.
/// A witness record can name an opaque type, though. The compiler writes the
/// underlying type into the record whenever it knows it, but not for a
/// `dynamic` naming declaration, whose result can be replaced, nor for an
/// availability-conditional one (SE-0360), whose underlying type depends on
/// the OS the code runs on — and not for a non-inlinable `some` of another
/// resilient module. The projection spliced that reference into the row as it
/// was, and the row printed the demangler's placeholder,
/// `() -> opaque type symbolic reference 0x….0`, where it used to print the
/// member, `DynamicConcrete.Body`.
@Suite
struct NestedFieldOffsetOpaqueWitnessTests {
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
        var description: String { "nested-field-offset opaque-witness fixture compilation failed:\n\(diagnostics)" }
    }

    private static let moduleName = "NestedFieldOffsetOpaqueWitnessFixture"

    /// `FixtureAnchor` is ballast: a fixture dylib with no class has no
    /// `__DATA` segment, which older MachOKit releases mis-walked.
    private static let fixtureSource = """
    public final class FixtureAnchor {}

    public protocol Shape {
        associatedtype Body
        var body: Body { get }
    }

    public struct DynamicConcrete: Shape {
        public init() {}
        public dynamic var body: some Equatable { 1 }
    }

    public struct ConditionalConcrete: Shape {
        public init() {}
        public var body: some Equatable {
            if #available(macOS 26, *) {
                return 1
            } else {
                return "one"
            }
        }
    }

    public struct Wrapper<Value: Shape> {
        public var make: () -> Value.Body
    }

    public struct DynamicHolder {
        public var wrapper: Wrapper<DynamicConcrete>
    }

    public struct ConditionalHolder {
        public var wrapper: Wrapper<ConditionalConcrete>
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
                "swiftc", "-swift-version", "5", "-O", "-emit-library",
                "-module-name", moduleName,
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

    @Test("a member whose witness is an opaque type is not named by a placeholder", arguments: ["DynamicHolder", "ConditionalHolder"])
    func memberWithAnOpaqueWitnessIsNotNamedByAPlaceholder(holderName: String) throws {
        let machOFile = try loadFixtureMachOFile()
        let holderDescriptor = try #require(
            try machOFile.swift.typeContextDescriptors.first { try $0.namedContextDescriptor.name(in: machOFile.context) == holderName }?.struct
        )
        let wrapperRecord = try #require(try holderDescriptor.fieldDescriptor(in: machOFile.context).records(in: machOFile.context).first)
        let calculator = StaticLayoutCalculator(imageUniverse: try ImageUniverse.dependencyClosure(root: machOFile, searchPaths: [.systemDyldSharedCache]))

        let tree = calculator.nestedFieldOffsetTree(forMangledTypeName: try wrapperRecord.mangledTypeName(in: machOFile.context), baseOffset: 0, depthLimit: 8)

        let make = try #require(tree.first { $0.fieldName == "make" }, "\(tree.map(\.fieldName))")
        // The demangler's two placeholders for an opaque reference it cannot
        // spell: one resolved from a file, one from a symbol.
        #expect(!make.typeName.contains("opaque type symbolic reference") && !make.typeName.contains("opaque return type"), "\(make.typeName)")
    }
}
