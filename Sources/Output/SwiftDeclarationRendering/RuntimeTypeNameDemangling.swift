@_spi(Internals) import Demangling
@_spi(Internals) import SwiftInspection

/// The one way this library turns a runtime metatype into a demangled node.
///
/// `_mangledTypeName` hands back the runtime's own name for the type
/// (`swift_getMangledTypeName` → `_swift_buildDemanglingForMetadata`), which
/// is its source-level name with one exception. A context the runtime has no
/// richer information about is spelled by its descriptor's address —
/// `AnonymousContext("$<address>", <parent>, TypeList())`, "an unstable
/// mangling ... by its pointer identity" (`stdlib/public/runtime/Demangle.cpp`,
/// `_buildDemanglingForContext`). The compiler parents every outermost
/// `private` / `fileprivate` type on such a context, so every private type
/// reaches us that way: as the specialized definition itself, as one of its
/// type arguments, or anywhere inside a field's type.
///
/// That address names nothing a reader can use. The interface printer has no
/// spelling for it and printed nothing — the separator after it dangled in
/// front of the name (`struct .WindowPortal<AppKit.ButtonContent>`), and a
/// private type lost its module and every enclosing type — while the stock
/// printer rendered it as `(unknown context at $…)`. So each anonymous context
/// is rewritten into what the name built from the descriptors carries
/// (`SymbolicDemangler.buildContextDescriptorMangling`): the private type
/// inside gets a `privateDeclName` when the image records the discriminator —
/// a symbol on the anonymous descriptor, or a `_symbolic` symbol naming the
/// type, which is what survives in the dyld shared cache
/// (`AnonymousContextPrivateDiscriminatorIndex`) — and the context is replaced
/// by its parent when it records nothing.
package enum RuntimeTypeNameDemangling {
    /// The runtime's name for `metatype`, with every anonymous context
    /// rewritten as described on the type. `nil` on runtimes that predate
    /// `_mangledTypeName` (macOS 11 / iOS 14 / tvOS 14 / watchOS 7) and when
    /// the runtime has no name for the type, so callers fall back to the
    /// unbound representation.
    ///
    /// Transient demangle: callers render the node and drop it, so the tree
    /// must not be interned into the global `NodeCache`.
    package static func node(forMetatype metatype: Any.Type) -> Node? {
        guard #available(macOS 11, iOS 14, tvOS 14, watchOS 7, *) else { return nil }
        guard let mangledTypeName = _mangledTypeName(metatype),
              let node = try? demangleAsNodeTransient(mangledTypeName, isType: true)
        else { return nil }
        var rewrittenNodes: [ObjectIdentifier: Node] = [:]
        return rewritingAnonymousContexts(in: node, rewrittenNodes: &rewrittenNodes)
    }

    /// The demangler hands back one instance for every back-reference to a
    /// substitution, so the tree is a DAG; memoizing by identity keeps the walk
    /// linear in the unique nodes. A subtree with no anonymous context comes
    /// back as the same instance.
    private static func rewritingAnonymousContexts(in node: Node, rewrittenNodes: inout [ObjectIdentifier: Node]) -> Node {
        if let rewrittenNode = rewrittenNodes[ObjectIdentifier(node)] {
            return rewrittenNode
        }
        let rewrittenNode: Node
        // `AnonymousContext` children: the address identifier, the parent
        // context, and an always-empty generic argument list — the runtime
        // gives an anonymous context no arguments of its own.
        if let privateTypeNode = privateTypeNode(renaming: node, rewrittenNodes: &rewrittenNodes) {
            rewrittenNode = privateTypeNode
        } else if node.kind == .anonymousContext, let parent = node.children.at(1) {
            rewrittenNode = rewritingAnonymousContexts(in: parent, rewrittenNodes: &rewrittenNodes)
        } else {
            var rewrittenChildren: [Node] = []
            rewrittenChildren.reserveCapacity(node.children.count)
            var hasRewrittenChild = false
            for child in node.children {
                let rewrittenChild = rewritingAnonymousContexts(in: child, rewrittenNodes: &rewrittenNodes)
                hasRewrittenChild = hasRewrittenChild || rewrittenChild !== child
                rewrittenChildren.append(rewrittenChild)
            }
            // Only a node with children can have a rewritten child, and a node's
            // children and contents are mutually exclusive, so rebuilding from
            // the children alone loses nothing.
            rewrittenNode = hasRewrittenChild ? Node.createTransient(kind: node.kind, children: rewrittenChildren) : node
        }
        rewrittenNodes[ObjectIdentifier(node)] = rewrittenNode
        return rewrittenNode
    }

    /// `Type(AnonymousContext("$<address>", parent, …), Identifier(name), …)`
    /// → `Type(parent, PrivateDeclName(Identifier(discriminator), Identifier(name)), …)`
    /// when this process's image records the discriminator of the anonymous
    /// context at that address; `nil` otherwise, leaving the node to the
    /// parent-only rewrite.
    private static func privateTypeNode(renaming node: Node, rewrittenNodes: inout [ObjectIdentifier: Node]) -> Node? {
        guard node.children.count >= 2,
              let anonymousContext = node.children.first,
              anonymousContext.kind == .anonymousContext,
              let parent = anonymousContext.children.at(1),
              let addressText = anonymousContext.children.first?.text,
              addressText.hasPrefix("$"),
              let address = UInt(addressText.dropFirst(), radix: 16),
              let anonymousContextAddress = UnsafeRawPointer(bitPattern: address),
              node.children[1].kind == .identifier,
              let privateDiscriminator = SymbolicDemangler.privateDiscriminator(forAnonymousContextAt: anonymousContextAddress)
        else { return nil }
        let privateDeclName = Node.createTransient(kind: .privateDeclName, children: [
            .createTransient(kind: .identifier, text: privateDiscriminator),
            node.children[1],
        ])
        var rewrittenChildren = [rewritingAnonymousContexts(in: parent, rewrittenNodes: &rewrittenNodes), privateDeclName]
        for remainingChild in node.children.dropFirst(2) {
            rewrittenChildren.append(rewritingAnonymousContexts(in: remainingChild, rewrittenNodes: &rewrittenNodes))
        }
        return Node.createTransient(kind: node.kind, children: rewrittenChildren)
    }
}
