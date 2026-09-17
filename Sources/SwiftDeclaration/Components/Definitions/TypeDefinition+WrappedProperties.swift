@_spi(Internals) import Demangling
import Dependencies
import MachOSwiftSection
import SwiftDeclarationRendering
@_spi(Internals) import MachOSymbols

/// Wrapped-property recovery, the last step of `TypeDefinition.index(in:)`.
///
/// For every stored field `_x` whose type is a property wrapper, the
/// definition gains a `WrappedPropertyDefinition` (see that type for what
/// it carries). A field is a wrapper's storage when its nominal type has
/// `wrappedValue` accessors: first looked for in this image's own symbol
/// index (which also knows an internal wrapper), then in the export tries
/// the image's `PropertyWrapperTypeCatalog` can reach (a wrapper from
/// another image). A field whose type is not a wrapper — a hand-written
/// `_manual` behind a computed `manual` — is left alone: `Int` has no
/// `wrappedValue`.
extension TypeDefinition {
    package func recoverWrappedProperties(in machO: some MachOSwiftSectionRepresentableWithCache) {
        @Dependency(\.symbolIndexStore)
        var symbolIndexStore
        let catalog = PropertyWrapperTypeCatalogStore.shared.catalog(for: machO)
        var recovered: [WrappedPropertyDefinition] = []
        for field in fields where !field.flags.contains(.isArtificial) && field.name.hasPrefix("_") && field.name.count > 1 {
            let propertyName = String(field.name.dropFirst())
            let fieldTypeNode = field.typeNode.materialize()
            guard let wrapperNominalTypeNode = WrappedPropertyRecovery.nominalTypeNode(ofFieldType: fieldTypeNode) else { continue }
            let wrapperTypeName = TypeName(
                node: InternedNodeReferenceCache.shared.reference(interning: wrapperNominalTypeNode, in: machO),
                kind: wrapperNominalTypeNode.typeKind ?? .struct
            )
            let ownImageEvidence = WrappedPropertyRecovery.evidence(
                fromWrappedValueSymbols: symbolIndexStore.memberSymbols(
                    of: .variable(inExtension: false, isStatic: false, isStorage: false),
                    .variable(inExtension: false, isStatic: false, isStorage: true),
                    .variable(inExtension: true, isStatic: false, isStorage: false),
                    for: wrapperTypeName.name,
                    node: wrapperTypeName.node,
                    in: machO
                )
            )
            guard let evidence = ownImageEvidence ?? catalog.evidence(forWrapperCandidate: wrapperNominalTypeNode) else { continue }

            let declaredMember = variables.first { $0.name == propertyName }
            let origin: WrappedPropertyDefinition.Origin
            let declaredTypeNode: Node?
            if let declaredMember {
                origin = .declaredMember
                declaredTypeNode = WrappedPropertyRecovery.declaredTypeNode(of: declaredMember)
            } else {
                // The accessors are stripped: the declaration has to be
                // rebuilt from the wrapper's own `wrappedValue` type with the
                // field's generic arguments substituted. A wrapper whose
                // `wrappedValue` type the substitution cannot express is not
                // guessed at; `_x` then stays a stored field.
                guard let wrappedValueTypeNode = evidence.wrappedValueTypeNode,
                      let substitutedTypeNode = WrappedPropertyRecovery.substitutingGenericArguments(ofBoundType: fieldTypeNode, into: wrappedValueTypeNode)
                else { continue }
                origin = .synthesized(
                    declaredTypeNode: InternedNodeReferenceCache.shared.reference(interning: substitutedTypeNode, in: machO),
                    hasSetter: evidence.hasSetter
                )
                declaredTypeNode = substitutedTypeNode
            }
            let attributeTypeNode = WrappedPropertyRecovery.attributeTypeNode(
                fieldTypeNode: fieldTypeNode,
                wrapperNominalTypeNode: wrapperNominalTypeNode,
                wrappedPropertyTypeNode: declaredTypeNode
            )
            recovered.append(WrappedPropertyDefinition(
                name: propertyName,
                backingFieldName: field.name,
                projectionName: "$" + propertyName,
                attributeTypeNode: InternedNodeReferenceCache.shared.reference(interning: attributeTypeNode, in: machO),
                origin: origin
            ))
        }
        wrappedProperties = recovered
    }
}

/// The node-level rules of wrapped-property recovery, kept free of any
/// image so they can be pinned on hand-built trees.
package enum WrappedPropertyRecovery {
    /// The `.type`-wrapped nominal a field's type node names, generic
    /// arguments stripped — the shape a `TypeName.node` has. `nil` for
    /// anything that is not a plain or bound-generic struct / class / enum.
    package static func nominalTypeNode(ofFieldType typeNode: Node) -> Node? {
        guard typeNode.kind == .type, let inner = typeNode.firstChild else { return nil }
        switch inner.kind {
        case .structure, .class, .enum:
            return typeNode
        case .boundGenericStructure, .boundGenericClass, .boundGenericEnum:
            guard let nominal = inner.firstChild, nominal.kind == .type else { return nil }
            return nominal
        default:
            return nil
        }
    }

    /// The generic arguments a bound field type carries, in order; empty
    /// for a non-generic wrapper.
    package static func genericArguments(ofBoundType typeNode: Node) -> [Node] {
        guard let inner = typeNode.firstChild,
              inner.kind == .boundGenericStructure || inner.kind == .boundGenericClass || inner.kind == .boundGenericEnum,
              let typeList = inner.children.first(where: { $0.kind == .typeList })
        else { return [] }
        return Array(typeList.children)
    }

    /// How the wrapper is spelled in the attribute. When the wrapper takes
    /// exactly one generic argument and that argument is the wrapped
    /// property's own type, the compiler infers it and the attribute is
    /// bare (`@State var x: Int`); otherwise the arguments stay
    /// (`@Tagged<String, Int> var count: Int`). Both are valid source.
    package static func attributeTypeNode(fieldTypeNode: Node, wrapperNominalTypeNode: Node, wrappedPropertyTypeNode: Node?) -> Node {
        let arguments = genericArguments(ofBoundType: fieldTypeNode)
        guard arguments.count == 1, let onlyArgument = arguments.first, let wrappedPropertyTypeNode, onlyArgument == wrappedPropertyTypeNode else {
            return fieldTypeNode
        }
        return wrapperNominalTypeNode
    }

    /// The declared type of a member variable, read off its symbol node —
    /// past the `global` wrapper (skipping an async / merged-function
    /// marker), past `static`, a `getter` / `setter`, a `methodDescriptor`
    /// or a `protocolWitness`, down to the `variable` node's `type` child.
    package static func declaredTypeNode(of variable: VariableDefinition) -> Node? {
        var node = variable.node.materialize()
        for _ in 0 ..< 6 where node.kind != .variable {
            switch node.kind {
            case .global:
                guard let first = node.firstChild else { return nil }
                let skipsFirst = first.kind == .asyncFunctionPointer || first.kind == .asyncSuspendResumePartialFunction || first.kind == .mergedFunction
                guard let next = skipsFirst ? node.children.dropFirst().first : first else { return nil }
                node = next
            case .static, .getter, .setter, .modifyAccessor, .methodDescriptor:
                guard let next = node.firstChild else { return nil }
                node = next
            case .protocolWitness:
                guard let next = node.children.dropFirst().first else { return nil }
                node = next
            default:
                return nil
            }
        }
        guard node.kind == .variable else { return nil }
        return node.children.first(where: { $0.kind == .type })
    }

    /// The evidence this image's own symbols give for a wrapper candidate:
    /// its `wrappedValue` accessor symbols, if the index holds any.
    package static func evidence(fromWrappedValueSymbols symbols: [DemangledSymbol]) -> PropertyWrapperEvidence? {
        var wrappedValueTypeNode: Node?
        var hasSetter = false
        var matched = false
        for symbol in symbols {
            guard let shape = WrappedValueAccessorSymbol.shape(of: symbol.demangledNode.materialize()) else { continue }
            matched = true
            hasSetter = hasSetter || shape.isSetter
            if wrappedValueTypeNode == nil, let typeNode = shape.typeNode {
                wrappedValueTypeNode = typeNode
            }
        }
        guard matched else { return nil }
        return PropertyWrapperEvidence(wrappedValueTypeNode: wrappedValueTypeNode, hasSetter: hasSetter)
    }

    /// `wrappedValueTypeNode` with every depth-0 generic parameter reference
    /// replaced by the corresponding argument of `boundTypeNode`
    /// (`A` under `EnvironmentObject<Model>` becomes `Model`). `nil` when a
    /// reference has no argument to take — a deeper depth (the wrapper is
    /// nested in a generic context) or an index past the argument list —
    /// so a half-substituted type never renders.
    package static func substitutingGenericArguments(ofBoundType boundTypeNode: Node, into wrappedValueTypeNode: Node) -> Node? {
        let arguments = genericArguments(ofBoundType: boundTypeNode)
        return substitute(in: wrappedValueTypeNode, arguments: arguments)
    }

    private static func substitute(in node: Node, arguments: [Node]) -> Node? {
        if node.kind == .type, let parameter = node.firstChild, parameter.kind == .dependentGenericParamType, node.children.count == 1 {
            guard let depth = parameter.children.first?.index, depth == 0,
                  let index = parameter.children.dropFirst().first?.index,
                  index < UInt64(arguments.count)
            else { return nil }
            return arguments[Int(index)]
        }
        if node.kind == .dependentGenericParamType {
            return nil
        }
        if node.children.isEmpty {
            return node
        }
        var substitutedChildren: [Node] = []
        substitutedChildren.reserveCapacity(node.children.count)
        for child in node.children {
            guard let substituted = substitute(in: child, arguments: arguments) else { return nil }
            substitutedChildren.append(substituted)
        }
        // Contents and children are mutually exclusive on a node, so an inner
        // node is rebuilt from its kind and the substituted children alone.
        return Node.createTransient(kind: node.kind, children: substitutedChildren)
    }
}
