import Foundation
import MachOKit
import MachOFoundation
import MachOSwiftSection
@_spi(Internals) import Demangling
@_spi(Internals) import SwiftInspection

/// How an opaque reference the rewriter could not expand is spelled in the
/// tree it leaves behind (evolution proposal
/// `opaque-reference-spelling-and-member-projection`).
///
/// Swift has exactly one syntax for *naming* an existing opaque archetype,
/// the textual-interface attribute
/// `@_opaqueReturnTypeOf("<owner declaration mangling>", <index>) __<args>`
/// (the generics book, "Textual interfaces"); the demangler's own
/// `<<opaque return type of …>>.0` is a description, not a type.
public enum OpaqueReferenceSpelling: Sendable, Hashable {
    /// The attribute as the compiler writes it — what an interface must
    /// contain to be accepted by a compiler.
    case textualInterface
    /// The same attribute followed by a comment naming the owner declaration
    /// in demangled form, `… /* (extension in Core):Core.P.f() -> some */`,
    /// for a reader rather than a compiler. The dump's spelling.
    case annotated
}

extension Node {
    /// Every `opaqueType` reference still in the tree — one the rewriter
    /// could not expand — replaced by a leaf carrying its spelling, so that
    /// every printer (the upstream `NodePrinter` the indexer freezes witness
    /// text with, a host's own resolver, `SwiftPrinting`) prints the same
    /// text. A member of such a reference keeps the parentheses the
    /// attribute grammar needs: `(@_opaqueReturnTypeOf("…", 0) __<X>).Element`.
    ///
    /// The owner declaration's mangling is what the reference carries by
    /// name, or what the descriptor a pointer-form reference points at says
    /// (its anonymous parent context's mangled name, else its own symbol).
    /// A reference whose owner cannot be named is left as it is.
    package func spellingUnexpandedOpaqueReferences(as spelling: OpaqueReferenceSpelling, in machO: some MachOSwiftSectionRepresentableWithCache) -> Node {
        guard contains(Node.Kind.opaqueType) else { return self }
        return UnexpandedOpaqueReferenceSpeller(spelling: spelling) { reference in
            Node.ownerDeclarationNode(of: reference, in: machO)
        }.rewrite(self)
    }

    /// ``spellingUnexpandedOpaqueReferences(as:in:)`` without an image:
    /// by-name references only, which is all a symbol-demangled signature
    /// carries (a symbol has no symbolic references). A pointer-form
    /// reference is left as it is.
    package func spellingUnexpandedOpaqueReferences(as spelling: OpaqueReferenceSpelling) -> Node {
        guard contains(Node.Kind.opaqueType) else { return self }
        return UnexpandedOpaqueReferenceSpeller(spelling: spelling) { reference in
            Node.ownerDeclarationNode(of: reference)
        }.rewrite(self)
    }

    /// The owner declaration a by-name reference (`opaqueReturnTypeOf`)
    /// names, or `nil` for any other reference kind.
    static func ownerDeclarationNode(of reference: Node) -> Node? {
        guard reference.isKind(of: .opaqueReturnTypeOf) else { return nil }
        return reference.firstChild
    }

    /// The owner declaration of a by-name or pointer-form reference; the
    /// pointer form reads its descriptor — in-process through the absolute
    /// pointer `SymbolicDemangler` stashes in the node, offline through the
    /// offset — and demangles the descriptor's context the way the runtime's
    /// `_swift_buildDemanglingForContext` does, falling back to the
    /// descriptor's own symbol when the context carries no mangled name.
    static func ownerDeclarationNode(of reference: Node, in machO: some MachOSwiftSectionRepresentableWithCache) -> Node? {
        if let ownerDeclaration = ownerDeclarationNode(of: reference) { return ownerDeclaration }
        guard reference.isKind(of: .opaqueTypeDescriptorSymbolicReference), let offset: Int = reference.index?.cast() else { return nil }
        var contextNode: Node?
        if machO is MachOImage, let absolutePointer = UnsafeRawPointer(bitPattern: offset) {
            if let descriptor: OpaqueTypeDescriptor = try? absolutePointer.readWrapperElement() {
                contextNode = try? SymbolicDemangler.demangleContext(for: .opaqueType(descriptor))
            }
        } else if let descriptor = try? OpaqueTypeDescriptor.resolve(from: offset, in: machO) {
            contextNode = try? SymbolicDemangler.demangleContext(for: .opaqueType(descriptor), in: machO)
            if contextNode == nil, let symbol = try? Symbol.resolve(from: offset, in: machO) {
                contextNode = try? symbol.demangledNode
            }
        }
        return contextNode?.first(of: .opaqueReturnTypeOf)?.firstChild
    }
}

/// The rewrite behind ``Node/spellingUnexpandedOpaqueReferences(as:in:)``.
private final class UnexpandedOpaqueReferenceSpeller: Node.Rewriter {
    private static let attributePrefix = "@_opaqueReturnTypeOf(\""

    private let spelling: OpaqueReferenceSpelling
    private let ownerDeclaration: (Node) -> Node?

    init(spelling: OpaqueReferenceSpelling, ownerDeclaration: @escaping (Node) -> Node?) {
        self.spelling = spelling
        self.ownerDeclaration = ownerDeclaration
    }

    override func visit(_ node: Node) -> Node {
        if node.isKind(of: .opaqueType) {
            guard let text = spelledText(of: node) else { return node }
            return Node.createTransient(kind: .identifier, contents: .text(text))
        }
        // Bottom-up, so a member's base has already been spelled when the
        // member is visited; `(…).Element` is how the compiler prints it.
        if node.isKind(of: .dependentMemberType), let baseTypeNode = node.firstChild, let leafText = Self.spelledLeafText(in: baseTypeNode) {
            let parenthesizedLeaf = Node.createTransient(kind: .identifier, contents: .text("(" + leafText + ")"))
            let parenthesizedBase = baseTypeNode.isKind(of: .type) ? Node.createTransient(kind: .type, children: [parenthesizedLeaf]) : parenthesizedLeaf
            var children = Array(node.children)
            children[0] = parenthesizedBase
            return Node.createTransient(kind: .dependentMemberType, children: children)
        }
        return node
    }

    private static func spelledLeafText(in baseTypeNode: Node) -> String? {
        let leaf = baseTypeNode.isKind(of: .type) ? baseTypeNode.firstChild : baseTypeNode
        guard let leaf, leaf.isKind(of: .identifier), let text = leaf.text, text.hasPrefix(attributePrefix) else { return nil }
        return text
    }

    /// `@_opaqueReturnTypeOf("$s…", n) __<A, B>`: the owner declaration's
    /// mangling (its symbol, `$s` prefix and all — the descriptor's symbol
    /// is this plus `QOMQ`), the node's own ordinal, and its generic
    /// arguments flattened in depth order, the order the compiler's
    /// `resolveOpaqueReturnType` reads them back in.
    private func spelledText(of opaqueTypeNode: Node) -> String? {
        guard let reference = opaqueTypeNode[safeChild: 0],
              let ordinal = opaqueTypeNode[safeChild: 1]?.index,
              let ownerDeclaration = ownerDeclaration(reference),
              let symbolName = try? mangleAsString(Node.createTransient(kind: .global, children: [ownerDeclaration]))
        else { return nil }
        // The remangler spells a symbol (`_$s…`); the attribute takes the
        // mangling (`$s…`), which is what `swift-demangle` reads too.
        let mangledName = symbolName.hasPrefix("_") ? String(symbolName.dropFirst()) : symbolName
        let arguments = Node.opaqueTypeGenericArgumentsByDepth(of: opaqueTypeNode).values.flatMap { $0 }
        var text = "@_opaqueReturnTypeOf(\"\(mangledName)\", \(ordinal)) __"
        if !arguments.isEmpty {
            text += "<" + arguments.map { $0.print(using: .default) }.joined(separator: ", ") + ">"
        }
        if spelling == .annotated {
            text += " /* " + ownerDeclaration.print(using: .default) + " */"
        }
        return text
    }
}
