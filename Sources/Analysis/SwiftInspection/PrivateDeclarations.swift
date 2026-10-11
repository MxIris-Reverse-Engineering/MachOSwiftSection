@_spi(Internals) import Demangling

/// A private or fileprivate declaration a name reads (evolution proposal
/// `private-declarations`): the declaration's name, and the private
/// discriminator the compiler gave the file declaring it.
public struct PrivateDeclaration: Hashable, Sendable {
    /// The declaration's name: `EnabledKey`, `readEntryList`. A private
    /// initializer's or subscript's mangled name carries none of its own
    /// (`Holder.(in _C017…).init(argument:)`), so theirs reads `init` or
    /// `subscript`. `nil` only for a name of a shape nothing here expects.
    public let name: String?

    /// `_` followed by the 32 uppercase hexadecimal digits of
    /// `MD5(module name + source file name)`, the compiler's
    /// `SourceFile::getPrivateDiscriminator`.
    public let discriminator: String

    public init(name: String?, discriminator: String) {
        self.name = name
        self.discriminator = discriminator
    }
}

extension DemanglingNode {
    /// The private declarations this name reads, in the order it reads them,
    /// each once.
    ///
    /// A name printed for a reader leaves its discriminators out; this is
    /// where they are kept. The whole tree is read — the declaration's own
    /// name, every enclosing context, an extension's extended type and
    /// requirements, a specialized type's generic arguments — except for two
    /// parts:
    ///
    /// - The signature of a function, closure, variable, subscript or
    ///   initializer the name runs through: its argument labels, parameter
    ///   types and result type. A local type's name runs through the
    ///   function declaring it,
    ///   `InPrivateSignature #1 in M.Holder.(takes in _C017…)(M.(PrivateArgument in _C017…)) -> Any`,
    ///   and the name a reader is shown of it
    ///   (`DefinitionName.localTypeDisplayName`) leaves the signature out:
    ///   the method is read, `PrivateArgument` is not.
    /// - A position-based local type's address
    ///   (`LocalTypeNaming.positionBased`): `$1a2b3c` has a private name's
    ///   shape, but is no discriminator.
    public var privateDeclarations: [PrivateDeclaration] {
        var privateDeclarations: [PrivateDeclaration] = []
        // Walked with an explicit stack, in preorder: a name's tree has no
        // depth limit a recursion could rely on.
        var pendingNodes: [(node: Self, parentKind: Node.Kind?)] = [(self, nil)]
        while let (node, parentKind) = pendingNodes.popLast() {
            if node.kind == .privateDeclName {
                if let privateDeclaration = node.privateDeclaration(declaredBy: parentKind), !privateDeclarations.contains(privateDeclaration) {
                    privateDeclarations.append(privateDeclaration)
                }
                continue
            }
            let readsSignature = !node.kind.declaresSignature
            for child in node.children.reversed() where readsSignature || !child.kind.isSignaturePart {
                pendingNodes.append((child, node.kind))
            }
        }
        return privateDeclarations
    }

    /// Whether this is a position-based local type's private name: the
    /// address of the anonymous context wrapping the type, which a
    /// compiler-written discriminator never starts with.
    package var isPositionBasedPrivateName: Bool {
        kind == .privateDeclName && children.first?.text?.hasPrefix("$") == true
    }

    /// The declaration this `privateDeclName` names, under a parent of
    /// `parentKind`; `nil` for a position-based local type's.
    private func privateDeclaration(declaredBy parentKind: Node.Kind?) -> PrivateDeclaration? {
        guard !isPositionBasedPrivateName, let discriminator = children.first?.text else { return nil }
        if let name = children.at(1)?.text {
            return PrivateDeclaration(name: name, discriminator: discriminator)
        }
        switch parentKind {
        case .allocator?, .constructor?:
            return PrivateDeclaration(name: "init", discriminator: discriminator)
        case .subscript?:
            return PrivateDeclaration(name: "subscript", discriminator: discriminator)
        default:
            return PrivateDeclaration(name: nil, discriminator: discriminator)
        }
    }
}

extension Node.Kind {
    /// The declarations whose children include a signature: argument labels
    /// and a function type, or a variable's type. The children are laid out
    /// by the demangler's `demanglePlainFunction`, `demangleEntity`,
    /// `demangleFunctionEntity` and `demangleSubscript`; a private
    /// subscript's or initializer's `privateDeclName` is a child of its own,
    /// not part of the signature.
    fileprivate var declaresSignature: Bool {
        switch self {
        case .function, .variable, .subscript, .allocator, .constructor, .explicitClosure, .implicitClosure, .macro:
            return true
        default:
            return false
        }
    }

    fileprivate var isSignaturePart: Bool {
        self == .type || self == .labelList
    }
}
