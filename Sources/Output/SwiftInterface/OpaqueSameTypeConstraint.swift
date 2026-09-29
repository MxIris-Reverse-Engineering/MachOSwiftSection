import Demangling

/// One same-type constraint mined from an opaque type descriptor's generic
/// requirements, keeping the associated-type name and anchor protocol that
/// primary-associated-type attribution needs (the opaque-primary-associated-type-attribution evolution proposal).
struct OpaqueSameTypeConstraint {
    enum ArgumentSource {
        /// Direct pin (`τ.Name == X`): the concrete right-hand-side node.
        case node(Node)
        /// Reversed pin (`outer == τ.Name`): the dependent-member node, to be
        /// resolved through the provider's `SubstitutionMap` at render time.
        case substitutionRoot(Node)
    }

    let associatedTypeName: String
    let anchorProtocolName: String?
    let argumentSource: ArgumentSource
}

/// Parse result of a single-level dependent member type (`τ.Name`) with its
/// grouping parameter and optional anchor protocol.
struct OpaqueDependentMemberProjection {
    let parameterName: String
    let associatedTypeName: String
    let anchorProtocolName: String?

    /// Parses a `.type` node whose content is a single-level dependent member
    /// of a bare generic parameter. A nested path (`τ.Name.Sub`) cannot come
    /// from primary-associated-type sugar and yields `nil`.
    static func parse(typeNode: Node) async -> OpaqueDependentMemberProjection? {
        guard let dependentMemberNode = typeNode.children.first,
              dependentMemberNode.isKind(of: .dependentMemberType),
              let baseTypeNode = dependentMemberNode.children.at(0),
              let associatedTypeRefNode = dependentMemberNode.children.at(1),
              associatedTypeRefNode.isKind(of: .dependentAssociatedTypeRef),
              let parameterNode = baseTypeNode.children.first,
              parameterNode.isKind(of: .dependentGenericParamType),
              let parameterName = parameterNode.text,
              let identifierNode = associatedTypeRefNode.children.at(0),
              let associatedTypeName = identifierNode.text
        else { return nil }

        var anchorProtocolName: String?
        if let anchorNode = associatedTypeRefNode.children.at(1) {
            let printedAnchorName = await anchorNode.print(using: .opaqueTypeBuilderOnly)
            anchorProtocolName = printedAnchorName.isEmpty ? nil : printedAnchorName
        }
        return OpaqueDependentMemberProjection(
            parameterName: parameterName,
            associatedTypeName: associatedTypeName,
            anchorProtocolName: anchorProtocolName
        )
    }
}
