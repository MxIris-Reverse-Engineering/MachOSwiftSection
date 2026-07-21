@testable import SwiftDiffing
import Testing
import Foundation

// MARK: - N-way lineage tracking
//
// These drive `ABIEvolutionBuilder` with explicitly-keyed `MemberRecord`s and
// hand-built snapshots — same style as `ABIDifferAlgorithmTests` — so the
// matrix algorithm is validated deterministically, independent of remangle
// fidelity and without a Mach-O.

@Suite("ABIEvolutionBuilder")
struct ABIEvolutionBuilderTests {
    private func record(
        _ identity: String,
        payload: String? = nil,
        kind: MemberKind = .function,
        signature: String? = nil
    ) -> MemberRecord {
        MemberRecord(
            identityKey: .mangled(identity),
            payloadKey: .mangled(payload ?? identity),
            kind: kind,
            signature: signature ?? identity
        )
    }

    private func container(_ name: String, members: [MemberRecord] = []) -> ContainerSnapshot {
        ContainerSnapshot(key: .printed(name), name: name, kind: .type, members: members)
    }

    private func snapshot(types: [ContainerSnapshot] = [], globalFunctions: [MemberRecord] = []) -> ABISnapshot {
        ABISnapshot(types: types, globalFunctions: globalFunctions)
    }

    private func evolution(_ snapshots: [ABISnapshot], labels: [String]? = nil) throws -> ABIEvolution {
        try ABIEvolutionBuilder().evolution(
            of: snapshots.map { ABISnapshotDocument(snapshot: $0) },
            labels: labels
        )
    }

    // MARK: Lineage shapes

    @Test("a member appearing mid-axis gets an added event and a correct presence bitmap")
    func memberIntroduced() throws {
        let result = try evolution([
            snapshot(types: [container("Foo", members: [record("a")])]),
            snapshot(types: [container("Foo", members: [record("a"), record("b")])]),
            snapshot(types: [container("Foo", members: [record("a"), record("b")])]),
        ])
        #expect(result.types.count == 1)
        let lineage = try #require(result.types.first)
        #expect(lineage.presence == [true, true, true])
        #expect(lineage.events.isEmpty)
        #expect(lineage.memberLineages.count == 1)
        let memberLineage = try #require(lineage.memberLineages.first)
        #expect(memberLineage.key == .mangled("b"))
        #expect(memberLineage.presence == [false, true, true])
        #expect(memberLineage.events == [LineageEvent(versionIndex: 1, status: .added, newSignature: "b")])
    }

    @Test("a payload change mid-axis is a modified event with both signatures")
    func memberModified() throws {
        let result = try evolution([
            snapshot(types: [container("Foo", members: [record("x", payload: "Int", kind: .field, signature: "x: Int")])]),
            snapshot(types: [container("Foo", members: [record("x", payload: "String", kind: .field, signature: "x: String")])]),
        ])
        let memberLineage = try #require(result.types.first?.memberLineages.first)
        #expect(memberLineage.kind == .field)
        #expect(memberLineage.events == [
            LineageEvent(versionIndex: 1, status: .modified, oldSignature: "x: Int", newSignature: "x: String"),
        ])
    }

    @Test("an enum-case tag renumbering surfaces as modified on the affected version")
    func enumCaseTagRenumbered() throws {
        // Mid-inserting a case renumbers the tags after it — payload carries
        // the tag exactly like `MemberRecord.makeCase`.
        let result = try evolution([
            snapshot(types: [container("Direction", members: [record("case:south", payload: "tag:0|()", kind: .enumCase, signature: "case south")])]),
            snapshot(types: [container("Direction", members: [
                record("case:north", payload: "tag:0|()", kind: .enumCase, signature: "case north"),
                record("case:south", payload: "tag:1|()", kind: .enumCase, signature: "case south"),
            ])]),
        ])
        let lineage = try #require(result.types.first)
        let southLineage = try #require(lineage.memberLineages.first { $0.key == .mangled("case:south") })
        #expect(southLineage.events.map(\.status) == [.modified])
        let northLineage = try #require(lineage.memberLineages.first { $0.key == .mangled("case:north") })
        #expect(northLineage.events.map(\.status) == [.added])
    }

    @Test("a container removed then re-added yields two container events and no member events across the gap")
    func containerGap() throws {
        let result = try evolution([
            snapshot(types: [container("Foo", members: [record("x", payload: "Int", kind: .field)])]),
            snapshot(types: []),
            snapshot(types: [container("Foo", members: [record("x", payload: "String", kind: .field)])]),
        ])
        let lineage = try #require(result.types.first)
        #expect(lineage.presence == [true, false, true])
        #expect(lineage.events == [
            LineageEvent(versionIndex: 1, status: .removed),
            LineageEvent(versionIndex: 2, status: .added),
        ])
        // The retype across the gap is invisible by design — the two-sided
        // differ never enumerates members of an added/removed container.
        #expect(lineage.memberLineages.isEmpty)
    }

    @Test("an unchanged axis is empty")
    func unchangedAxisIsEmpty() throws {
        let unchanged = snapshot(
            types: [container("Foo", members: [record("a")])],
            globalFunctions: [record("g")]
        )
        let result = try evolution([unchanged, unchanged, unchanged])
        #expect(result.isEmpty)
    }

    @Test("global lineages track across the axis")
    func globals() throws {
        let result = try evolution([
            snapshot(globalFunctions: [record("f")]),
            snapshot(globalFunctions: []),
            snapshot(globalFunctions: [record("f")]),
        ])
        let lineage = try #require(result.globalFunctions.first)
        #expect(lineage.presence == [true, false, true])
        #expect(lineage.events.map(\.status) == [.removed, .added])
    }

    // MARK: Two-sided consistency

    @Test("for N == 2 the events match ABIDiffer.diff exactly")
    func pairwiseConsistency() throws {
        let old = snapshot(
            types: [
                container("Foo", members: [
                    record("removedMember"),
                    record("keptMember"),
                    record("retyped", payload: "Int", kind: .field),
                ]),
            ],
            globalFunctions: [record("droppedGlobal")]
        )
        let new = snapshot(
            types: [
                container("Foo", members: [
                    record("keptMember"),
                    record("addedMember"),
                    record("retyped", payload: "String", kind: .field),
                ]),
                container("Bar"),
            ],
            globalFunctions: []
        )

        let diff = ABIDiffer().diff(old: old, new: new)
        let result = try evolution([old, new])

        // Container axis: same keys, same statuses.
        let diffContainerStatuses = Dictionary(uniqueKeysWithValues: diff.types.map { ($0.key, $0.status) })
        for lineage in result.types {
            if let containerEvent = lineage.events.first {
                #expect(diffContainerStatuses[lineage.key] == containerEvent.status)
            } else {
                #expect(diffContainerStatuses[lineage.key] == .modified)
            }
        }
        #expect(result.types.count == diff.types.count)

        // Member axis of the modified container: same key → status mapping.
        let diffMemberStatuses = Dictionary(uniqueKeysWithValues:
            diff.types.first { $0.key == .printed("Foo") }!.memberChanges.map { ($0.key, $0.status) }
        )
        let lineageMemberStatuses = Dictionary(uniqueKeysWithValues:
            result.types.first { $0.key == .printed("Foo") }!.memberLineages.map { ($0.key, $0.events.first!.status) }
        )
        #expect(diffMemberStatuses == lineageMemberStatuses)

        // Globals too.
        #expect(diff.globalFunctions.map(\.key) == result.globalFunctions.map(\.key))
        #expect(diff.globalFunctions.map(\.status) == result.globalFunctions.flatMap(\.events).map(\.status))
    }

    // MARK: Labels & input shape

    @Test("label precedence: explicit > provenance > positional")
    func labelResolution() throws {
        let plain = ABISnapshotDocument(snapshot: snapshot())
        let labeled = ABISnapshotDocument(provenance: ABIProvenance(label: "from-provenance"), snapshot: snapshot())

        let positional = try ABIEvolutionBuilder().evolution(of: [plain, plain])
        #expect(positional.versions.map(\.label) == ["v1", "v2"])

        let provenanceDriven = try ABIEvolutionBuilder().evolution(of: [plain, labeled])
        #expect(provenanceDriven.versions.map(\.label) == ["v1", "from-provenance"])

        let explicit = try ABIEvolutionBuilder().evolution(of: [plain, labeled], labels: ["a", "b"])
        #expect(explicit.versions.map(\.label) == ["a", "b"])
    }

    @Test("fewer than two versions is a typed error")
    func fewerThanTwoVersions() {
        #expect(throws: ABIEvolutionError.fewerThanTwoVersions(versionCount: 1)) {
            try ABIEvolutionBuilder().evolution(of: [ABISnapshotDocument(snapshot: ABISnapshot())])
        }
    }

    @Test("label count mismatch is a typed error")
    func labelCountMismatch() {
        let document = ABISnapshotDocument(snapshot: ABISnapshot())
        #expect(throws: ABIEvolutionError.labelCountMismatch(labelCount: 3, versionCount: 2)) {
            try ABIEvolutionBuilder().evolution(of: [document, document], labels: ["a", "b", "c"])
        }
    }

    // MARK: Compatibility

    @Test("per-transition verdicts and the first breaking transition")
    func transitionCompatibilities() throws {
        let result = try evolution([
            snapshot(types: [container("Foo", members: [record("a")])]),
            snapshot(types: [container("Foo", members: [record("a"), record("b")])]),   // additive
            snapshot(types: [container("Foo", members: [record("b")])]),                 // breaking (a removed)
        ])
        #expect(result.transitionCompatibilities == [.additive, .breaking])
        #expect(result.hasBreakingChange)
        #expect(result.firstBreakingVersionIndex == 2)
    }

    @Test("an all-additive axis has no breaking transition")
    func additiveAxis() throws {
        let result = try evolution([
            snapshot(types: [container("Foo", members: [record("a")])]),
            snapshot(types: [container("Foo", members: [record("a"), record("b")])]),
        ])
        #expect(result.transitionCompatibilities == [.additive])
        #expect(!result.hasBreakingChange)
        #expect(result.firstBreakingVersionIndex == nil)
    }

    // MARK: Round-trip

    @Test("an evolution is Codable and round-trips")
    func evolutionRoundTrips() throws {
        let result = try evolution([
            snapshot(types: [container("Foo", members: [record("a")])]),
            snapshot(types: [container("Foo", members: [record("a"), record("b")])]),
        ])
        let decoded = try ABIJSON.decoder().decode(ABIEvolution.self, from: ABIJSON.encoder().encode(result))
        #expect(decoded == result)
    }
}

// MARK: - Reporter

@Suite("ABIEvolutionReporter")
struct ABIEvolutionReporterTests {
    @Test("renders the timeline report deterministically")
    func timelineReport() throws {
        let old = ABISnapshot(types: [ContainerSnapshot(
            key: .printed("Foo"),
            name: "Foo",
            kind: .type,
            members: [MemberRecord(identityKey: .mangled("x"), payloadKey: .mangled("Int"), kind: .field, signature: "x: Int")]
        )])
        let middle = ABISnapshot(types: [ContainerSnapshot(
            key: .printed("Foo"),
            name: "Foo",
            kind: .type,
            members: [MemberRecord(identityKey: .mangled("x"), payloadKey: .mangled("String"), kind: .field, signature: "x: String")]
        )])
        let latest = ABISnapshot()

        let evolution = try ABIEvolutionBuilder().evolution(
            of: [old, middle, latest].map { ABISnapshotDocument(snapshot: $0) },
            labels: ["1.0", "2.0", "3.0"]
        )
        let report = ABIEvolutionReporter().report(evolution)
        let expected = """
        ABI evolution across 3 versions: 1.0 → 2.0 → 3.0

        Transitions:
          1.0 → 2.0: 1 modified · ABI-breaking
          2.0 → 3.0: 1 removed · ABI-breaking
        First ABI-breaking transition: 1.0 → 2.0

        Types:
          [●●○] Foo
              - removed in 3.0
              [●●○] x: String
                  ~ modified in 2.0: x: Int → x: String
        """
        #expect(report == expected)
    }

    @Test("summary is the header plus transitions only")
    func summaryOnly() throws {
        let evolution = try ABIEvolutionBuilder().evolution(
            of: [ABISnapshot(), ABISnapshot()].map { ABISnapshotDocument(snapshot: $0) },
            labels: ["1.0", "2.0"]
        )
        let summary = ABIEvolutionReporter().summary(evolution)
        #expect(summary == """
        ABI evolution across 2 versions: 1.0 → 2.0

        Transitions:
          1.0 → 2.0: no changes
        """)
    }
}
