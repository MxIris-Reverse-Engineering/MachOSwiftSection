@testable import SwiftDiffing
@testable import SwiftDeclaration
@testable import MachOSwiftSection
import Testing
import Foundation
import Demangling

// MARK: - Stripped protocol-requirement (PWT slot) projection

@Suite("Stripped protocol-requirement (PWT slot) projection")
struct ABIProtocolRequirementTests {
    /// Builds the model value the indexer produces for a stripped requirement:
    /// raw descriptor flags + the running PWT offset. Flags layout (runtime
    /// ABI): kind in the low 4 bits, `isInstance` = 0x10, `maybeAsync` = 0x20.
    private func strippedRequirement(
        pwtOffset: Int,
        flagsRawValue: UInt32,
        defaultImplementationOffset: Int32 = 0
    ) -> StrippedSymbolicRequirement {
        StrippedSymbolicRequirement(
            requirement: ProtocolRequirement(
                layout: .init(
                    flags: ProtocolRequirementFlags(rawValue: flagsRawValue),
                    defaultImplementation: .init(relativeOffset: defaultImplementationOffset)
                ),
                offset: 0
            ),
            pwtOffset: pwtOffset
        )
    }

    private func record(_ stripped: StrippedSymbolicRequirement) -> MemberRecord {
        MemberRecord.makeProtocolRequirement(
            pwtOffset: stripped.pwtOffset,
            kindToken: stripped.kindToken,
            isInstance: stripped.isInstance,
            isAsync: stripped.isAsync,
            hasDefaultImplementation: stripped.hasDefaultImplementation
        )
    }

    @Test("the model facade exposes the flag facts Mach-O-free")
    func modelFacts() {
        let instanceMethod = strippedRequirement(pwtOffset: 8, flagsRawValue: 0x11)
        #expect(instanceMethod.kindToken == "method")
        #expect(instanceMethod.isInstance)
        #expect(!instanceMethod.isAsync)
        #expect(!instanceMethod.hasDefaultImplementation)

        let asyncInstanceMethod = strippedRequirement(pwtOffset: 8, flagsRawValue: 0x31, defaultImplementationOffset: 4)
        #expect(asyncInstanceMethod.isAsync)
        #expect(asyncInstanceMethod.hasDefaultImplementation)

        // A coroutine's `maybeAsync` bit does not mean async (mirrors
        // `ProtocolRequirementFlags.isAsync`).
        let readCoroutine = strippedRequirement(pwtOffset: 16, flagsRawValue: 0x25)
        #expect(readCoroutine.kindToken == "readCoroutine")
        #expect(!readCoroutine.isAsync)

        let staticGetter = strippedRequirement(pwtOffset: 24, flagsRawValue: 0x03)
        #expect(staticGetter.kindToken == "getter")
        #expect(!staticGetter.isInstance)
    }

    @Test("identity keys on the PWT offset alone; the payload folds in every flag")
    func keyComposition() {
        let slot = record(strippedRequirement(pwtOffset: 8, flagsRawValue: 0x11))
        #expect(slot.identityKey == .printed("pwtslot:8"))
        #expect(slot.payloadKey == .printed("pwtslot:8|method|instance:1|async:0|default:0"))
        #expect(slot.kind == .protocolRequirement)

        let asyncDefaulted = record(strippedRequirement(pwtOffset: 8, flagsRawValue: 0x31, defaultImplementationOffset: 4))
        #expect(asyncDefaulted.identityKey == slot.identityKey)
        #expect(asyncDefaulted.payloadKey == .printed("pwtslot:8|method|instance:1|async:1|default:1"))
    }

    @Test("an unchanged slot set reports nothing; a flag flip at the same offset is .modified")
    func flagFlip() {
        let old = [record(strippedRequirement(pwtOffset: 8, flagsRawValue: 0x11))]
        #expect(ABIDiffer().diffMembers(old: old, new: old).isEmpty)

        let defaulted = [record(strippedRequirement(pwtOffset: 8, flagsRawValue: 0x11, defaultImplementationOffset: 4))]
        let changes = ABIDiffer().diffMembers(old: old, new: defaulted)
        #expect(changes.count == 1)
        #expect(changes.first?.status == .modified)
        #expect(changes.first?.kind == .protocolRequirement)
    }

    @Test("appending a slot is a single .added; removing one is a single .removed")
    func appendAndRemove() {
        let base = [
            record(strippedRequirement(pwtOffset: 8, flagsRawValue: 0x11)),
            record(strippedRequirement(pwtOffset: 16, flagsRawValue: 0x13)),
        ]
        let appended = base + [record(strippedRequirement(pwtOffset: 24, flagsRawValue: 0x14))]

        let added = ABIDiffer().diffMembers(old: base, new: appended)
        #expect(added.map(\.status) == [.added])
        #expect(added.first?.key == .printed("pwtslot:24"))

        let removed = ABIDiffer().diffMembers(old: appended, new: base)
        #expect(removed.map(\.status) == [.removed])
    }

    @Test("a mid-table insertion honestly cascades: every shifted slot changes")
    func midTableInsertionCascade() {
        let old = [
            record(strippedRequirement(pwtOffset: 8, flagsRawValue: 0x11)),
            record(strippedRequirement(pwtOffset: 16, flagsRawValue: 0x13)),
        ]
        let new = [
            record(strippedRequirement(pwtOffset: 8, flagsRawValue: 0x00)),
            record(strippedRequirement(pwtOffset: 16, flagsRawValue: 0x11)),
            record(strippedRequirement(pwtOffset: 24, flagsRawValue: 0x13)),
        ]
        let changes = ABIDiffer().diffMembers(old: old, new: new)
        // Slots 8 and 16 keep their identity but change flags; 24 is new.
        #expect(changes.map(\.status).sorted(by: { $0.sortRank < $1.sortRank }) == [.added, .modified, .modified])
    }
}

// MARK: - Remangle-fallback audit

@Suite("Remangle-fallback key audit")
struct ABIRemangleFallbackTests {
    private func fallbackRecord(_ signature: String) -> MemberRecord {
        MemberRecord(
            identityKey: .printed(ABIKey.remangleFallbackPrefix + "function:" + signature),
            payloadKey: .printed(ABIKey.remangleFallbackPrefix + "function:" + signature),
            kind: .function,
            signature: signature
        )
    }

    private func cleanRecord(_ identity: String) -> MemberRecord {
        MemberRecord(identityKey: .mangled(identity), payloadKey: .mangled(identity), kind: .function, signature: identity)
    }

    private func container(_ name: String, members: [MemberRecord]) -> ContainerSnapshot {
        ContainerSnapshot(key: .printed(name), name: name, kind: .type, members: members)
    }

    @Test("a node the remangler rejects produces a self-identifying fallback key")
    func fallbackKeyIsSelfIdentifying() throws {
        // `genericSpecializationParam` is remangler-rejected by construction
        // (`mangleGenericSpecializationParam` throws `unsupportedNodeKind`).
        let key = ABIKey.make(for: Node.create(kind: .genericSpecializationParam))
        guard case .printed(let value) = key else {
            Issue.record("expected the fallback .printed branch, got \(key)")
            return
        }
        #expect(value.hasPrefix(ABIKey.remangleFallbackPrefix))
        #expect(key.isRemangleFallback)
    }

    @Test("mangled keys and deliberate printed namespaces are not flagged")
    func deliberateKeysAreNotFlagged() {
        #expect(!ABIKey.mangled("$s1M3FooV").isRemangleFallback)
        #expect(!ABIKey.printed("field:count").isRemangleFallback)
        #expect(!ABIKey.printed("pwtslot:8").isRemangleFallback)
    }

    @Test("the snapshot scan finds member, payload-only, and container-level fallbacks")
    func snapshotScan() {
        let payloadOnly = MemberRecord(
            identityKey: .printed("field:count"),
            payloadKey: .printed(ABIKey.remangleFallbackPrefix + "structure:Broken"),
            kind: .field,
            signature: "count: Broken"
        )
        // A composed extension-container key embeds its components' sort keys,
        // so a fallback component surfaces through `contains`.
        let composedContainer = ContainerSnapshot(
            key: .printed("extbucket:struct|1:" + ABIKey.remangleFallbackPrefix + "structure:Broken|proto:-|where:-|retro:0"),
            name: "Broken",
            kind: .typeExtension,
            members: []
        )
        let snapshot = ABISnapshot(
            types: [container("Foo", members: [fallbackRecord("broken()"), cleanRecord("fine"), payloadOnly])],
            typeExtensions: [composedContainer]
        )
        let fallbacks = snapshot.remangleFallbacks()
        #expect(fallbacks.count == 3)
        #expect(fallbacks.contains { $0.containerName == nil && $0.signature == "Broken" })
        #expect(fallbacks.contains { $0.containerName == "Foo" && $0.signature == "broken()" })
        #expect(fallbacks.contains { $0.containerName == "Foo" && $0.signature == "count: Broken" })
    }

    @Test("the diff carries per-side fallbacks even when key collisions are absent")
    func diffDiagnostics() throws {
        let clean = ABISnapshot(types: [container("Foo", members: [cleanRecord("fine")])])
        let falling = ABISnapshot(types: [container("Foo", members: [cleanRecord("fine"), fallbackRecord("broken()")])])

        #expect(ABIDiffer().diff(old: clean, new: clean).diagnostics == nil)

        let diagnostics = try #require(ABIDiffer().diff(old: clean, new: falling).diagnostics)
        #expect(diagnostics.oldSideKeyCollisions.isEmpty && diagnostics.newSideKeyCollisions.isEmpty)
        #expect(diagnostics.oldSideRemangleFallbacks.isEmpty)
        #expect(diagnostics.newSideRemangleFallbacks.map(\.signature) == ["broken()"])
    }

    @Test("the diff reporter appends the fallback warnings section")
    func diffReporterWarnings() {
        let falling = ABISnapshot(types: [container("Foo", members: [fallbackRecord("broken()")])])
        let report = ABIDiffReporter().report(ABIDiffer().diff(old: falling, new: falling))
        #expect(report == """
        No ABI changes.

        Warnings — remangle-fallback keys (print-derived identity; removed+added may be an identity flip across toolchains):
          old · Foo · broken()
          new · Foo · broken()
        """)
    }

    @Test("the evolution carries per-version fallbacks aligned with the axis, nil when clean")
    func evolutionDiagnostics() throws {
        let clean = ABISnapshot(types: [container("Foo", members: [cleanRecord("fine")])])
        let falling = ABISnapshot(types: [container("Foo", members: [cleanRecord("fine"), fallbackRecord("broken()")])])

        let cleanEvolution = try ABIEvolutionBuilder().evolution(
            of: [clean, clean].map { ABISnapshotDocument(snapshot: $0) }
        )
        #expect(cleanEvolution.remangleFallbacksByVersion == nil)

        let evolution = try ABIEvolutionBuilder().evolution(
            of: [clean, falling, clean].map { ABISnapshotDocument(snapshot: $0) },
            labels: ["1.0", "2.0", "3.0"]
        )
        let remangleFallbacksByVersion = try #require(evolution.remangleFallbacksByVersion)
        #expect(remangleFallbacksByVersion.map(\.count) == [0, 1, 0])

        let report = ABIEvolutionReporter().report(evolution)
        #expect(report.hasSuffix("""
        Warnings — remangle-fallback keys (print-derived identity; removed+added may be an identity flip across toolchains):
          2.0 · Foo · broken()
        """))
    }
}
