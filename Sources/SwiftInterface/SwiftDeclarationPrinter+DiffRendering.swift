import SwiftDeclaration
import SwiftAttributeInference
import MachOSwiftSection
import Semantic
import Demangling
@_spi(Support) import SwiftPrinting

/// Diff-only rendering entry points on `SwiftDeclarationPrinter`.
///
/// `SwiftDiffableInterfaceRenderer` composes a type's lines itself so it can
/// interleave `+`/`-` markers, so it needs the declaration *header* without a
/// body, plus standalone `deinit` / `associatedtype` lines. These live here — in
/// the diff module — rather than in `SwiftPrinting`, because they serve only the
/// diff path; keeping them out of the general printer removes the ambiguity of
/// diff-specific helpers sitting beside the shared rendering primitives. The
/// shared header rendering they delegate to (`renderTypeDeclarationHeader` /
/// `renderProtocolDeclarationHeader`) stays in `SwiftPrinting` as `package` API.
package extension SwiftDeclarationPrinter {
    /// Renders a type's declaration header (`struct Foo<A> : Bar`) — attributes
    /// plus the declaration line, with no opening brace, body, or trailing
    /// newline. Mirrors the header portion of `printTypeDefinition`; keep in sync.
    ///
    /// The type's own demangled leaf-name node is handed to the header renderer so
    /// a `private`/`fileprivate` type surfaces its discriminator (`(Name in _ABC)`);
    /// see `renderLeafName` in `SwiftPrinting` for why.
    @SemanticStringBuilder
    func printTypeHeader(_ typeDefinition: TypeDefinition, level: Int, displayParentName: Bool = false) async throws -> SemanticString {
        if !typeDefinition.isIndexed {
            try await typeDefinition.index(in: machO)
        }

        let typeAttributeInferrer = TypeAttributeInferrer()
        typeDefinition.attributes = typeAttributeInferrer.infer(for: typeDefinition)

        // Attributes each on their own line; the diff renderer adds indentation
        // when it marks the lines, so none is emitted here.
        for attribute in typeDefinition.attributes {
            Keyword(attribute.keyword)
            BreakLine()
        }

        try await renderTypeDeclarationHeader(
            for: typeDefinition.type,
            displayParentName: displayParentName,
            level: level,
            leafNameNode: leafNameNode(of: typeDefinition.typeName.node)
        )
    }

    /// Renders a protocol's declaration header (`protocol Foo : Bar where …`) with
    /// no opening brace, body, or trailing newline. Mirrors the header portion of
    /// `printProtocolDefinition`; keep in sync.
    @SemanticStringBuilder
    func printProtocolHeader(_ protocolDefinition: ProtocolDefinition, level: Int, displayParentName: Bool = false) async throws -> SemanticString {
        if !protocolDefinition.isIndexed {
            try await protocolDefinition.index(in: machO)
        }

        try await renderProtocolDeclarationHeader(
            for: protocolDefinition.protocol,
            displayParentName: displayParentName,
            leafNameNode: leafNameNode(of: protocolDefinition.protocolName.node)
        )
    }

    /// Renders the `deinit` keyword line.
    @SemanticStringBuilder
    func printDeinit() -> SemanticString {
        Keyword(.deinit)
    }

    /// Renders a single protocol associated-type requirement (`associatedtype Name`).
    @SemanticStringBuilder
    func printAssociatedType(_ name: String) -> SemanticString {
        Keyword(.associatedtype)
        Space()
        MemberDeclaration(name)
    }

    /// The declaration's own leaf-name node — the second child of the
    /// (`.type`-unwrapped) nominal node, which is an `.identifier` for an ordinary
    /// type or a `.privateDeclName` carrying the build-specific discriminator for a
    /// `private`/`fileprivate` one. The header renderer uses it to surface the
    /// discriminator; an unexpected shape yields `nil` and falls back to the bare
    /// name.
    private func leafNameNode(of nameNode: Node) -> Node? {
        let nominalNode = nameNode.kind == .type ? (nameNode.children.first ?? nameNode) : nameNode
        return nominalNode.children.at(1)
    }
}
