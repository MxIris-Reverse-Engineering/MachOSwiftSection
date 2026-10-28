import Foundation
import Testing
import MachO
import ObjCDiffing
import ObjCOutputTransformer
import OutputTransformer
import SwiftSectionKit

/// The `objc` requests against the SymbolTestsCore fixture, whose
/// `@objc`-exposed classes give it a small Objective-C side.
@Suite
struct ObjCRequestTests {
    private static let fixture = MachOSource.file(path: FixtureFiles.symbolTestsCore, architecture: nil)
    private static let bridgeClassName = "SymbolTestsCoreObjCBridgeClass"

    @Test("A filtered dump prints the matching declaration, each followed by an empty line")
    func filteredDump() async throws {
        let output = RecordingOutput()
        let outcome = try await ObjCDumpRequest(source: Self.fixture, kinds: [.classes], nameFilter: Self.bridgeClassName)
            .run(output: output)

        #expect(outcome.emittedCount == 1)
        #expect(output.printedProduct.hasPrefix("@interface SymbolTestsCoreObjCBridgeClass : NSObject {\n"))
        #expect(output.printedProduct.hasSuffix("@end\n\n"))
        #expect(output.diagnostics.isEmpty)
    }

    /// What lets a host write each declaration into a file of its own; the
    /// empty line after the piece is no declaration.
    @Test("A dump hands each declaration over with its kind and name")
    func dumpNamesEachDeclaration() async throws {
        let output = DeclarationRecordingOutput()
        try await ObjCDumpRequest(source: Self.fixture, kinds: [.classes], nameFilter: Self.bridgeClassName)
            .run(output: output)

        let declarationPieces = output.declarationPieces
        #expect(declarationPieces.map(\.declaration) == [.objc(.classes, name: Self.bridgeClassName)])
        #expect(declarationPieces.first?.declarationText?.hasPrefix("@interface SymbolTestsCoreObjCBridgeClass : NSObject {\n") == true)
        #expect(output.pieces.count == 2)
        #expect(output.pieces.last?.declaration == nil)
    }

    @Test("A kind asked for by name that is empty is noted, under the image description given")
    func emptyRequestedKindIsNoted() async throws {
        let derived = RecordingOutput()
        try await ObjCDumpRequest(source: Self.fixture, kinds: [.unions]).run(output: derived)
        #expect(derived.messages(of: .note) == ["no unions found in \(FixtureFiles.symbolTestsCore)"])

        let described = RecordingOutput()
        try await ObjCDumpRequest(source: Self.fixture, kinds: [.unions], imageDescription: "SymbolTestsCore").run(output: described)
        #expect(described.messages(of: .note) == ["no unions found in SymbolTestsCore"])
    }

    /// A custom ivar-offset wording on its own would otherwise be silently
    /// inert, since ivar offset comments are off by default.
    @Test("A custom ivar-offset comment turns ivar offset comments on")
    func ivarOffsetCommentImpliesTheComments() async throws {
        let withComment = RecordingOutput()
        try await ObjCInterfaceRequest(
            declarationName: Self.bridgeClassName,
            source: Self.fixture,
            ivarOffsetComment: Transformer.ObjCIvarOffset(isEnabled: true, template: "IVAR@${offset}", useHexadecimal: true)
        ).run(output: withComment)
        let withoutComment = RecordingOutput()
        try await ObjCInterfaceRequest(declarationName: Self.bridgeClassName, source: Self.fixture).run(output: withoutComment)

        #expect(withComment.printedProduct.contains("// IVAR@0x"))
        #expect(!withoutComment.printedProduct.contains("IVAR@"))
    }

    @Test("A declaration the binary does not have is an error naming it")
    func missingDeclaration() async throws {
        await #expect(throws: ObjCDeclarationLookupError.declarationNotFound("NoSuchDeclaration")) {
            try await ObjCInterfaceRequest(declarationName: "NoSuchDeclaration", source: Self.fixture).run(output: RecordingOutput())
        }
    }

    @Test("A binary diffed against its own snapshot breaks no API")
    func diffAgainstOwnSnapshot() async throws {
        let directoryURL = try FixtureFiles.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let documentPath = directoryURL.appendingPathComponent("baseline.json").path
        let snapshotOutput = RecordingOutput()
        let document = try await ObjCAPISnapshotRequest(source: .path(FixtureFiles.symbolTestsCore), label: "1.0", destination: .file(path: documentPath))
            .run(output: snapshotOutput, environment: .testing)
        #expect(document.provenance?.generatorVersion == "9.9.9")
        #expect(snapshotOutput.messages(of: .progress).last == "Snapshot written to \(documentPath)")

        let output = RecordingOutput()
        let outcome = try await ObjCAPIDiffRequest(old: .path(documentPath), new: .path(FixtureFiles.symbolTestsCore), report: .summary)
            .run(output: output, environment: .testing)
        #expect(!outcome.hasBreakingChange)
        #expect(output.printedProduct == "API-breaking: false · backward-compatible: true\n")
    }

    @Test("An ObjC evolution needs a label per input, checked before anything is loaded")
    func evolutionLabelCountIsCheckedFirst() async throws {
        await #expect(throws: ObjCAPIEvolutionError.labelCountMismatch(labelCount: 3, versionCount: 2)) {
            _ = try await ObjCAPIEvolutionRequest(inputs: [.path("/nonexistent/one"), .path("/nonexistent/two")], labels: ["a", "b", "c"])
                .run(output: RecordingOutput(), environment: .testing)
        }
    }

    @Test("An annotated ObjC evolution refuses a snapshot document before loading anything")
    func annotatedEvolutionRejectsADocument() async throws {
        let directoryURL = try FixtureFiles.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let documentPath = directoryURL.appendingPathComponent("baseline.json").path
        _ = try await ObjCAPISnapshotRequest(source: .path(FixtureFiles.symbolTestsCore), destination: .file(path: documentPath))
            .run(output: RecordingOutput(), environment: .testing)

        let output = RecordingOutput()
        await #expect(throws: SnapshotSourceError.binaryRequired(path: documentPath)) {
            _ = try await ObjCAPIEvolutionRequest(
                inputs: [.path(FixtureFiles.symbolTestsCore), .path(documentPath)],
                report: .annotatedInterface(availabilityAttributes: .none)
            ).run(output: output, environment: .testing)
        }
        #expect(output.events.isEmpty)
    }

    /// The copy names another platform than the fixture's macOS; a simulator
    /// counts as its device, and the names are the availability macros' own
    /// (`API_AVAILABLE(macCatalyst(…))`). Thrown after loading and before any
    /// indexing.
    @Test("Inputs naming different platforms leave no availability platform to infer", arguments: [
        (PLATFORM_IOSSIMULATOR, ["ios", "macos"]),
        (PLATFORM_TVOS, ["macos", "tvos"]),
        (PLATFORM_WATCHOSSIMULATOR, ["macos", "watchos"]),
        (PLATFORM_VISIONOSSIMULATOR, ["macos", "visionos"]),
        (PLATFORM_MACCATALYST, ["macCatalyst", "macos"]),
        (PLATFORM_DRIVERKIT, ["driverkit", "macos"]),
    ])
    func annotatedEvolutionRefusesConflictingPlatforms(buildPlatform: Int32, expectedPlatforms: [String]) async throws {
        let directoryURL = try FixtureFiles.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let copyPath = try FixtureFiles.makeCopy(of: FixtureFiles.symbolTestsCore, buildPlatform: buildPlatform, in: directoryURL)

        let output = RecordingOutput()
        await #expect(throws: ObjCAvailabilityPlatformInferenceError.conflictingPlatforms(expectedPlatforms)) {
            _ = try await ObjCAPIEvolutionRequest(
                inputs: [.path(FixtureFiles.symbolTestsCore), .path(copyPath)],
                report: .annotatedInterface(availabilityAttributes: .inferredPlatform)
            ).run(output: output, environment: .testing)
        }
        #expect(!output.messages(of: .progress).contains { $0.hasPrefix("Indexing") })
    }

    @Test("An input naming a platform the availability macros cannot spell leaves nothing to infer")
    func annotatedEvolutionRefusesAnUnspellablePlatform() async throws {
        let directoryURL = try FixtureFiles.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let copyPath = try FixtureFiles.makeCopy(of: FixtureFiles.symbolTestsCore, buildPlatform: PLATFORM_BRIDGEOS, in: directoryURL)

        let output = RecordingOutput()
        await #expect(throws: ObjCAvailabilityPlatformInferenceError.noPlatform(path: copyPath)) {
            _ = try await ObjCAPIEvolutionRequest(
                inputs: [.path(FixtureFiles.symbolTestsCore), .path(copyPath)],
                report: .annotatedInterface(availabilityAttributes: .inferredPlatform)
            ).run(output: output, environment: .testing)
        }
        #expect(!output.messages(of: .progress).contains { $0.hasPrefix("Indexing") })
    }
}
