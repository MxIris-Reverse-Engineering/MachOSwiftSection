import Foundation
import SwiftDeclaration
@_spi(Support) import SwiftIndexing
@_spi(Support) import SwiftPrinting
import SwiftDiffing
import SwiftDeclarationRendering
import MachOSwiftSection
import Semantic
import Demangling
import OrderedCollections

/// Renders a **full Swift interface annotated with diff markers** — a git-diff
/// style view of how the new binary's ABI surface differs from the old.
///
/// It is the rendering analogue of ``ABIDiffer``: where the differ produces a
/// machine-readable change list, this produces the *whole* interface (every
/// declaration, changed or not) with each line classified as `added` (`+`),
/// `removed` (`-`), or `unchanged` (a space). It is structure-driven — the
/// shared ``InterfaceUnionWalker`` walks the two indexed models as a 2-version
/// axis, matches declarations on the same `ABIKey` the differ uses, and emits
/// each member from its own per-member printer so a single member's lines can
/// carry its own marker. A modified member shows as its old line (`-`)
/// immediately followed by its new line (`+`). The two-sided presentation
/// itself lives in ``DiffUnionStrategy``.
///
/// The renderer deliberately produces a *classified* stream — a block-grouped
/// `[[DiffLine]]` — and never bakes a diff symbol in. How a ``DiffMarker``
/// becomes concrete output (git-diff prefixes, a unified-diff hunk, HTML, …) is
/// the job of a ``DiffFormat``; ``printAnnotatedInterface(format:)`` defaults to
/// ``DiffFormat/inline``, which emits the git-diff-style `+`/`-`/` ` line prefix
/// at column 0 followed by a one-space gutter so column 0 is dedicated to the
/// marker and content always starts at column 2.
///
/// Surface is FULL: public, package, internal, and private declarations are all
/// rendered (private discriminators kept). Access-level splitting is a future
/// refinement, not a filter.
///
/// Build two ``SwiftDiffableInterfaceBuilder``s, `prepare()` each, then hand them
/// here. The two binaries may be different `MachO` types (e.g. a standalone
/// dylib vs a dyld-cache image), so the renderer is generic over both — the
/// generic parameters are erased at construction (each side becomes an
/// `InterfaceVersionUnit`), so they carry type-checking meaning only.
public final class SwiftDiffableInterfaceRenderer<
    OldMachO: FieldLayoutRenderable,
    NewMachO: FieldLayoutRenderable
>: Sendable {
    /// `[old, new]` — the two-version axis the shared walker consumes.
    private let versions: [any InterfaceVersionRendering]

    public init(old: SwiftDiffableInterfaceBuilder<OldMachO>, new: SwiftDiffableInterfaceBuilder<NewMachO>) {
        // Each unit's printer shares its builder's indexer dispatcher, so the
        // handlers the host passed to the builder cover printing too (see
        // `InterfaceVersionUnit`).
        self.versions = [InterfaceVersionUnit(builder: old), InterfaceVersionUnit(builder: new)]
    }

    /// Produces the annotated interface in the chosen ``DiffFormat`` (default
    /// ``DiffFormat/inline``, the git-diff-style `+`/`-`/` ` markers with a
    /// one-space gutter). The classified stream comes from
    /// ``annotatedDiffBlocks()``; the format turns it into the final string.
    public func printAnnotatedInterface(format: DiffFormat = .inline) async -> SemanticString {
        await format.render(annotatedDiffBlocks())
    }

    /// The full classified diff as a block-grouped, single-line-split stream: the
    /// outer array is the top-level declaration blocks in render order (globals →
    /// types → protocols → extensions), each inner array is one block's lines.
    /// Empty blocks are dropped. This is the structured input every ``DiffFormat``
    /// consumes; expose it for callers that need the raw classification rather
    /// than a rendered string.
    @_spi(Support)
    public func annotatedDiffBlocks() async -> [[DiffLine]] {
        await InterfaceUnionWalker(versions: versions, strategy: DiffUnionStrategy(versions: versions)).blocks()
    }
}

/// The two-sided emission strategy: reads the walker's matches as
/// `[old, new]` and presents them as git-diff markers.
struct DiffUnionStrategy: InterfaceUnionEmitting {
    typealias Line = DiffLine

    /// Both sides' resolved headers plus the container's own marker, carried
    /// from header resolution to container assembly.
    struct ContainerHeader {
        let old: SemanticString
        let new: SemanticString
        let marker: DiffMarker
    }

    /// `[old, new]`.
    let versions: [any InterfaceVersionRendering]

    func resolveTypeHeader(elements: [TypeDefinition?], level: Int) async -> ContainerHeader? {
        await resolveContainerHeader(
            elements: elements,
            subject: { $0.typeName.name },
            kind: .type
        ) { versionIndex, definition in
            try await versions[versionIndex].printTypeHeader(definition, level: level)
        }
    }

    func resolveProtocolHeader(elements: [ProtocolDefinition?], level: Int) async -> ContainerHeader? {
        await resolveContainerHeader(
            elements: elements,
            subject: { $0.protocolName.name },
            kind: .protocol
        ) { versionIndex, definition in
            try await versions[versionIndex].printProtocolHeader(definition, level: level)
        }
    }

    func resolveExtensionHeader(header: SemanticString, elements: [ExtensionUnionContainer?]) -> ContainerHeader {
        ContainerHeader(old: header, new: header, marker: containerMarker(oldPresent: elements[0] != nil, newPresent: elements[1] != nil))
    }

    /// Three-way member emission, keyed by `identityKey` (matching
    /// `ABIDiffer.diffMembers`): an unchanged member emits its new side (` `),
    /// an added member its new side (`+`), a removed member its old side (`-`),
    /// and a modified member its old line (`-`) immediately followed by its
    /// new line (`+`) — unless the two sides *render* byte-identically: the
    /// payload key (a remangle) can differ while the rendered signature is
    /// identical (e.g. a symbolic reference or private discriminator the
    /// `.default` printing elides), and an identical `-`/`+` pair is pure
    /// noise, so it collapses to a single context line; the change-list still
    /// records the underlying ABI-key change for anyone who needs it.
    func memberUnits(match: UnionMatch<UnionRenderableMember>, scope: UnionMemberScope, level: Int) async -> [[DiffLine]] {
        switch (match.elements[0], match.elements[1]) {
        case (nil, nil):
            return []
        case (nil, let newMember?):
            return [DiffMarking.markedLines(await newMember.render(), marker: .added, indentLevel: level)]
        case (let oldMember?, nil):
            return [DiffMarking.markedLines(await oldMember.render(), marker: .removed, indentLevel: level)]
        case (let oldMember?, let newMember?):
            guard oldMember.payloadKey != newMember.payloadKey else {
                return [DiffMarking.markedLines(await newMember.render(), marker: .unchanged, indentLevel: level)]
            }
            let oldRendered = await oldMember.render()
            let newRendered = await newMember.render()
            guard oldRendered.string != newRendered.string else {
                return [DiffMarking.markedLines(newRendered, marker: .unchanged, indentLevel: level)]
            }
            return [
                DiffMarking.markedLines(oldRendered, marker: .removed, indentLevel: level),
                DiffMarking.markedLines(newRendered, marker: .added, indentLevel: level),
            ]
        }
    }

    func assembleContainer(header: ContainerHeader, key: ABIKey, bodyUnits: [[DiffLine]], level: Int) -> [DiffLine] {
        DiffContainerAssembler.assemble(oldHeader: header.old, newHeader: header.new, marker: header.marker, bodyUnits: bodyUnits, level: level)
    }

    // MARK: - Header outcomes

    /// What came of one side's header. Three states, not `SemanticString?`:
    /// "this side has no such declaration" and "this side has one but it would
    /// not render" both used to arrive as the same value, and conflating them
    /// substitutes an empty header for a real one — emitting members under a
    /// blank line, the exact defect the drop-whole rule exists to prevent.
    ///
    /// Header rendering can genuinely throw — it reads the declaration's name,
    /// generic signature and superclass, and demangles each (issue #102 is the
    /// field evidence that print-time `DemanglingError`s happen on real
    /// binaries) — plus, since evolution 0002, it re-materializes the wrapper
    /// from its descriptor. Swallowing that into an empty string emitted the
    /// type's members with no `struct Foo` line above them, silently.
    private enum HeaderOutcome {
        /// The declaration does not exist on this side (a pure add or remove).
        case absent
        case rendered(SemanticString)
        case failed
    }

    /// Both sides are ALWAYS attempted before resolving — never
    /// `guard let a, let b`, which would skip the second side the moment the
    /// first failed (see `resolveHeaders`).
    private func resolveContainerHeader<EnclosingDefinition>(
        elements: [EnclosingDefinition?],
        subject: (EnclosingDefinition) -> String,
        kind: SwiftIndexEvents.PrintingDefinitionKind,
        render: (Int, EnclosingDefinition) async throws -> SemanticString
    ) async -> ContainerHeader? {
        let oldOutcome = await headerOutcome(elements[0], subject: subject, kind: kind, versionIndex: 0, render)
        let newOutcome = await headerOutcome(elements[1], subject: subject, kind: kind, versionIndex: 1, render)
        guard let resolved = resolveHeaders(old: oldOutcome, new: newOutcome) else { return nil }
        return ContainerHeader(
            old: resolved.old,
            new: resolved.new,
            marker: containerMarker(oldPresent: elements[0] != nil, newPresent: elements[1] != nil)
        )
    }

    private func headerOutcome<EnclosingDefinition>(
        _ definition: EnclosingDefinition?,
        subject: (EnclosingDefinition) -> String,
        kind: SwiftIndexEvents.PrintingDefinitionKind,
        versionIndex: Int,
        _ render: (Int, EnclosingDefinition) async throws -> SemanticString
    ) async -> HeaderOutcome {
        guard let definition else { return .absent }
        do {
            return .rendered(try await render(versionIndex, definition))
        } catch {
            // Reported on the failing side's own dispatcher; `subject` is what
            // makes it actionable — the message used to name no declaration,
            // so an operator could see that something vanished but not what.
            versions[versionIndex].eventDispatcher.dispatch(
                .definitionPrintFailed(
                    context: .init(name: subject(definition), kind: kind),
                    error: error
                )
            )
            return .failed
        }
    }

    /// Decides what to render from two independently-attempted headers.
    ///
    /// A previous implementation short-circuited on the first failure, so a
    /// failure on the OLD side — the routine cross-version case — never even
    /// asked the new side, and returning nothing deleted the declaration, its
    /// members and all nested children from BOTH sides of the diff, even
    /// though the new side was fine.
    ///
    /// A side that merely does not exist contributes an empty header, which is
    /// how a pure add or remove has always rendered. A side that FAILED is
    /// different: if the other side rendered, it stands in (a valid declaration
    /// line, with the member diff below it intact); if the other side is absent
    /// or failed too, there is no line to print and the declaration is dropped —
    /// the original drop-whole rule, now scoped to the case that needs it.
    /// Either way `headerOutcome` has already dispatched the failure.
    private func resolveHeaders(
        old: HeaderOutcome,
        new: HeaderOutcome
    ) -> (old: SemanticString, new: SemanticString)? {
        switch (old, new) {
        case let (.rendered(oldHeader), .rendered(newHeader)):
            (old: oldHeader, new: newHeader)
        case let (.absent, .rendered(newHeader)):
            (old: SemanticString(), new: newHeader)
        case let (.rendered(oldHeader), .absent):
            (old: oldHeader, new: SemanticString())
        case let (.failed, .rendered(newHeader)):
            (old: newHeader, new: newHeader)
        case let (.rendered(oldHeader), .failed):
            (old: oldHeader, new: oldHeader)
        case (.failed, .absent), (.absent, .failed), (.failed, .failed), (.absent, .absent):
            nil
        }
    }

    private func containerMarker(oldPresent: Bool, newPresent: Bool) -> DiffMarker {
        !oldPresent ? .added : (!newPresent ? .removed : .unchanged)
    }
}
