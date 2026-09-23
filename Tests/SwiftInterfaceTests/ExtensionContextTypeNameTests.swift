import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
@_spi(Support) @testable import SwiftInterface

/// A type declared in an extension of another module's type is parented on an
/// extension context descriptor, so every name for it — the offline one from
/// `SymbolicDemangler` and the runtime's alike — carries an `extension` node:
/// `Structure(Extension(<extending module>, <extended type>), <name>)`.
///
/// The interface printer had no case for that node and printed it as nothing,
/// so every reference lost the extended type: the macOS 26.5.2 AppKit interface
/// reads `Invalidations.Tuple<A1, B1>` for `NSView.Invalidations.Tuple`. An
/// extension context now prints as the type it extends — what the Demangling
/// printer does too, minus the `(extension in <module>):` prefix a textual
/// interface cannot spell.
@Suite(.serialized)
struct ExtensionContextTypeNameTests {
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
        var description: String { "extension-context fixture compilation failed:\n\(diagnostics)" }
    }

    private static let fixtureCompilationResult: Result<URL, Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("ExtensionContextFixture-\(UUID().uuidString)")
            _ = FixtureWorkingDirectoryCleanup.registration
            FixtureWorkingDirectoryCleanup.directories.append(workingDirectory)
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            let sourceURL = workingDirectory.appendingPathComponent("ExtensionContexts.swift")
            try source.write(to: sourceURL, atomically: true, encoding: .utf8)
            let libraryURL = workingDirectory.appendingPathComponent("libProbeExtensionContext.dylib")
            try run(swiftcArguments: [
                "-O", "-emit-library", "-module-name", "ProbeExtensionContext",
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

    /// `FixtureAnchor` is ballast: a struct-only fixture dylib has no `__DATA`
    /// segment and the pinned MachOKit mis-walks its chained-fixup pages.
    /// `Holder` is what references the nested types, so their names are printed
    /// as references rather than as declarations inside an `extension` block.
    private static let source = """
    import Foundation

    public final class FixtureAnchor {}

    extension Int {
        public struct NestedInExtension {
            public init() {}
        }

        public struct GenericNestedInExtension<Element> {
            public init() {}
        }
    }

    extension NSObject {
        public struct NestedInObjCClassExtension {
            public init() {}
        }
    }

    public struct Holder {
        public init() {}
        public var nested = Int.NestedInExtension()
        public var genericNested = Int.GenericNestedInExtension<String>()
        public var object = NSObject()
        public var objcNested = NSObject.NestedInObjCClassExtension()
    }
    """

    private func renderInterface() async throws -> String {
        let libraryURL = try Self.fixtureCompilationResult.get()
        let machOFile: MachOFile
        switch try File.loadFromFile(url: libraryURL) {
        case .machO(let file):
            machOFile = file
        case .fat(let fatFile):
            machOFile = try #require(try fatFile.machOFiles().first { $0.header.cpuType == .arm64 })
        }
        let builder = try SwiftInterfaceBuilder(configuration: .init(), eventHandlers: [], in: machOFile)
        try await builder.prepare()
        return try await builder.printRoot().string
    }

    /// The printed type of the `Holder` property named `propertyName`.
    private func propertyType(named propertyName: String, in interface: String) -> String? {
        let prefix = "var \(propertyName): "
        guard let line = interface.split(separator: "\n").first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix) }) else { return nil }
        let afterPrefix = line.trimmingCharacters(in: .whitespaces).dropFirst(prefix.count)
        // Stored properties print bare; a trailing ` {` would open an accessor block.
        return String(afterPrefix.split(separator: " ").first ?? afterPrefix)
    }

    @Test("a type nested in another module's extension is named through the extended type")
    func typeInCrossModuleExtensionKeepsTheExtendedType() async throws {
        let interface = try await renderInterface()

        #expect(propertyType(named: "nested", in: interface) == "Swift.Int.NestedInExtension", "\(interface)")
    }

    @Test("a generic type nested in another module's extension keeps the extended type before its arguments")
    func genericTypeInCrossModuleExtensionKeepsTheExtendedType() async throws {
        let interface = try await renderInterface()

        #expect(propertyType(named: "genericNested", in: interface) == "Swift.Int.GenericNestedInExtension<Swift.String>", "\(interface)")
    }

    /// The AppKit shape (`extension NSView { enum Invalidations }`): the extended
    /// type is a C-imported class, whose module the printer may resolve, so the
    /// nested name must be spelled through whatever the class itself prints as.
    @Test("a type nested in an Objective-C class's extension is named through the class")
    func typeInObjectiveCClassExtensionKeepsTheClass() async throws {
        let interface = try await renderInterface()
        let classSpelling = try #require(propertyType(named: "object", in: interface), "\(interface)")

        #expect(propertyType(named: "objcNested", in: interface) == "\(classSpelling).NestedInObjCClassExtension", "\(interface)")
    }
}
