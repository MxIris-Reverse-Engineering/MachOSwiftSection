@testable import SwiftDiffing
import Testing
import Foundation

// MARK: - Default-implementation-aware compatibility verdict

@Suite("Default-implementation-aware compatibility")
struct ABICompatibilityTests {
    private func strippedSlot(offset: Int = 8, kindToken: String = "method", hasDefaultImplementation: Bool) -> MemberRecord {
        MemberRecord.makeProtocolRequirement(
            pwtOffset: offset,
            kindToken: kindToken,
            isInstance: true,
            isAsync: false,
            hasDefaultImplementation: hasDefaultImplementation
        )
    }

    private func resolvedRequirement(_ name: String, hasDefaultImplementation: Bool?) -> MemberRecord {
        MemberRecord(
            identityKey: .mangled(name),
            payloadKey: .mangled(name),
            kind: .function,
            signature: name + "()",
            hasDefaultImplementation: hasDefaultImplementation
        )
    }

    private func protocolContainer(_ name: String, members: [MemberRecord]) -> ContainerSnapshot {
        ContainerSnapshot(key: .printed(name), name: name, kind: .protocol, members: members)
    }

    // MARK: Rule table

    @Test("an addition without a default implementation overrides to breaking; with one (or unknown) it stays additive")
    func additionRule() {
        #expect(MemberRecord.compatibilityOverride(old: nil, new: strippedSlot(hasDefaultImplementation: false)) == .breaking)
        #expect(MemberRecord.compatibilityOverride(old: nil, new: strippedSlot(hasDefaultImplementation: true)) == nil)
        #expect(MemberRecord.compatibilityOverride(old: nil, new: resolvedRequirement("f", hasDefaultImplementation: false)) == .breaking)
        #expect(MemberRecord.compatibilityOverride(old: nil, new: resolvedRequirement("f", hasDefaultImplementation: true)) == nil)
        #expect(MemberRecord.compatibilityOverride(old: nil, new: resolvedRequirement("f", hasDefaultImplementation: nil)) == nil)
    }

    @Test("a stripped slot gaining only its default implementation overrides to additive; losing it (or changing anything else) does not")
    func defaultFlipRule() {
        let bare = strippedSlot(hasDefaultImplementation: false)
        let defaulted = strippedSlot(hasDefaultImplementation: true)
        #expect(MemberRecord.compatibilityOverride(old: bare, new: defaulted) == .additive)
        #expect(MemberRecord.compatibilityOverride(old: defaulted, new: bare) == nil)

        let differentKind = strippedSlot(kindToken: "getter", hasDefaultImplementation: true)
        #expect(MemberRecord.compatibilityOverride(old: bare, new: differentKind) == nil)
    }

    @Test("removals never override — the status rule (breaking) already applies")
    func removalRule() {
        #expect(MemberRecord.compatibilityOverride(old: strippedSlot(hasDefaultImplementation: true), new: nil) == nil)
        #expect(MemberRecord.compatibilityOverride(old: strippedSlot(hasDefaultImplementation: false), new: nil) == nil)
    }

    @Test("the slot-correlation flag: all slots defaulted, any not, any unknown")
    func slotCorrelation() {
        let defaultedOffsets: Set<Int> = [8, 16]
        #expect(ABIDiffer.requirementDefaultImplementationFlag(slotOffsets: [8, 16], defaultedOffsets: defaultedOffsets) == true)
        #expect(ABIDiffer.requirementDefaultImplementationFlag(slotOffsets: [8, 24], defaultedOffsets: defaultedOffsets) == false)
        #expect(ABIDiffer.requirementDefaultImplementationFlag(slotOffsets: [8, nil], defaultedOffsets: defaultedOffsets) == nil)
        #expect(ABIDiffer.requirementDefaultImplementationFlag(slotOffsets: [], defaultedOffsets: defaultedOffsets) == nil)
    }

    // MARK: Diff integration

    @Test("diffMembers stamps the override onto the change")
    func diffMembersStampsOverride() {
        let changes = ABIDiffer().diffMembers(old: [], new: [strippedSlot(hasDefaultImplementation: false)])
        #expect(changes.first?.compatibilityOverride == .breaking)
        #expect(changes.first?.compatibility == .breaking)

        let flip = ABIDiffer().diffMembers(
            old: [strippedSlot(hasDefaultImplementation: false)],
            new: [strippedSlot(hasDefaultImplementation: true)]
        )
        #expect(flip.first?.status == .modified)
        #expect(flip.first?.compatibility == .additive)
    }

    @Test("a protocol gaining a defaultless requirement flips the whole diff to ABI-breaking; a defaulted one stays additive")
    func containerVerdict() {
        let before = ABISnapshot(protocols: [protocolContainer("P", members: [resolvedRequirement("existing", hasDefaultImplementation: nil)])])
        let defaultlessAfter = ABISnapshot(protocols: [protocolContainer("P", members: [
            resolvedRequirement("existing", hasDefaultImplementation: nil),
            strippedSlot(hasDefaultImplementation: false),
        ])])
        let defaultedAfter = ABISnapshot(protocols: [protocolContainer("P", members: [
            resolvedRequirement("existing", hasDefaultImplementation: nil),
            strippedSlot(hasDefaultImplementation: true),
        ])])

        let breakingDiff = ABIDiffer().diff(old: before, new: defaultlessAfter)
        #expect(breakingDiff.hasBreakingChange)
        #expect(breakingDiff.protocols.first?.compatibility == .breaking)

        let additiveDiff = ABIDiffer().diff(old: before, new: defaultedAfter)
        #expect(!additiveDiff.hasBreakingChange)
        #expect(additiveDiff.protocols.first?.compatibility == .additive)
    }

    // MARK: Evolution integration

    @Test("evolution transitions apply the same rule as the two-sided differ")
    func evolutionVerdicts() throws {
        let before = ABISnapshot(protocols: [protocolContainer("P", members: [resolvedRequirement("existing", hasDefaultImplementation: nil)])])
        let defaultlessAfter = ABISnapshot(protocols: [protocolContainer("P", members: [
            resolvedRequirement("existing", hasDefaultImplementation: nil),
            strippedSlot(hasDefaultImplementation: false),
        ])])
        let defaultedFinally = ABISnapshot(protocols: [protocolContainer("P", members: [
            resolvedRequirement("existing", hasDefaultImplementation: nil),
            strippedSlot(hasDefaultImplementation: true),
        ])])

        // v1 → v2 adds a defaultless slot (breaking); v2 → v3 only gains the
        // default implementation (additive).
        let evolution = try ABIEvolutionBuilder().evolution(
            of: [before, defaultlessAfter, defaultedFinally].map { ABISnapshotDocument(snapshot: $0) },
            labels: ["1", "2", "3"]
        )
        #expect(evolution.transitionCompatibilities == [.breaking, .additive])
        #expect(evolution.firstBreakingVersionIndex == 1)

        // Pairwise agreement on both transitions.
        #expect(ABIDiffer().diff(old: before, new: defaultlessAfter).hasBreakingChange)
        #expect(!ABIDiffer().diff(old: defaultlessAfter, new: defaultedFinally).hasBreakingChange)
    }
}
