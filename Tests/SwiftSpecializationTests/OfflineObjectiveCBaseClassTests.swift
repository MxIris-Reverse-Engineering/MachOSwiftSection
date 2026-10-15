@_spi(Support) @testable import SwiftSpecialization
@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
import Foundation
import Testing
import MachOKit
@testable import MachOSwiftSection
import MachOTestingSupport

/// A base-class requirement on an Objective-C class, checked offline
/// (evolution proposal `offline-generic-specialization`).
///
/// The offline check reads class hierarchies from the indexed images, and
/// those hold Swift classes only: a Swift class whose superclass is an
/// Objective-C class other than the base — `FixtureOperation: Operation`
/// under an `NSObject` bound — has no indexed link up to the base. The check
/// took that for proof of a violation and rejected the selection, while the
/// runtime accepts it. A chain that leaves the indexed classes is evidence the
/// file does not carry; `staticPreflight` promises a warning for that, never
/// an error. Cocoa bounds — `NSObject`, `NSView`, `UIViewController` — are
/// the most common base-class bounds there are.
@Suite(.serialized)
struct OfflineObjectiveCBaseClassTests {
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
        var description: String { "Objective-C base-class fixture compilation failed:\n\(diagnostics)" }
    }

    private static let moduleName = "ObjectiveCBaseClassFixture"

    private static let fixtureSource = """
    import Foundation

    public final class FixtureOperation: Operation {}

    public final class FixtureObject: NSObject {}

    public struct ObjectBound<Subject: NSObject> {
        public var subject: Subject
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
                "swiftc", "-swift-version", "5", "-emit-library", "-module-name", moduleName,
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

    /// The offline specializer over the fixture file, the request for
    /// `ObjectBound`, and the candidate for the fixture class `className`.
    /// The candidate is built from the indexer's definition rather than taken
    /// from the request: the request's list is narrowed by the same indexed
    /// hierarchy, so a class below an Objective-C intermediate is not on it.
    private func offlineSelection(ofClassNamed className: String) async throws -> (specializer: GenericSpecializer<MachOFile>, request: SpecializationRequest, candidate: SpecializationRequest.Candidate) {
        let indexer = SwiftDeclarationIndexer(in: try loadFixtureMachOFile())
        try await indexer.prepare()
        let boundDefinition = try #require(indexer.allTypeDefinitions.values.first { $0.typeName.declaredNameForTesting == "ObjectBound" })
        let classDefinition = try #require(indexer.allTypeDefinitions.values.first { $0.typeName.declaredNameForTesting == className })
        let specializer = GenericSpecializer(indexer: indexer)
        let request = try specializer.makeRequest(for: boundDefinition.typeContextDescriptorWrapper)
        return (specializer, request, .init(typeName: classDefinition.typeName, source: .image(Self.moduleName)))
    }

    @Test("a Swift class below an Objective-C intermediate is not a base-class violation")
    func swiftClassBelowAnObjectiveCIntermediateIsNotAViolation() async throws {
        let (specializer, request, operation) = try await offlineSelection(ofClassNamed: "FixtureOperation")

        let validation = specializer.staticPreflight(selection: ["A": .candidate(operation)], for: request)

        #expect(validation.isValid, "\(validation.errors)")
    }

    @Test("a Swift class below an Objective-C intermediate specializes offline")
    func swiftClassBelowAnObjectiveCIntermediateSpecializes() async throws {
        let (specializer, request, operation) = try await offlineSelection(ofClassNamed: "FixtureOperation")

        let result = try specializer.specialize(request, with: ["A": .candidate(operation)])

        #expect(result.typeName.name(using: .default) == "\(Self.moduleName).ObjectBound<\(Self.moduleName).FixtureOperation>")
    }
}
