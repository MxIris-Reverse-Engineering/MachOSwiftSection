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
}
