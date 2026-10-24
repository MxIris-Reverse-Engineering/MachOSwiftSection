@testable import SwiftDiffing
import Testing
import Foundation

// MARK: - Versions that cannot show non-exported members
//
// Evolution proposal `evolution-unobservable-presence`: a version whose image
// carries no local Swift symbols cannot show a member only a non-exported
// symbol evidences. Driven with hand-built snapshots, like the other
// `ABIEvolutionBuilder` suites, so each rule is pinned without a Mach-O.

private func record(
    _ identity: String,
    payload: String? = nil,
    kind: MemberKind = .function,
    isExported: Bool? = false
) -> MemberRecord {
    MemberRecord(
        identityKey: .mangled(identity),
        payloadKey: .mangled(payload ?? identity),
        kind: kind,
        signature: identity,
        isExported: isExported
    )
}

private func container(_ name: String, kind: ContainerKind = .type, members: [MemberRecord] = []) -> ContainerSnapshot {
    ContainerSnapshot(key: .printed(name), name: name, kind: kind, members: members)
}

/// A version that keeps its local Swift symbols.
private func symbolRich(_ types: [ContainerSnapshot] = [], typeExtensions: [ContainerSnapshot] = [], conformanceExtensions: [ContainerSnapshot] = []) -> ABISnapshot {
    ABISnapshot(types: types, typeExtensions: typeExtensions, conformanceExtensions: conformanceExtensions)
}

/// A version stripped of its local Swift symbols.
private func stripped(_ types: [ContainerSnapshot] = [], typeExtensions: [ContainerSnapshot] = [], conformanceExtensions: [ContainerSnapshot] = []) -> ABISnapshot {
    ABISnapshot(types: types, typeExtensions: typeExtensions, conformanceExtensions: conformanceExtensions, hasLocalSwiftSymbols: false)
}

private func evolution(_ snapshots: [ABISnapshot]) throws -> ABIEvolution {
    try ABIEvolutionBuilder().evolution(
        of: snapshots.map { ABISnapshotDocument(snapshot: $0) },
        labels: snapshots.indices.map { "\($0 + 1).0" }
    )
}

private func memberLineage(_ key: String, in result: ABIEvolution, container containerName: String = "Foo") throws -> MemberLineage {
    let containerLineage = try #require(result.allContainerLineages.first { $0.name == containerName })
    return try #require(containerLineage.memberLineages.first { $0.key == .mangled(key) })
}

@Suite("ABIEvolutionBuilder: versions without local Swift symbols")
struct ABIUnobservablePresenceTests {
    @Test("a non-exported member a version cannot show is inferred present between two observations of it")
    func inferredPresentBetweenObservations() throws {
        let result = try evolution([
            symbolRich([container("Foo", members: [record("hidden")])]),
            stripped([container("Foo")]),
            symbolRich([container("Foo", members: [record("hidden")])]),
        ])
        let lineage = try memberLineage("hidden", in: result)
        #expect(lineage.presenceStates == [.present, .inferredPresent, .present])
        #expect(lineage.presence == [true, true, true])
        #expect(lineage.events.isEmpty)
        #expect(lineage.latestSignature == "hidden")
        #expect(result.versionIndicesWithoutLocalSwiftSymbols == [1])
    }

    @Test("a removal across versions that cannot show the member is placed between the observations around them")
    func removalPlacedBetweenObservations() throws {
        let result = try evolution([
            symbolRich([container("Foo", members: [record("retired")])]),
            stripped([container("Foo")]),
            symbolRich([container("Foo")]),
        ])
        let lineage = try memberLineage("retired", in: result)
        #expect(lineage.presenceStates == [.present, .unobservable, .absent])
        #expect(lineage.events == [LineageEvent(versionIndex: 2, status: .removed, oldSignature: "retired", earliestVersionIndex: 1)])
    }

    @Test("an addition across versions that cannot show the member is placed between the observations around them")
    func additionPlacedBetweenObservations() throws {
        let result = try evolution([
            symbolRich([container("Foo")]),
            stripped([container("Foo")]),
            symbolRich([container("Foo", members: [record("fresh")])]),
        ])
        let lineage = try memberLineage("fresh", in: result)
        #expect(lineage.presenceStates == [.absent, .unobservable, .present])
        #expect(lineage.events == [LineageEvent(versionIndex: 2, status: .added, newSignature: "fresh", earliestVersionIndex: 1)])
    }

    @Test("a payload change across versions that cannot show the member is placed between the observations around them")
    func modificationPlacedBetweenObservations() throws {
        let result = try evolution([
            symbolRich([container("Foo", members: [record("value", payload: "get", kind: .variable)])]),
            stripped([container("Foo")]),
            symbolRich([container("Foo", members: [record("value", payload: "get,set", kind: .variable)])]),
        ])
        let lineage = try memberLineage("value", in: result)
        #expect(lineage.presenceStates == [.present, .inferredPresent, .present])
        #expect(lineage.events == [LineageEvent(versionIndex: 2, status: .modified, oldSignature: "value", newSignature: "value", earliestVersionIndex: 1)])
    }

    @Test("an exported member missing from a version without local Swift symbols is an observed removal")
    func exportedMemberAbsenceIsObserved() throws {
        let result = try evolution([
            symbolRich([container("Foo", members: [record("public", isExported: true)])]),
            stripped([container("Foo")]),
        ])
        let lineage = try memberLineage("public", in: result)
        #expect(lineage.presenceStates == nil)
        #expect(lineage.events == [LineageEvent(versionIndex: 1, status: .removed, oldSignature: "public")])
    }

    @Test("a member the image's metadata records stays observable without local Swift symbols")
    func metadataMemberAbsenceIsObserved() throws {
        let result = try evolution([
            symbolRich([container("Foo", members: [record("field:count", payload: "Int", kind: .field, isExported: nil)])]),
            stripped([container("Foo")]),
        ])
        let lineage = try memberLineage("field:count", in: result)
        #expect(lineage.presenceStates == nil)
        #expect(lineage.events.map(\.status) == [.removed])
    }

    @Test("a member whose only neighbour is exported on one side and not on the other is not seen gone")
    func oneNonExportedNeighbourHides() throws {
        let result = try evolution([
            symbolRich([container("Foo", members: [record("promoted", isExported: false)])]),
            stripped([container("Foo")]),
            symbolRich([container("Foo", members: [record("promoted", isExported: true)])]),
        ])
        let lineage = try memberLineage("promoted", in: result)
        #expect(lineage.presenceStates == [.present, .inferredPresent, .present])
        #expect(lineage.events.isEmpty)
    }

    @Test("versions that cannot show the member at an end of the axis claim nothing")
    func spanReachingTheAxisEndStaysUnobservable() throws {
        let result = try evolution([
            symbolRich([container("Foo", members: [record("trailing")])]),
            stripped([container("Foo")]),
        ])
        let lineage = try memberLineage("trailing", in: result)
        #expect(lineage.presenceStates == [.present, .unobservable])
        #expect(lineage.presence == [true, false])
        #expect(lineage.events.isEmpty)
    }

    @Test("two absences around versions that cannot show the member infer nothing")
    func absencesAroundASpanClaimNothing() throws {
        let result = try evolution([
            symbolRich([container("Foo", members: [record("gone")])]),
            symbolRich([container("Foo")]),
            stripped([container("Foo")]),
            symbolRich([container("Foo")]),
        ])
        let lineage = try memberLineage("gone", in: result)
        #expect(lineage.presenceStates == [.present, .absent, .unobservable, .absent])
        #expect(lineage.events == [LineageEvent(versionIndex: 1, status: .removed, oldSignature: "gone")])
    }

    /// The container comes and goes around the stripped version, so the
    /// member has no event of its own, and the span it cannot be seen in
    /// lies between two absences: nothing to tell, so no lineage.
    @Test("a member unseen only between two absences carries no lineage of its own")
    func spanBetweenAbsencesKeepsNoLineage() throws {
        let result = try evolution([
            symbolRich(),
            stripped([container("Foo")]),
            symbolRich(),
            symbolRich([container("Foo", members: [record("late")])]),
        ])
        let lineage = try #require(result.types.first)
        #expect(lineage.events.map(\.status) == [.added, .removed, .added])
        #expect(lineage.memberLineages.isEmpty)
    }

    @Test("an extension made up only of non-exported members cannot be seen where they cannot")
    func extensionOfHiddenMembersIsHidden() throws {
        let result = try evolution([
            symbolRich(typeExtensions: [container("Swift.Int", kind: .typeExtension, members: [record("scale")])]),
            stripped(),
            symbolRich(typeExtensions: [container("Swift.Int", kind: .typeExtension, members: [record("scale")])]),
        ])
        let lineage = try #require(result.typeExtensions.first)
        #expect(lineage.presenceStates == [.present, .inferredPresent, .present])
        #expect(lineage.events.isEmpty)
    }

    /// The members of an added or removed container carry no lineage of
    /// their own; neither do the members of a container a version cannot
    /// show, unseen only because it is.
    @Test("a member unseen only where its container is unseen is left to the container's lineage")
    func memberOfAnUnseenContainerHasNoLineage() throws {
        let result = try evolution([
            symbolRich(typeExtensions: [container("Swift.Int", kind: .typeExtension, members: [record("scale")])]),
            stripped(),
            symbolRich(typeExtensions: [container("Swift.Int", kind: .typeExtension, members: [record("scale")])]),
        ])
        #expect(result.typeExtensions.first?.memberLineages.isEmpty == true)
    }

    @Test("a conformance stays observable without local Swift symbols")
    func conformanceAbsenceIsObserved() throws {
        let result = try evolution([
            symbolRich(conformanceExtensions: [container("Foo: Equatable", kind: .conformanceExtension, members: [record("equals")])]),
            stripped(),
        ])
        let lineage = try #require(result.conformanceExtensions.first)
        #expect(lineage.presenceStates == nil)
        #expect(lineage.events == [LineageEvent(versionIndex: 1, status: .removed)])
    }

    @Test("a change across versions that cannot show the member counts toward the transition that first observes it")
    func spanningRemovalIsBreakingWhereObserved() throws {
        let result = try evolution([
            symbolRich([container("Foo", members: [record("retired")])]),
            stripped([container("Foo")]),
            symbolRich([container("Foo")]),
        ])
        #expect(result.transitionCompatibilities == [.additive, .breaking])
    }

    @Test("an axis whose every version keeps its local Swift symbols encodes none of the new fields")
    func symbolRichAxisEncodingIsUnchanged() throws {
        let result = try evolution([
            symbolRich([container("Foo", members: [record("a")])]),
            symbolRich([container("Foo")]),
        ])
        let json = try #require(String(data: ABIJSON.encoder().encode(result), encoding: .utf8))
        for key in ["presenceStates", "latestSignature", "earliestVersionIndex", "versionIndicesWithoutLocalSwiftSymbols"] {
            #expect(!json.contains(key), "\(key) leaked into the encoding of an axis without stripped versions")
        }
    }
}

// MARK: - Two-sided diff

@Suite("ABIDiffer: a side without local Swift symbols")
struct ABIDifferUnobservablePresenceTests {
    @Test("a non-exported member the new side cannot show is listed apart, neither removed nor breaking")
    func hiddenOnTheNewSide() {
        let diff = ABIDiffer().diff(
            old: symbolRich([container("Foo", members: [record("hidden"), record("public", isExported: true)])]),
            new: stripped([container("Foo")])
        )
        let fooChange = diff.types.first { $0.name == "Foo" }
        #expect(fooChange?.memberChanges.map(\.key) == [.mangled("public")])
        #expect(diff.unobservableDeclarations == [
            UnobservableDeclaration(side: .new, key: .mangled("hidden"), containerName: "Foo", containerKind: .type, memberKind: .function, signature: "hidden"),
        ])
    }

    @Test("a non-exported member the old side cannot show is listed apart, never added")
    func hiddenOnTheOldSide() {
        let diff = ABIDiffer().diff(
            old: stripped([container("Foo")]),
            new: symbolRich([container("Foo", members: [record("hidden")])])
        )
        #expect(diff.isEmpty)
        #expect(diff.unobservableDeclarations?.map(\.side) == [.old])
    }

    @Test("an extension the new side cannot show is listed apart, its members with it")
    func hiddenExtension() {
        let diff = ABIDiffer().diff(
            old: symbolRich(typeExtensions: [container("Swift.Int", kind: .typeExtension, members: [record("scale")])]),
            new: stripped()
        )
        #expect(diff.isEmpty)
        #expect(diff.unobservableDeclarations?.map(\.key) == [.printed("Swift.Int")])
        #expect(!diff.hasBreakingChange)
    }

    @Test("for two versions the diff lists exactly what the evolution leaves unobservable")
    func pairwiseConsistencyWithAStrippedSide() throws {
        let old = symbolRich(
            [container("Foo", members: [record("hidden"), record("public", isExported: true)])],
            typeExtensions: [container("Swift.Int", kind: .typeExtension, members: [record("scale")])]
        )
        let new = stripped([container("Foo")])
        let diff = ABIDiffer().diff(old: old, new: new)
        let result = try evolution([old, new])

        let changedMemberKeys = Set(diff.types.flatMap(\.memberChanges).map(\.key))
        let eventMemberKeys = Set(result.allContainerLineages.flatMap(\.memberLineages).filter { !$0.events.isEmpty }.map(\.key))
        #expect(changedMemberKeys == eventMemberKeys)

        let unobservableKeys = Set((diff.unobservableDeclarations ?? []).map(\.key))
        let unobservableLineageKeys = Set(
            result.allContainerLineages.filter { $0.presenceStates?.contains(.unobservable) == true }.map(\.key)
                + result.allContainerLineages.flatMap(\.memberLineages).filter { $0.presenceStates?.contains(.unobservable) == true }.map(\.key)
        )
        #expect(unobservableKeys == unobservableLineageKeys)
    }
}

// MARK: - Reports

@Suite("Reports: versions without local Swift symbols")
struct UnobservablePresenceReportTests {
    @Test("the timeline report marks what the stripped version cannot show")
    func timelineReport() throws {
        let result = try evolution([
            symbolRich([container("Foo", members: [record("kept"), record("retired")])]),
            stripped([container("Foo")]),
            symbolRich([container("Foo", members: [record("kept")])]),
        ])
        let report = ABIEvolutionReporter().report(result)
        #expect(report == """
        ABI evolution across 3 versions: 1.0 → 2.0 → 3.0

        Transitions:
          1.0 → 2.0: no changes
          2.0 → 3.0: 1 removed · ABI-breaking
            (1 of them happened somewhere between 1.0 and 3.0: the versions in between could not show them)
        First ABI-breaking transition: 2.0 → 3.0
        No local Swift symbols, so non-exported members cannot be seen: 2.0 (◍ inferred present, ◌ not observable)

        Types:
          [●●●] Foo
              [●◍●] kept
                  ◍ inferred present in 2.0
              [●◌○] retired
                  - removed between 1.0 and 3.0
        """)
    }

    @Test("the diff report lists what one side cannot show")
    func diffReport() {
        let diff = ABIDiffer().diff(
            old: symbolRich([container("Foo", members: [record("hidden")])]),
            new: stripped([container("Foo")])
        )
        #expect(ABIDiffReporter().report(diff) == """
        No ABI changes.

        Not observable on the new side — it carries no local Swift symbols, so these are neither removed nor added:
          hidden
        """)
    }
}
