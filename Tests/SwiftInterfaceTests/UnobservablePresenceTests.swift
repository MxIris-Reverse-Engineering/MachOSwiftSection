import Foundation
import Testing
import MachOKit
import SwiftDiffing
import SwiftInterface
@testable import MachOTestingSupport

/// Telling a declaration a version cannot show from one that is gone
/// (evolution proposal `evolution-unobservable-presence`), over
/// `UnobservablePresenceFixture`'s three compiled versions, the middle one
/// stripped of its local symbols.
@Suite(.serialized)
struct UnobservablePresenceTests {
    private static let panelName = "\(UnobservablePresenceFixture.moduleName).Panel"

    private func snapshots() async throws -> [ABISnapshot] {
        var snapshots: [ABISnapshot] = []
        for machOFile in try UnobservablePresenceFixture.machOFiles() {
            let builder = SwiftDiffableInterfaceBuilder(in: machOFile)
            try await builder.prepare()
            snapshots.append(builder.snapshot())
        }
        return snapshots
    }

    private func panelMembers(in snapshot: ABISnapshot) throws -> [MemberRecord] {
        try #require(snapshot.types.first { $0.name == Self.panelName }).members
    }

    // MARK: - Snapshot facts

    @Test("a snapshot records whether its image keeps local Swift symbols")
    func snapshotsRecordLocalSwiftSymbols() async throws {
        let hasLocalSwiftSymbols = try await snapshots().map(\.hasLocalSwiftSymbols)
        #expect(hasLocalSwiftSymbols == [true, false, true])
    }

    @Test("a snapshot records each symbol-backed member's export verdict")
    func snapshotsRecordExportVerdicts() async throws {
        let members = try panelMembers(in: try await snapshots()[0])
        let layout = try #require(members.first { $0.kind == .function && $0.signature.contains(".layout()") })
        let render = try #require(members.first { $0.kind == .function && $0.signature.contains(".render()") })
        let title = try #require(members.first { $0.kind == .field })
        #expect(layout.isExported == false)
        #expect(render.isExported == true)
        // A stored field is read from the field descriptor, not a symbol.
        #expect(title.isExported == nil)
    }

    @Test("the stripped version shows the public members and none of the internal ones")
    func strippedVersionHidesInternalMembers() async throws {
        let signatures = try panelMembers(in: try await snapshots()[UnobservablePresenceFixture.strippedVersionIndex]).map(\.signature)
        #expect(signatures.contains { $0.contains(".render()") })
        #expect(!signatures.contains { $0.contains(".layout()") })
    }

    // MARK: - Annotated evolution interface

    private func interfaceLines() async throws -> [String] {
        let builder = try AnySwiftEvolutionInterfaceBuilder(
            versions: try UnobservablePresenceFixture.machOFiles(),
            labels: UnobservablePresenceFixture.labels,
            availabilityAnnotationPlatform: "macOS"
        )
        try await builder.prepare()
        return try await builder.printAnnotatedInterface().string.components(separatedBy: "\n")
    }

    private func lineIndex(containing fragment: String, in lines: [String]) throws -> Int {
        try #require(lines.firstIndex { $0.contains(fragment) }, "no line contains \(fragment)")
    }

    @Test("the legend names the version without local Swift symbols")
    func legendNamesTheStrippedVersion() async throws {
        let lines = try await interfaceLines()
        #expect(lines.contains { $0.hasPrefix("// 2.0 carries no local Swift symbols") })
    }

    @Test("an internal member present on both sides of the stripped version is inferred present there")
    func internalMemberIsInferredPresent() async throws {
        let lines = try await interfaceLines()
        #expect(lines[try lineIndex(containing: "func layout()", in: lines)].contains("// [●◍●] inferred present in 2.0"))
    }

    @Test("an internal member's removal and addition are placed between the versions that saw them, without @available")
    func internalChangesArePlacedBetweenObservations() async throws {
        let lines = try await interfaceLines()
        let removedIndex = try lineIndex(containing: "func legacyLayout()", in: lines)
        let addedIndex = try lineIndex(containing: "func freshLayout()", in: lines)
        #expect(lines[removedIndex].contains("// [●◌○] removed between 1.0 and 3.0"))
        #expect(lines[addedIndex].contains("// [○◌●] added between 1.0 and 3.0"))
        #expect(!lines[removedIndex - 1].contains("@available"))
        #expect(!lines[addedIndex - 1].contains("@available"))
    }

    @Test("a public member's removal stays exact in the stripped version")
    func publicRemovalStaysExact() async throws {
        let lines = try await interfaceLines()
        let retiredIndex = try lineIndex(containing: "func retiredRender()", in: lines)
        #expect(lines[retiredIndex].contains("// [●○○] removed in 2.0"))
        #expect(lines[retiredIndex - 1].contains("@available(macOS, obsoleted: 2.0)"))
    }

    @Test("an extension of internal members alone is inferred present, its members with it")
    func internalExtensionIsInferredPresent() async throws {
        let lines = try await interfaceLines()
        #expect(lines[try lineIndex(containing: "extension Swift.Int", in: lines)].contains("// [●◍●] inferred present in 2.0"))
        // The container's annotation tells the member's story, as it does for
        // the members of an added or removed container.
        #expect(!lines[try lineIndex(containing: "func panelScale()", in: lines)].contains("// ["))
    }
}
