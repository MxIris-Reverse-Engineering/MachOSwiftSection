import Foundation
import MachOKit
import Testing

/// An on-the-fly fixture for the export verdict of types declared in
/// extensions of another module's types, in images that keep no symbol at a
/// non-exported descriptor (evolution proposal
/// `export-verdict-without-local-symbols`).
///
/// Every type nested in such an extension runs through an extension context
/// — the shape every Swift type nested in an Objective-C class has
/// (`(extension in AppKit):__C.NSView`). Without a symbol at the descriptor,
/// its verdict comes from remangling its name, which the remangling leg used
/// to refuse for any extension context. The module declares, in an
/// unconstrained extension of `Int` and of `NSObject` and in a constrained
/// extension of its own generic type, one public, one internal and one
/// private type each, plus a type nested in a private one, a protocol and a
/// local type. It also declares a public and a private `@objc` protocol,
/// which have no descriptor at all, and two categories of Foundation
/// classes: one adopting only the private protocol, one adopting both. It is
/// compiled without `-enable-testing`, so every internal and private
/// descriptor is a local symbol, in three variants:
///
/// - `.unstripped`: every symbol — leg 1 rules on every descriptor, which
///   makes it the reference the other two are compared with.
/// - `.symbolicReferencesOnly`: the exported and imported symbols plus the
///   `_symbolic` ones — the shape of AppKit in the macOS 27.2 dyld shared
///   cache, where private discriminators are still recovered but no
///   non-exported descriptor carries a symbol.
/// - `.stripped` (`strip -x`): the exported and imported symbols only — a
///   stripped app, where private types are named by position.
///
/// `strip -s <the symbols to keep>` cuts the middle variant: no strip option
/// removes chosen local symbols, and `strip -s` keeps a local symbol only
/// when it was a private external before linking, as the `_symbolic` ones
/// are. Stripping invalidates the linker's ad-hoc signature, so every
/// variant is re-signed. Each variant is compiled on its own, under a module
/// name of its own: the per-image caches key a file by its `LC_UUID`, which
/// copies of one build share, so a stripped copy would be answered from the
/// unstripped one's symbol index.
package enum ExtensionContextExportFixture {
    package enum Variant: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case unstripped
        case symbolicReferencesOnly
        case stripped

        /// The variants that keep no symbol at a non-exported descriptor.
        package static let withoutLocalDescriptorSymbols: [Variant] = [.symbolicReferencesOnly, .stripped]

        package var testDescription: String { rawValue }

        package var moduleName: String {
            switch self {
            case .unstripped: "ExtensionContextExportFixtureUnstripped"
            case .symbolicReferencesOnly: "ExtensionContextExportFixtureSymbolicReferencesOnly"
            case .stripped: "ExtensionContextExportFixtureStripped"
            }
        }
    }

    /// The `ExclusiveImageAccess` key every suite touching these images
    /// declares.
    package static let exclusiveAccessName = "ExtensionContextExportFixture"

    package static let source = """
    import Foundation

    extension Int {
        public struct PublicNestedInExtension {
            public init() {}
        }
        struct InternalNestedInExtension {}
        private struct PrivateNestedInExtension {
            struct NestedInPrivateType {}
        }
        protocol InternalProtocolNestedInExtension {}
        @inline(never) func makeLocalTypeValue() -> Any {
            struct LocalTypeInExtension {}
            return LocalTypeInExtension()
        }
    }

    extension NSObject {
        public struct PublicNestedInObjCClassExtension {
            public init() {}
        }
        struct InternalNestedInObjCClassExtension {}
        private final class PrivateNestedInObjCClassExtension {}
    }

    public struct GenericBox<Element> {
        public var element: Element
        public init(element: Element) { self.element = element }
    }

    extension GenericBox where Element == Int {
        public struct PublicNestedInConstrainedExtension {
            public init() {}
        }
        struct InternalNestedInConstrainedExtension {}
        private struct PrivateNestedInConstrainedExtension {}
    }

    @objc public protocol PublicObjCProtocol {
        func publicObjCRequirement()
    }

    @objc private protocol PrivateObjCProtocol {
        func privateObjCRequirement()
    }

    extension NumberFormatter: PrivateObjCProtocol {
        func privateObjCRequirement() {}
    }

    extension ByteCountFormatter: PrivateObjCProtocol, PublicObjCProtocol {
        func privateObjCRequirement() {}
        public func publicObjCRequirement() {}
    }
    """

    package struct CompilationError: Swift.Error, CustomStringConvertible {
        package let step: String
        package let diagnostics: String
        package var description: String { "ExtensionContextExportFixture step \(step) failed:\n\(diagnostics)" }
    }

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

    /// Compiled once per process; every variant shares one working directory.
    private static let compilationResult: Result<[Variant: URL], Swift.Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("ExtensionContextExportFixture-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            _ = WorkingDirectoryCleanup.registration
            WorkingDirectoryCleanup.directories.append(workingDirectory)

            let sourceURL = workingDirectory.appendingPathComponent("Fixture.swift")
            try source.write(to: sourceURL, atomically: true, encoding: .utf8)

            var libraries: [Variant: URL] = [:]
            for variant in Variant.allCases {
                let libraryURL = workingDirectory.appendingPathComponent("lib\(variant.moduleName).dylib")
                // The language mode pinned: CI's toolchain and a newer local
                // one must compile the same source the same way.
                try run(step: "swiftc (\(variant.rawValue))", [
                    "swiftc", "-swift-version", "5", "-emit-library", "-Onone", "-module-name", variant.moduleName,
                    sourceURL.path, "-o", libraryURL.path,
                ])
                switch variant {
                case .unstripped:
                    break
                case .symbolicReferencesOnly:
                    try strip(libraryURL, keepingLocalSymbolsWhere: { $0.hasPrefix("_symbolic") }, in: workingDirectory, variant: variant)
                case .stripped:
                    try run(step: "strip (\(variant.rawValue))", ["strip", "-x", libraryURL.path])
                }
                try run(step: "codesign (\(variant.rawValue))", ["codesign", "--force", "--sign", "-", libraryURL.path])
                libraries[variant] = libraryURL
            }
            return libraries
        }
    }()

    /// Strips every local symbol but those `isKept` selects. The global ones
    /// stay: `-g` lists the imported symbols too, which the indirect symbol
    /// table refers to and `strip -s` refuses to drop.
    private static func strip(_ libraryURL: URL, keepingLocalSymbolsWhere isKept: (String) -> Bool, in directory: URL, variant: Variant) throws {
        let globalSymbolNames = try symbolNames(of: libraryURL, globalOnly: true, step: "nm -g (\(variant.rawValue))")
        let keptLocalSymbolNames = try symbolNames(of: libraryURL, globalOnly: false, step: "nm (\(variant.rawValue))").filter(isKept)
        let keepListURL = directory.appendingPathComponent("keep-\(variant.rawValue).txt")
        try ((globalSymbolNames + keptLocalSymbolNames).joined(separator: "\n") + "\n").write(to: keepListURL, atomically: true, encoding: .utf8)
        try run(step: "strip -s (\(variant.rawValue))", ["strip", "-s", keepListURL.path, libraryURL.path])
    }

    private static func symbolNames(of libraryURL: URL, globalOnly: Bool, step: String) throws -> [String] {
        let output = try run(step: step, ["nm", globalOnly ? "-gj" : "-j", libraryURL.path])
        return output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    /// Runs `xcrun <arguments>` and returns its standard output. Standard
    /// error goes to a file rather than a pipe, so neither stream can fill
    /// while the other is drained.
    @discardableResult
    private static func run(step: String, _ arguments: [String]) throws -> String {
        let diagnosticsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExtensionContextExportFixture-diagnostics-\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: diagnosticsURL.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: diagnosticsURL) }
        let diagnosticsHandle = try FileHandle(forWritingTo: diagnosticsURL)
        defer { try? diagnosticsHandle.close() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = arguments
        let standardOutputPipe = Pipe()
        process.standardOutput = standardOutputPipe
        process.standardError = diagnosticsHandle
        try process.run()
        // Drain BEFORE waitUntilExit, or a long output deadlocks both sides.
        let outputData = standardOutputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let diagnostics = (try? String(contentsOf: diagnosticsURL, encoding: .utf8)) ?? ""
            throw CompilationError(step: step, diagnostics: diagnostics)
        }
        return String(decoding: outputData, as: UTF8.self)
    }

    package static func machOFile(_ variant: Variant) throws -> MachOFile {
        let libraries = try compilationResult.get()
        let libraryURL = try #require(libraries[variant], "no library for variant \(variant.rawValue)")
        switch try MachOKit.loadFromFile(url: libraryURL) {
        case .machO(let machOFile):
            return machOFile
        case .fat(let fatFile):
            let machOFile = try fatFile.machOFiles().first { $0.header.cpuType == .arm64 }
            return try #require(machOFile, "fixture unexpectedly missing an arm64 slice")
        }
    }
}
