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
/// `private` / `fileprivate` type on such a context, and every type declared
/// in a function or closure body on a chain of them (the type's own, one per
/// closure, the function's), so every private and local type reaches us that
/// way: as the specialized definition itself, as one of its type arguments,
/// or anywhere inside a field's type.
///
/// That address names nothing a reader can use. The interface printer has no
/// spelling for it and printed nothing — the separator after it dangled in
/// front of the name (`struct .WindowPortal<AppKit.ButtonContent>`), and a
/// private type lost its module and every enclosing type — while the stock
/// printer rendered it as `(unknown context at $…)`. So each anonymous context
/// is rewritten into what the name built from the descriptors carries
/// (`SymbolicDemangler.buildContextDescriptorMangling`), from the same sources
/// (evolution proposal `local-type-context-names`): the compiler's own name
/// for the type inside, which carries a local type's function and closure and
/// a private type's discriminator; a discriminator alone, which is all an OS
/// framework in the dyld shared cache records for a private type
/// (`AnonymousContextNameIndex`); and, for a local type nothing names, the
/// position-based name `(Name in $<address>)`. A private type the image
/// records nothing for loses the context, and demangles as if it were
/// internal.
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
        if let namedTypeNode = typeNode(renaming: node, rewrittenNodes: &rewrittenNodes) {
            rewrittenNode = namedTypeNode
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
    /// renamed the way the descriptors name the type, or `nil` when nothing
    /// names it, leaving the node to the parent-only rewrite:
    ///
    /// - the compiler's name for the type: a local type's
    ///   (`Visitor #1 in Holder.countValues()`), whose function or closure
    ///   stands in for every anonymous context above, or a private type's, put
    ///   under the runtime's own parent, which carries the arguments of a bound
    ///   enclosing type;
    /// - a private discriminator alone;
    /// - for a local type — an anonymous context whose parent is one too —
    ///   `(name in $<address>)` under the nearest context the runtime names.
    private static func typeNode(renaming node: Node, rewrittenNodes: inout [ObjectIdentifier: Node]) -> Node? {
        guard node.children.count >= 2,
              let anonymousContext = node.children.first,
              anonymousContext.kind == .anonymousContext,
              let parent = anonymousContext.children.at(1),
              let addressText = anonymousContext.children.first?.text,
              addressText.hasPrefix("$"),
              let address = UInt(addressText.dropFirst(), radix: 16),
              let anonymousContextAddress = UnsafeRawPointer(bitPattern: address),
              node.children[1].kind == .identifier,
              let name = node.children[1].text
        else { return nil }

        let context: Node
        let declarationName: Node
        if let compilerSpelledName = SymbolicDemangler.anonymousContextName(forAnonymousContextAt: anonymousContextAddress),
           let compilerSpelledContext = compilerSpelledName.children.first,
           let compilerSpelledDeclarationName = compilerSpelledName.children.at(1),
           compilerSpelledDeclarationName.kind == .localDeclName || compilerSpelledDeclarationName.kind == .privateDeclName,
           compilerSpelledDeclarationName.children.at(1)?.text == name {
            context = compilerSpelledDeclarationName.kind == .localDeclName ? compilerSpelledContext : rewritingAnonymousContexts(in: parent, rewrittenNodes: &rewrittenNodes)
            declarationName = compilerSpelledDeclarationName
        } else if let privateDiscriminator = SymbolicDemangler.privateDiscriminator(forAnonymousContextAt: anonymousContextAddress) {
            context = rewritingAnonymousContexts(in: parent, rewrittenNodes: &rewrittenNodes)
            declarationName = Node.createTransient(kind: .privateDeclName, children: [
                .createTransient(kind: .identifier, text: privateDiscriminator),
                node.children[1],
            ])
        } else if parent.kind == .anonymousContext, let positionName = SymbolicDemangler.positionName(forAnonymousContextAt: anonymousContextAddress) {
            context = rewritingAnonymousContexts(in: parent, rewrittenNodes: &rewrittenNodes)
            declarationName = Node.createTransient(kind: .privateDeclName, children: [
                .createTransient(kind: .identifier, text: positionName),
                node.children[1],
            ])
        } else {
            return nil
        }
        var rewrittenChildren = [context, declarationName]
        for remainingChild in node.children.dropFirst(2) {
            rewrittenChildren.append(rewritingAnonymousContexts(in: remainingChild, rewrittenNodes: &rewrittenNodes))
        }
        return Node.createTransient(kind: node.kind, children: rewrittenChildren)
    }
}
