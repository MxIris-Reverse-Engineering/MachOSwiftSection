import Foundation
import Testing
import MachOKit
import MachOFoundation
import Demangling
@testable import MachOSwiftSection
@testable import SwiftLayout
@_spi(Internals) import SwiftInspection

/// The fixture the two suites below share: a module with `@_rawLayout`
/// enabled, compiled on the fly (it carries a class: a struct-only fixture
/// dylib has no `__DATA` segment and MachOKit before 0.52.103 mis-walked its
/// chained-fixup pages). A separate type on purpose: a `@Suite(.enabled(if:))`
/// condition that reads a static of the suite it decorates is a circular
/// macro reference.
///
/// Compiled for macOS 27 so no field type hides behind an accessor thunk
/// (`NoncopyableReflectionSafety` wraps every noncopyable field type in one
/// below that deployment target, and the static engine does not read thunks
/// — see `draft-static-layout-through-accessor-thunks`). A Swift 6.3
/// toolchain does not honor that threshold, so the offset suite runs only
/// under Swift 6.4 or newer; the whole-type suite reads nothing but the
/// struct declarations and runs everywhere.
enum RawLayoutBuiltinDescriptorFixture {
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
        var description: String { "raw-layout layout fixture compilation failed:\n\(diagnostics)" }
    }

    static let moduleName = "ProbeRawLayoutLayout"

    private static let source = """
    public final class ProbeAnchor {}

    @_rawLayout(size: 12, alignment: 4)
    public struct OpaqueTwelve: ~Copyable {
        public init() {}
    }

    @_rawLayout(likeArrayOf: UInt32, count: 4)
    public struct QuadWords: ~Copyable {
        public init() {}
    }

    public struct Holder: ~Copyable {
        public var tag: UInt8 = 0
        public var opaque: OpaqueTwelve = OpaqueTwelve()
        public var quad: QuadWords = QuadWords()
        public var tail: UInt8 = 0
        public init() {}
    }
    """

    static let compilationResult: Result<URL, Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("RawLayoutLayoutFixture-\(UUID().uuidString)")
            _ = WorkingDirectoryCleanup.registration
            WorkingDirectoryCleanup.directories.append(workingDirectory)
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            let sourceURL = workingDirectory.appendingPathComponent("RawLayouts.swift")
            try source.write(to: sourceURL, atomically: true, encoding: .utf8)
            let libraryURL = workingDirectory.appendingPathComponent("lib\(moduleName).dylib")
            let output = try run(swiftcArguments: [
                "-O", "-emit-library", "-module-name", moduleName,
                "-enable-experimental-feature", "RawLayout",
                "-target", "arm64-apple-macos27.0",
                sourceURL.path, "-o", libraryURL.path,
            ])
            guard output.terminationStatus == 0 else { throw CompilationError(diagnostics: output.standardError) }
            return libraryURL
        }
    }()

    /// `xcrun swiftc -version` reports a Swift 6.4 or newer toolchain — the
    /// same toolchain `compilationResult` compiles the fixture with.
    static let compilesWithSwift64OrNewer: Bool = {
        guard let output = try? run(swiftcArguments: ["-version"]), output.terminationStatus == 0 else { return false }
        let combined = output.standardOutput + output.standardError
        guard let range = combined.range(of: #"Swift version (\d+)\.(\d+)"#, options: .regularExpression) else { return false }
        let components = combined[range].split(separator: " ").last?.split(separator: ".").compactMap { Int($0) } ?? []
        guard components.count == 2 else { return false }
        return components[0] > 6 || (components[0] == 6 && components[1] >= 4)
    }()

    private static func run(swiftcArguments: [String]) throws -> (terminationStatus: Int32, standardOutput: String, standardError: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["swiftc"] + swiftcArguments
        let standardOutputPipe = Pipe()
        let standardErrorPipe = Pipe()
        process.standardOutput = standardOutputPipe
        process.standardError = standardErrorPipe
        try process.run()
        // Drain before waiting, or a long diagnostic deadlocks both sides.
        let standardOutputData = standardOutputPipe.fileHandleForReading.readDataToEndOfFile()
        let standardErrorData = standardErrorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: standardOutputData, as: UTF8.self), String(decoding: standardErrorData, as: UTF8.self))
    }

    static func image() throws -> MachOFile {
        let libraryURL = try compilationResult.get()
        switch try File.loadFromFile(url: libraryURL) {
        case .machO(let machOFile):
            return machOFile
        case .fat(let fatFile):
            return try #require(try fatFile.machOFiles().first { $0.header.cpuType == .arm64 })
        }
    }
}

/// `@_rawLayout(size:alignment:)` and a non-generic `likeArrayOf:count:`
/// leave no field record, only a `__swift5_builtin` descriptor — the same
/// record an imported C struct gets — and the engine already reads those
/// before walking a struct's fields. Pinned here for a module that is not
/// the standard library: the experimental feature is anyone's to enable.
@Suite(.serialized)
struct RawLayoutBuiltinDescriptorTypeLayoutTests {
    private func resolveLayout(ofMangledType mangledTypeName: String) throws -> StaticTypeLayout {
        let universe = try ImageUniverse.singleImage(try RawLayoutBuiltinDescriptorFixture.image())
        let resolver = StaticTypeLayoutResolver(imageUniverse: universe)
        let typeNode = try demangleAsNode(mangledTypeName, isType: true)
        return try resolver.layout(forTypeNode: typeNode, in: universe.rootImage)
    }

    @Test func aSizeAndAlignmentStructTakesTheRecordedLayoutWithNoExtraInhabitants() throws {
        let layout = try resolveLayout(ofMangledType: "20ProbeRawLayoutLayout12OpaqueTwelveV")
        #expect(layout.size == 12)
        #expect(layout.stride == 12)
        #expect(layout.alignmentMask == 3)
        #expect(layout.extraInhabitantCount == 0)
        // No extra inhabitants means the Optional needs a tag byte — the
        // runtime's `MemoryLayout<OpaqueTwelve?>.size` is 13.
        #expect(try resolveLayout(ofMangledType: "20ProbeRawLayoutLayout12OpaqueTwelveVSg").size == 13)
    }

    @Test func aFixedArrayLikeStructIsSizedFromItsDescriptor() throws {
        let layout = try resolveLayout(ofMangledType: "20ProbeRawLayoutLayout9QuadWordsV")
        #expect(layout.size == 16)
        #expect(layout.alignmentMask == 3)
        #expect(layout.extraInhabitantCount == 0)
    }
}

/// A struct holding those types lays out exactly as the compiler did:
/// `Holder { tag: UInt8, opaque: OpaqueTwelve, quad: QuadWords, tail: UInt8 }`
/// is 33 bytes at 4-byte alignment (`MemoryLayout` measured with a Swift 6.4
/// toolchain).
@Suite(.serialized, .enabled(if: RawLayoutBuiltinDescriptorFixture.compilesWithSwift64OrNewer))
struct RawLayoutBuiltinDescriptorFieldOffsetTests {
    @Test func rawLayoutFieldsPlaceLikeAnyOtherStoredProperty() throws {
        let machO = try RawLayoutBuiltinDescriptorFixture.image()
        let qualifiedTypeName = "\(RawLayoutBuiltinDescriptorFixture.moduleName).Holder"
        var holderDescriptor: TypeContextDescriptorWrapper?
        for contextDescriptor in try machO.swift.contextDescriptors {
            guard let descriptor = contextDescriptor.typeContextDescriptorWrapper,
                  let name = (try? SymbolicDemangler.demangleContext(for: contextDescriptor, in: machO)).flatMap(NodeTypeNaming.nominalQualifiedName(of:)),
                  name == qualifiedTypeName
            else { continue }
            holderDescriptor = descriptor
            break
        }
        let calculator = try StaticLayoutCalculator(machO: machO)
        let aggregate = try calculator.fieldLayout(of: try #require(holderDescriptor, "no descriptor named \(qualifiedTypeName)"))

        #expect(aggregate.fields.map(\.fieldName) == ["tag", "opaque", "quad", "tail"])
        #expect(aggregate.computedFieldOffsets == [0, 4, 16, 32])
        #expect(aggregate.size == 33)
        #expect(aggregate.stride == 36)
        #expect(aggregate.alignment == 4)
        #expect(aggregate.extraInhabitantCount == 0)
    }
}
