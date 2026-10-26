import Foundation
import MachOKit
import MachOFoundation
import MachOSwiftSection
import Testing

/// An on-the-fly fixture for the declaration shapes Swift 6.4 introduced and
/// the readers once lost (evolution proposal
/// `borrow-accessors-and-suppressed-associated-types`):
///
/// - SE-0507 `borrow` / `mutate` accessors on a property, a subscript and a
///   protocol requirement. Such a member has no getter or setter symbol, only
///   `…vb` / `…vz`, and printed as nothing at all.
/// - SE-0503 associated types declared `~Copyable` / `~Escapable`. The binary
///   records the declaration only through an extension of the protocol whose
///   signature suppresses the default, and an extension gets that default
///   only for a PRIMARY associated type — so each suppressed primary
///   associated type comes with such an extension, while `Strategy` (not
///   primary: its extension's `where Strategy: ~Copyable` mangles to nothing)
///   and `UnprovenElementContainer.Element` (no extension at all) cannot be
///   told apart from a Copyable one. `Index` is the Copyable control.
///   `ConstrainedSuppressedElementContainer.Element` is both suppressed and
///   constrained, so with requirements printed on the associated types
///   (evolution proposal `protocol-requirement-placement`) the suppression
///   joins an inheritance clause that is already there.
///
/// Only a Swift 6.4 compiler builds this: 6.3 rejects the accessors as an
/// experimental feature it cannot enable in a production compiler. CI builds
/// with Xcode 26.6 and `SymbolTestsCore` must not change (it would move every
/// offset the ABI baselines pin), so the fixture is compiled here with the
/// first Swift 6.4 or newer toolchain found — the selected one, then any other
/// Xcode in `/Applications` — and a suite using it is enabled only when there
/// is one (`isAvailable`).
package enum Swift64DeclarationShapesFixture {
    package static let moduleName = "Swift64DeclarationShapesFixture"

    package static let source = """
    // MARK: - SE-0507 borrow / mutate accessors

    public struct BorrowedStorage {
        var stored: Int = 0

        public init() {}

        public var borrowedOnly: Int {
            borrow { stored }
        }

        public var borrowedAndMutated: Int {
            borrow { stored }
            mutate { &stored }
        }

        public var computed: Int {
            get { stored }
            set { stored = newValue }
        }

        public subscript(position: Int) -> Int {
            borrow { stored }
            mutate { &stored }
        }
    }

    public protocol BorrowRequirement {
        var element: Int { borrow mutate }
        var readOnlyElement: Int { borrow }
    }

    // MARK: - SE-0503 suppressed associated types

    public protocol SuppressedElementContainer<Element, View, Payload>: ~Copyable {
        associatedtype Element: ~Copyable
        associatedtype View: ~Escapable
        associatedtype Payload: ~Copyable & ~Escapable
        associatedtype Strategy: ~Copyable
        associatedtype Index

        func count() -> Int
    }

    extension SuppressedElementContainer where Self: ~Copyable, Element: ~Copyable {
        public func isEmpty() -> Bool { count() == 0 }
    }

    extension SuppressedElementContainer where View: ~Escapable {
        public func hasView() -> Bool { true }
    }

    extension SuppressedElementContainer where Payload: ~Copyable, Payload: ~Escapable {
        public static func payloadDescription() -> String { "" }
    }

    extension SuppressedElementContainer where Strategy: ~Copyable {
        public func strategyDescription() -> String { "" }
    }

    extension SuppressedElementContainer {
        public func describe() -> String { "\\(count())" }
    }

    public protocol UnprovenElementContainer {
        associatedtype Element: ~Copyable
    }

    public protocol SuppressibleMarker: ~Copyable {}

    public protocol ConstrainedSuppressedElementContainer<Element> {
        associatedtype Element: SuppressibleMarker & ~Copyable
    }

    extension ConstrainedSuppressedElementContainer where Element: ~Copyable {
        public func elementDescription() -> String { "" }
    }
    """

    package struct CompilationError: Swift.Error, CustomStringConvertible {
        package let diagnostics: String
        package var description: String { "\(moduleName) fixture compilation failed:\n\(diagnostics)" }
    }

    /// Whether a Swift 6.4 or newer toolchain exists to compile the fixture.
    package static var isAvailable: Bool {
        toolchain != nil
    }

    /// The developer directory of the toolchain the fixture compiles with —
    /// `nil` for the selected one, which `xcrun` uses with no `DEVELOPER_DIR`.
    private struct Toolchain: Sendable {
        let developerDirectory: String?
    }

    private static let toolchain: Toolchain? = {
        let candidates: [String?] = [nil] + installedDeveloperDirectories()
        return candidates.lazy
            .filter { swiftVersion(developerDirectory: $0).map { $0 >= (6, 4) } ?? false }
            .map { Toolchain(developerDirectory: $0) }
            .first
    }()

    private static func installedDeveloperDirectories() -> [String] {
        let applicationsURL = URL(fileURLWithPath: "/Applications")
        let applicationNames = (try? FileManager.default.contentsOfDirectory(atPath: applicationsURL.path)) ?? []
        return applicationNames
            .filter { $0.hasPrefix("Xcode") && $0.hasSuffix(".app") }
            .sorted()
            .map { applicationsURL.appendingPathComponent($0).appendingPathComponent("Contents/Developer").path }
            .filter { FileManager.default.fileExists(atPath: $0) }
    }

    /// The `(major, minor)` of `swiftc -version` under `developerDirectory`.
    private static func swiftVersion(developerDirectory: String?) -> (Int, Int)? {
        guard let output = try? run(["swiftc", "-version"], developerDirectory: developerDirectory, capturesStandardOutput: true) else { return nil }
        guard let range = output.range(of: #"Swift version (\d+)\.(\d+)"#, options: .regularExpression) else { return nil }
        let numbers = output[range].dropFirst("Swift version ".count).split(separator: ".").compactMap { Int($0) }
        guard numbers.count == 2 else { return nil }
        return (numbers[0], numbers[1])
    }

    @discardableResult
    private static func run(_ arguments: [String], developerDirectory: String?, capturesStandardOutput: Bool = false) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = arguments
        if let developerDirectory {
            // `swift test` hands the test process its own toolchain's
            // `SDKROOT` and `DYLD_FRAMEWORK_PATH` (PrivateFrameworks included);
            // inherited, they make another Xcode's `xcodebuild -find` load the
            // wrong private frameworks and `xcrun` fail with exit 72.
            var environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("DYLD_") && $0.key != "SDKROOT" }
            environment["DEVELOPER_DIR"] = developerDirectory
            process.environment = environment
        }
        let outputPipe = Pipe()
        if capturesStandardOutput {
            process.standardOutput = outputPipe
        }
        process.standardError = outputPipe
        try process.run()
        // Drain BEFORE waitUntilExit, or a long diagnostic deadlocks both sides.
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: outputData, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw CompilationError(diagnostics: output)
        }
        return output
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

    /// Compiled once per process.
    private static let compilationResult: Result<URL, Swift.Error> = {
        Result {
            guard let toolchain else {
                throw CompilationError(diagnostics: "no Swift 6.4 or newer toolchain is installed")
            }
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(moduleName)-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            _ = WorkingDirectoryCleanup.registration
            WorkingDirectoryCleanup.directories.append(workingDirectory)

            let sourceURL = workingDirectory.appendingPathComponent("Fixture.swift")
            let libraryURL = workingDirectory.appendingPathComponent("lib\(moduleName).dylib")
            try source.write(to: sourceURL, atomically: true, encoding: .utf8)
            try run([
                // The language mode pinned, so a newer toolchain compiles the
                // source the same way. Library evolution keeps the protocol
                // requirements resilient, the way a framework ships them.
                "swiftc", "-swift-version", "6", "-Onone", "-emit-library", "-enable-library-evolution",
                "-module-name", moduleName,
                sourceURL.path, "-o", libraryURL.path,
            ], developerDirectory: toolchain.developerDirectory)
            return libraryURL
        }
    }()

    package static func machOFile() throws -> MachOFile {
        switch try MachOKit.loadFromFile(url: try compilationResult.get()) {
        case .machO(let machOFile):
            return machOFile
        case .fat(let fatFile):
            let machOFile = try fatFile.machOFiles().first { $0.header.cpuType == .arm64 }
            return try #require(machOFile, "fixture unexpectedly missing an arm64 slice")
        }
    }
}
