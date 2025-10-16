/// An entry in the remangler's substitution map.
///
/// This struct represents a substitutable node in the demangling tree, along with
/// metadata for efficient lookup and comparison.
struct SubstitutionEntry: Hashable {
    /// The node being substituted
    let node: Node?

    /// Precomputed hash value for efficient lookup
    let storedHash: Int

    /// Whether to treat this node as an identifier (affects equality comparison)
    let treatAsIdentifier: Bool

    init(node: Node?, storedHash: Int, treatAsIdentifier: Bool) {
        self.node = node
        self.storedHash = storedHash
        self.treatAsIdentifier = treatAsIdentifier
    }

    /// Create an empty entry
    static var empty: SubstitutionEntry {
        return SubstitutionEntry(node: nil, storedHash: 0, treatAsIdentifier: false)
    }

    /// Check if this entry is empty
    var isEmpty: Bool {
        return node == nil
    }

    /// Check if this entry matches a given node and identifier treatment
    func matches(node: Node?, treatAsIdentifier: Bool) -> Bool {
        // Use pointer equality for fast path
        return self.node === node && self.treatAsIdentifier == treatAsIdentifier
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(storedHash)
    }

    static func == (lhs: SubstitutionEntry, rhs: SubstitutionEntry) -> Bool {
        // Fast path: check hash first
        if lhs.storedHash != rhs.storedHash {
            return false
        }

        // Check treatment mode
        if lhs.treatAsIdentifier != rhs.treatAsIdentifier {
            return false
        }

        // Handle nil nodes
        guard let lhsNode = lhs.node, let rhsNode = rhs.node else {
            return lhs.node == nil && rhs.node == nil
        }

        // Use appropriate equality check
        if lhs.treatAsIdentifier {
            return identifierEquals(lhsNode, rhsNode)
        } else {
            return deepEquals(lhsNode, rhsNode)
        }
    }

    // MARK: - Helper Methods

    /// Check if two nodes are equal as identifiers.
    ///
    /// This handles special cases like operator character translation.
    private static func identifierEquals(_ lhs: Node, _ rhs: Node) -> Bool {
        // Fast path: same kind and text
        if lhs.kind == rhs.kind && lhs.text == rhs.text {
            return true
        }

        // Both must have text
        guard let lhsText = lhs.text, let rhsText = rhs.text else {
            return false
        }

        // Length must match
        guard lhsText.count == rhsText.count else {
            return false
        }

        // Check if we need to translate operator characters
        let needsTranslation = lhs.kind.isOperatorKind || rhs.kind.isOperatorKind

        if needsTranslation {
            // Slow path: compare character by character with translation
            return lhsText.elementsEqual(rhsText) { lhsChar, rhsChar in
                let lhsTranslated = lhs.kind.isOperatorKind ? Mangle.translateOperatorChar(lhsChar) : lhsChar
                let rhsTranslated = rhs.kind.isOperatorKind ? Mangle.translateOperatorChar(rhsChar) : rhsChar
                return lhsTranslated == rhsTranslated
            }
        } else {
            // Fast path for non-operators
            return lhsText == rhsText
        }
    }

    /// Perform deep equality comparison of two nodes.
    private static func deepEquals(_ lhs: Node, _ rhs: Node) -> Bool {
        // Nodes must be similar (same kind, same text/index)
        guard lhs.isSimilar(to: rhs) else {
            return false
        }

        // Check all children recursively
        guard lhs.children.count == rhs.children.count else {
            return false
        }

        for (lhsChild, rhsChild) in zip(lhs.children, rhs.children) {
            if !deepEquals(lhsChild, rhsChild) {
                return false
            }
        }

        return true
    }
}

// MARK: - Node Extensions

extension Node.Kind {
    /// Check if this node kind represents an operator
    var isOperatorKind: Bool {
        switch self {
        case .infixOperator,
             .prefixOperator,
             .postfixOperator:
            return true
        default:
            return false
        }
    }
}

extension Node {
    /// Check if this node is similar to another node.
    ///
    /// Similarity means same kind and same text/index, but not necessarily same children.
    func isSimilar(to other: Node) -> Bool {
        // Kind must match
        guard kind == other.kind else {
            return false
        }

        // Check text
        if let selfText = text {
            if selfText != other.text {
                return false
            }
        } else if other.text != nil {
            return false
        }

        // Check index
        if let selfIndex = index {
            if selfIndex != other.index {
                return false
            }
        } else if other.index != nil {
            return false
        }

        return true
    }
}
