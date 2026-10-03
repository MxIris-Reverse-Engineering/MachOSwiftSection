import Foundation
import Testing
import SwiftDiffing
import SwiftSectionKit

/// `snapshot`, `diff` and `evolution` against the SymbolTestsCore fixture:
/// what each produces, how a snapshot document and a binary mix as inputs,
/// and the verdict a CI gate reads.
@Suite
struct ABIRequestTests {
    private static let fixture = SnapshotSource.path(FixtureFiles.symbolTestsCore)

    /// The fixture indexed once for the whole suite: every test that only
    /// needs a snapshot document starts from this one instead of indexing the
    /// fixture again.
    private static let fixtureDocument = Task {
        try await ABISnapshotRequest(source: fixture).run(output: RecordingOutput(), environment: .testing)
    }

    /// Writes the fixture's snapshot document, labeled `label`, into
    /// `directoryURL`.
    private func writeFixtureSnapshot(named fileName: String, label: String?, in directoryURL: URL) async throws -> String {
        var document = try await Self.fixtureDocument.value
        document.provenance?.label = label
        let path = directoryURL.appendingPathComponent(fileName).path
        try document.encoded().write(to: URL(fileURLWithPath: path))
        return path
    }

    // MARK: - snapshot

    @Test("A snapshot's provenance is stamped from the request and the environment")
    func snapshotProvenance() async throws {
        let output = RecordingOutput()
        let document = try await ABISnapshotRequest(source: Self.fixture, label: "1.0").run(output: output, environment: .testing)

        let provenance = try #require(document.provenance)
        #expect(provenance.label == "1.0")
        #expect(provenance.binaryPath == FixtureFiles.symbolTestsCore)
        #expect(provenance.generatorVersion == "9.9.9")
        #expect(provenance.createdAt == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(output.messages(of: .progress) == ["Indexing \(FixtureFiles.symbolTestsCore)…"])
        #expect(output.indexingLabels == ["1.0"])
    }

    @Test("The product is the document's JSON, which reads back as the document")
    func snapshotProductIsTheDocument() async throws {
        let output = RecordingOutput()
        let document = try await ABISnapshotRequest(source: Self.fixture).run(output: output, environment: .testing)

        guard case .data(let data)? = output.products.first, output.products.count == 1 else {
            Issue.record("expected one data product, got \(output.products)")
            return
        }
        #expect(try ABISnapshotDocument.decode(from: data) == document)
    }

    @Test("A snapshot document as input is relabeled, not re-indexed")
    func snapshotRelabelsADocument() async throws {
        let directoryURL = try FixtureFiles.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let documentPath = try await writeFixtureSnapshot(named: "baseline.json", label: "before", in: directoryURL)

        let output = RecordingOutput()
        let relabeled = try await ABISnapshotRequest(source: .path(documentPath), label: "after").run(output: output, environment: .testing)

        #expect(relabeled.provenance?.label == "after")
        #expect(output.messages(of: .progress) == ["Reading snapshot \(documentPath)…"])
        #expect(output.indexingLabels.isEmpty)
    }

    @Test("A file destination says where the snapshot went")
    func snapshotFileDestination() async throws {
        let directoryURL = try FixtureFiles.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let path = directoryURL.appendingPathComponent("snapshot.json").path

        let output = RecordingOutput()
        let document = try await ABISnapshotRequest(source: Self.fixture, destination: .file(path: path)).run(output: output, environment: .testing)

        #expect(output.products.isEmpty)
        #expect(output.messages(of: .progress).last == "Snapshot written to \(path)")
        #expect(try ABISnapshotDocument.decode(from: Data(contentsOf: URL(fileURLWithPath: path))) == document)
    }

    // MARK: - diff

    @Test("A binary diffed against its own snapshot has no change")
    func diffAgainstOwnSnapshot() async throws {
        let directoryURL = try FixtureFiles.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let documentPath = try await writeFixtureSnapshot(named: "baseline.json", label: nil, in: directoryURL)

        let output = RecordingOutput()
        let outcome = try await ABIDiffRequest(old: .path(documentPath), new: Self.fixture, report: .summary)
            .run(output: output, environment: .testing)

        #expect(outcome.hasBreakingChange == false)
        #expect(output.printedProduct == "ABI-breaking: false · backward-compatible: true\n")
        #expect(output.indexingLabels == ["new"])
    }

    /// The summary line has always gone to stdout even with `-o`.
    @Test("The summary reaches the output even with a file destination")
    func diffSummaryIgnoresTheFileDestination() async throws {
        let directoryURL = try FixtureFiles.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let documentPath = try await writeFixtureSnapshot(named: "baseline.json", label: nil, in: directoryURL)
        let reportPath = directoryURL.appendingPathComponent("report.txt").path

        let output = RecordingOutput()
        _ = try await ABIDiffRequest(old: .path(documentPath), new: .path(documentPath), report: .summary, destination: .file(path: reportPath))
            .run(output: output, environment: .testing)

        #expect(output.printedProduct == "ABI-breaking: false · backward-compatible: true\n")
        #expect(!FileManager.default.fileExists(atPath: reportPath))
    }

    @Test("The change list ends with the verdict, and a file gets it without the trailing newline")
    func diffChangeListFileDestination() async throws {
        let directoryURL = try FixtureFiles.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let documentPath = try await writeFixtureSnapshot(named: "baseline.json", label: nil, in: directoryURL)
        let reportPath = directoryURL.appendingPathComponent("report.txt").path

        let printed = RecordingOutput()
        _ = try await ABIDiffRequest(old: .path(documentPath), new: .path(documentPath)).run(output: printed, environment: .testing)
        let written = RecordingOutput()
        _ = try await ABIDiffRequest(old: .path(documentPath), new: .path(documentPath), destination: .file(path: reportPath))
            .run(output: written, environment: .testing)

        #expect(printed.printedProduct.hasSuffix("\n\nABI-breaking: false · backward-compatible: true\n"))
        #expect(try String(contentsOfFile: reportPath, encoding: .utf8) + "\n" == printed.printedProduct)
        #expect(written.messages(of: .progress).last == "Report written to \(reportPath)")
    }

    @Test("An annotated interface refuses a snapshot document before indexing anything")
    func annotatedDiffRejectsADocument() async throws {
        let directoryURL = try FixtureFiles.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let documentPath = try await writeFixtureSnapshot(named: "baseline.json", label: nil, in: directoryURL)

        let output = RecordingOutput()
        await #expect(throws: SnapshotSourceError.binaryRequired(path: documentPath)) {
            _ = try await ABIDiffRequest(
                old: Self.fixture,
                new: .path(documentPath),
                report: .annotatedInterface(format: .inline, includesBreakingChangeVerdict: false)
            ).run(output: output, environment: .testing)
        }
        #expect(output.events.isEmpty)
    }

    @Test("An annotated interface computes the verdict only when asked")
    func annotatedDiffVerdictIsOptional() async throws {
        let withoutVerdict = try await ABIDiffRequest(
            old: Self.fixture,
            new: Self.fixture,
            report: .annotatedInterface(format: .unified, includesBreakingChangeVerdict: false),
            maximumConcurrentPreparations: 1
        ).run(output: RecordingOutput(), environment: .testing)
        #expect(withoutVerdict.diff == nil)

        let output = RecordingOutput()
        let withVerdict = try await ABIDiffRequest(
            old: Self.fixture,
            new: Self.fixture,
            report: .annotatedInterface(format: .unified, includesBreakingChangeVerdict: true),
            maximumConcurrentPreparations: 1
        ).run(output: output, environment: .testing)
        #expect(withVerdict.hasBreakingChange == false)
        #expect(output.messages(of: .progress) == ["Indexing old binary, then new binary…", "Rendering annotated interface…"])
        #expect(output.indexingLabels == ["old", "new"])
        guard case .annotatedInterface(_, let style)? = output.products.first, output.products.count == 1 else {
            Issue.record("expected one annotated interface, got \(output.products)")
            return
        }
        #expect(style == .diff(isUnifiedDiff: true))
    }

    // MARK: - evolution

    @Test("A label per input is required, and checked before anything is loaded")
    func evolutionLabelCountIsCheckedFirst() async throws {
        await #expect(throws: ABIEvolutionError.labelCountMismatch(labelCount: 1, versionCount: 2)) {
            _ = try await ABIEvolutionRequest(inputs: [.path("/nonexistent/one"), .path("/nonexistent/two")], labels: ["1.0"])
                .run(output: RecordingOutput(), environment: .testing)
        }
    }

    @Test("A lineage of identical versions breaks nothing, labeled by stored label or file name")
    func evolutionLineage() async throws {
        let directoryURL = try FixtureFiles.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let firstPath = try await writeFixtureSnapshot(named: "first.json", label: "1.0", in: directoryURL)
        let secondPath = try await writeFixtureSnapshot(named: "second.json", label: nil, in: directoryURL)

        let output = RecordingOutput()
        let outcome = try await ABIEvolutionRequest(inputs: [.path(firstPath), .path(secondPath)], report: .json)
            .run(output: output, environment: .testing)

        let evolution = try #require(outcome.evolution)
        #expect(!outcome.hasBreakingChange)
        #expect(evolution.versions.map(\.label) == ["1.0", "second.json"])
        #expect(output.messages(of: .progress).last == "Tracking evolution…")
    }

    @Test("The lineage report holds the same bytes printed and in a file")
    func evolutionFileDestination() async throws {
        let directoryURL = try FixtureFiles.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let documentPath = try await writeFixtureSnapshot(named: "baseline.json", label: nil, in: directoryURL)
        let reportPath = directoryURL.appendingPathComponent("lineage.txt").path
        let inputs: [SnapshotSource] = [.path(documentPath), .path(documentPath)]

        let printed = RecordingOutput()
        _ = try await ABIEvolutionRequest(inputs: inputs, labels: ["a", "b"]).run(output: printed, environment: .testing)
        _ = try await ABIEvolutionRequest(inputs: inputs, labels: ["a", "b"], destination: .file(path: reportPath))
            .run(output: RecordingOutput(), environment: .testing)

        #expect(try String(contentsOfFile: reportPath, encoding: .utf8) == printed.printedProduct)
    }

    @Test("An annotated evolution refuses a snapshot document")
    func annotatedEvolutionRejectsADocument() async throws {
        let directoryURL = try FixtureFiles.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let documentPath = try await writeFixtureSnapshot(named: "baseline.json", label: nil, in: directoryURL)

        await #expect(throws: SnapshotSourceError.binaryRequired(path: documentPath)) {
            _ = try await ABIEvolutionRequest(inputs: [Self.fixture, .path(documentPath)], report: .annotatedInterface)
                .run(output: RecordingOutput(), environment: .testing)
        }
    }
}
