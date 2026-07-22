@testable import SwiftDiffing
import Testing
import Foundation

// MARK: - Identity-key collision surfacing

@Suite("ABIKeyCollision scanning and surfacing")
struct ABIDiagnosticsTests {
    private func record(_ identity: String, payload: String? = nil, signature: String? = nil) -> MemberRecord {
        MemberRecord(
            identityKey: .mangled(identity),
            payloadKey: .mangled(payload ?? identity),
            kind: .function,
            signature: signature ?? identity
        )
    }

    private func container(_ name: String, members: [MemberRecord] = []) -> ContainerSnapshot {
        ContainerSnapshot(key: .printed(name), name: name, kind: .type, members: members)
    }

    @Test("a clean snapshot reports no collisions")
    func cleanSnapshot() {
        let snapshot = ABISnapshot(
            types: [container("Foo", members: [record("a"), record("b")])],
            globalFunctions: [record("g")]
        )
        #expect(snapshot.keyCollisions().isEmpty)
    }

    @Test("duplicate member identities within one container are reported with the dropped signatures")
    func memberCollision() {
        // The realistic shape: a merged extension bucket flattening two
        // conditional extensions' same-identity members into one scope.
        let snapshot = ABISnapshot(typeExtensions: [container("Foo", members: [
            record("m", payload: "whereP", signature: "kept()"),
            record("m", payload: "whereQ", signature: "dropped()"),
        ])])
        let collisions = snapshot.keyCollisions()
        #expect(collisions == [ABIKeyCollision(
            key: .mangled("m"),
            containerName: "Foo",
            droppedSignatures: ["dropped()"]
        )])
    }

    @Test("duplicate container keys and global identities are reported too")
    func containerAndGlobalCollisions() {
        let snapshot = ABISnapshot(
            types: [container("Foo"), container("Foo")],
            globalFunctions: [record("g", signature: "g()"), record("g", signature: "g() #2")]
        )
        let collisions = snapshot.keyCollisions()
        #expect(collisions.count == 2)
        #expect(collisions.contains(ABIKeyCollision(key: .printed("Foo"), containerName: nil, droppedSignatures: ["Foo"])))
        #expect(collisions.contains(ABIKeyCollision(key: .mangled("g"), containerName: nil, droppedSignatures: ["g() #2"])))
    }

    @Test("the diff carries per-side diagnostics, nil when both sides are clean")
    func diffDiagnostics() throws {
        let clean = ABISnapshot(types: [container("Foo", members: [record("a")])])
        let colliding = ABISnapshot(types: [container("Foo", members: [record("a"), record("a")])])

        #expect(ABIDiffer().diff(old: clean, new: clean).diagnostics == nil)

        let diff = ABIDiffer().diff(old: clean, new: colliding)
        let diagnostics = try #require(diff.diagnostics)
        #expect(diagnostics.oldSideKeyCollisions.isEmpty)
        #expect(diagnostics.newSideKeyCollisions.count == 1)
    }

    @Test("the evolution carries per-version collisions aligned with the axis, nil when clean everywhere")
    func evolutionDiagnostics() throws {
        let clean = ABISnapshot(types: [container("Foo", members: [record("a")])])
        let colliding = ABISnapshot(types: [container("Foo", members: [record("a"), record("a")])])

        let cleanEvolution = try ABIEvolutionBuilder().evolution(
            of: [clean, clean].map { ABISnapshotDocument(snapshot: $0) }
        )
        #expect(cleanEvolution.keyCollisionsByVersion == nil)

        let evolution = try ABIEvolutionBuilder().evolution(
            of: [clean, colliding, clean].map { ABISnapshotDocument(snapshot: $0) }
        )
        let keyCollisionsByVersion = try #require(evolution.keyCollisionsByVersion)
        #expect(keyCollisionsByVersion.map(\.count) == [0, 1, 0])
    }

    @Test("the diff reporter appends a warnings section, even on an otherwise-empty diff")
    func diffReporterWarnings() {
        let colliding = ABISnapshot(types: [container("Foo", members: [
            record("m", signature: "kept()"),
            record("m", signature: "dropped()"),
        ])])
        let report = ABIDiffReporter().report(ABIDiffer().diff(old: colliding, new: colliding))
        #expect(report == """
        No ABI changes.

        Warnings — identity-key collisions (first record kept, later ones not compared):
          old · Foo · dropped: dropped()
          new · Foo · dropped: dropped()
        """)
    }

    @Test("the evolution reporter labels collision warnings with the version")
    func evolutionReporterWarnings() throws {
        let clean = ABISnapshot(types: [container("Foo", members: [record("m", signature: "kept()")])])
        let colliding = ABISnapshot(types: [container("Foo", members: [
            record("m", signature: "kept()"),
            record("m", signature: "dropped()"),
        ])])
        let evolution = try ABIEvolutionBuilder().evolution(
            of: [clean, colliding].map { ABISnapshotDocument(snapshot: $0) },
            labels: ["1.0", "2.0"]
        )
        let report = ABIEvolutionReporter().report(evolution)
        #expect(report.hasSuffix("""
        Warnings — identity-key collisions (first record kept, later ones not compared):
          2.0 · Foo · dropped: dropped()
        """))
    }
}
