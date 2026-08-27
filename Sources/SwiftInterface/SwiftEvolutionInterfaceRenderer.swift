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

/// Renders the **union interface** of N ≥ 2 versions of one module, each
/// declaration annotated with its lifecycle across the version axis — the
/// N-way emission strategy over ``InterfaceUnionWalker`` (the two-sided diff
/// strategy in ``SwiftDiffableInterfaceRenderer`` shares the same walk).
///
/// Division of labor (the load-bearing design decision):
///
/// - **Annotation facts come solely from `ABIEvolution`** via
///   ``EvolutionAnnotationIndex``. The walker computes each declaration's
///   `ABIKey` with the same construction `ABIDiffer` freezes into snapshots
///   and this strategy looks its lineage up; it never re-derives events
///   itself, so the annotated interface can never disagree with the lineage
///   report or the JSON. A lookup miss IS the "present throughout, never
///   changed" verdict (`ABIEvolution` materializes changed lineages only) and
///   renders with no annotation.
/// - **Rendered text comes from the live models**: every declaration renders
///   from the LAST version that has it, through that version's own printer —
///   which is also why a modified member shows a single line (its newest
///   generation), with the older shape carried in the annotation phrase.
///
/// Surface is FULL, matching the diff strategy: public, package, internal,
/// and private declarations all render. Protocols' symbol-stripped `pwtslot:`
/// requirement records are deliberately NOT rendered (they carry no
/// declaration; same as `diff --interface`) — their changes remain visible in
/// the lineage report and JSON.
struct SwiftEvolutionInterfaceRenderer: InterfaceUnionEmitting {
    typealias Line = EvolutionLine
    typealias ContainerHeader = SemanticString

    /// Oldest → newest, index-aligned with the evolution's version axis.
    private let versions: [any InterfaceVersionRendering]
    private let annotations: EvolutionAnnotationIndex

    init(versions: [any InterfaceVersionRendering], annotations: EvolutionAnnotationIndex) {
        self.versions = versions
        self.annotations = annotations
    }

    /// The full classified stream: the outer array is the top-level
    /// declaration blocks in render order (globals → types → protocols →
    /// extensions), each inner array one block's lines. Empty blocks are
    /// dropped.
    func annotatedBlocks() async -> [[EvolutionLine]] {
        await InterfaceUnionWalker(versions: versions, strategy: self).blocks()
    }

    // MARK: - InterfaceUnionEmitting

    func resolveTypeHeader(elements: [TypeDefinition?], level: Int) async -> SemanticString? {
        await latestRenderableHeader(
            elements: elements,
            subject: { $0.typeName.name },
            kind: .type
        ) { versionIndex, definition in
            try await versions[versionIndex].printTypeHeader(definition, level: level)
        }
    }

    func resolveProtocolHeader(elements: [ProtocolDefinition?], level: Int) async -> SemanticString? {
        await latestRenderableHeader(
            elements: elements,
            subject: { $0.protocolName.name },
            kind: .protocol
        ) { versionIndex, definition in
            try await versions[versionIndex].printProtocolHeader(definition, level: level)
        }
    }

    func resolveExtensionHeader(header: SemanticString, elements: [ExtensionUnionContainer?]) -> SemanticString {
        header
    }

    /// Renders the matched member from its latest present version and attaches
    /// its lifecycle annotation, anchored on the FIRST line — a member's
    /// attributes print inline, so its first line IS the declaration line (and
    /// a computed property's accessor block trails it; the annotation must not
    /// sink to the block's closing brace).
    func memberUnits(match: UnionMatch<UnionRenderableMember>, scope: UnionMemberScope, level: Int) async -> [[EvolutionLine]] {
        guard let latest = match.elements.reversed().compactMap({ $0 }).first else { return [] }
        let rendered = await latest.render()
        let annotation: EvolutionAnnotation? = switch scope {
        case .global:
            annotations.globalAnnotation(forKey: match.key)
        case .container(let containerKey):
            annotations.memberAnnotation(forContainerKey: containerKey, memberKey: match.key)
        }
        let lines = EvolutionMarking.annotatedLines(rendered, annotation: annotation, indentLevel: level, anchor: .firstLine)
        return lines.isEmpty ? [] : [lines]
    }

    func assembleContainer(header: SemanticString, key: ABIKey, bodyUnits: [[EvolutionLine]], level: Int) -> [EvolutionLine] {
        EvolutionContainerAssembler.assemble(
            header: header,
            annotation: annotations.containerAnnotation(forKey: key),
            bodyUnits: bodyUnits,
            level: level
        )
    }

    // MARK: - Header resolution

    /// Renders a container header from the latest version that can: walks the
    /// present versions newest → oldest, returning the first header that
    /// renders. Each failure is dispatched on ITS version's dispatcher
    /// (`definitionPrintFailed`, with the declaration named so the operator
    /// can see what degraded — issue #102's lesson), and `nil` comes back only
    /// when every present version failed, in which case the walker drops the
    /// whole declaration (members under no header are not valid Swift — the
    /// diff strategy's drop-whole rule, generalized to N sides).
    private func latestRenderableHeader<EnclosingDefinition>(
        elements: [EnclosingDefinition?],
        subject: (EnclosingDefinition) -> String,
        kind: SwiftIndexEvents.PrintingDefinitionKind,
        render: (Int, EnclosingDefinition) async throws -> SemanticString
    ) async -> SemanticString? {
        for versionIndex in elements.indices.reversed() {
            guard let definition = elements[versionIndex] else { continue }
            do {
                return try await render(versionIndex, definition)
            } catch {
                versions[versionIndex].eventDispatcher.dispatch(
                    .definitionPrintFailed(
                        context: .init(name: subject(definition), kind: kind),
                        error: error
                    )
                )
            }
        }
        return nil
    }
}
