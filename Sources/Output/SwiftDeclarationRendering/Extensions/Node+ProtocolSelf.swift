import Demangling

/// Reading the types of a protocol's requirement signature, where the
/// protocol's `Self` is the one generic parameter (`τ_0_0`).
extension Node {
    /// The associated type names of a type that is the protocol's `Self` or a
    /// chain of members rooted at it, root first: `["Second", "Leaf"]` for
    /// `Self.Second.Leaf`, `[]` for `Self` itself. `nil` for any other type,
    /// including a composite type that only mentions `Self` (`[Self.First]`).
    ///
    /// A member's protocol qualifier (`Self.Seventh.[Sequence]Element`) is not
    /// part of its name: Swift source cannot spell it, and the associated
    /// types of one name in a protocol and the protocols it refines are one
    /// type.
    package var protocolSelfMemberNames: [String]? {
        var memberNames: [String] = []
        var currentNode = self
        while true {
            switch currentNode.kind {
            case .type:
                guard currentNode.children.count == 1, let wrappedNode = currentNode.children.first else { return nil }
                currentNode = wrappedNode
            case .dependentMemberType:
                guard currentNode.children.count == 2,
                      let baseNode = currentNode.children.first,
                      let associatedTypeReference = currentNode.children.at(1),
                      associatedTypeReference.isKind(of: .dependentAssociatedTypeRef),
                      let memberName = associatedTypeReference.children.first?.text
                else { return nil }
                memberNames.append(memberName)
                currentNode = baseNode
            case .dependentGenericParamType:
                return currentNode.isProtocolSelfParameter ? memberNames.reversed() : nil
            default:
                return nil
            }
        }
    }

    /// The root of the first member chain in this type, in preorder, whose
    /// root is one of `associatedTypeNames`: `Second` for `Self.Second.Leaf`,
    /// for `[Self.Second]`, and for `(Self.Element, Self.Second)` when
    /// `Element` is not one of them. A chain's own subtree is not searched
    /// again: every inner chain has the same root.
    package func firstProtocolSelfMemberRoot(among associatedTypeNames: Set<String>) -> String? {
        var pendingNodes: [Node] = [self]
        while let node = pendingNodes.popLast() {
            if let memberNames = node.protocolSelfMemberNames {
                if let rootName = memberNames.first, associatedTypeNames.contains(rootName) {
                    return rootName
                }
                continue
            }
            pendingNodes.append(contentsOf: node.children.reversed())
        }
        return nil
    }

    /// The same tree printable as Swift source inside the protocol: the
    /// protocol's generic parameter spelled `Self` rather than by its position
    /// (`A`), and every member's protocol qualifier dropped
    /// (`strippingAssociatedTypeProtocolQualifiers()`), which the upstream
    /// `NodePrinter` would otherwise spell out (`Self.Seventh.Swift.Sequence.Element`).
    package func spellingProtocolSelfParameter() -> Node {
        ProtocolSelfParameterSpeller().rewrite(strippingAssociatedTypeProtocolQualifiers())
    }

    fileprivate var isProtocolSelfParameter: Bool {
        isKind(of: .dependentGenericParamType)
            && children.count == 2
            && children.first?.index == 0
            && children.at(1)?.index == 0
    }
}

/// Puts `.constrainedExistentialSelf` where the protocol's generic parameter
/// was: the one node kind both printers spell `Self` — swift-demangling's
/// `NodePrinter` as text, SwiftPrinting's type printer as the keyword. The
/// replacement is `NodeFactory`'s shared leaf, which outlives every print.
private final class ProtocolSelfParameterSpeller: Node.Rewriter {
    override func visit(_ node: Node) -> Node {
        node.isProtocolSelfParameter ? NodeFactory.constrainedExistentialSelf : node
    }
}
