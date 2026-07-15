import MachOSwiftSection
import Demangling

/// The fully-qualified name of the standard-library `Error` protocol, whose
/// bare existential (`any Error`) uses the special boxed representation.
private let errorProtocolName = "Swift.Error"

/// Existential-container layout for the resolver, ported from the Swift runtime
/// reflection lowering (`ExistentialTypeInfoBuilder` in `TypeLowering.cpp`):
///
/// - **Opaque** `any P` / protocol composition: a 3-word inline value buffer, a
///   value-metadata word, then one witness-table word per protocol —
///   `32 + 8 * witnessCount` bytes.
/// - **Class-bound** (`AnyObject`, a class-constrained protocol, an explicit
///   `AnyObject`/superclass member): a single retainable object word followed by
///   the witness tables — `8 * (1 + witnessCount)` bytes.
/// - **Error** (`any Error` alone): a single boxed reference word — 8 bytes.
/// - **Existential metatype** (`any P.Type`): a metadata word followed by the
///   witness tables — `8 * (1 + witnessCount)` bytes, regardless of class-bound.
///
/// Marker protocols (`Sendable`, `Copyable`, …) are already stripped from the
/// demangled protocol list by the compiler, so every listed protocol counts as
/// one witness table. A protocol whose class constraint cannot be resolved in
/// the current image scope degrades the field (the existential size is not
/// trustworthy), matching the runtime lowering's `markInvalid` behaviour.
extension StaticTypeLayoutResolver {
    /// The layout of an existential value (`any …`).
    func existentialLayout(forNode node: Node, in originImage: ImageReference<MachO>) throws -> StaticTypeLayout {
        let composition = try existentialComposition(of: node, in: originImage)
        if composition.isError {
            return Self.existentialContainer(wordCount: 1)
        }
        if composition.isClassBound {
            return Self.existentialContainer(wordCount: 1 + composition.witnessTableCount)
        }
        // Opaque: 3-word buffer + 1 metadata word + one word per witness table.
        return Self.existentialContainer(wordCount: 4 + composition.witnessTableCount)
    }

    /// The layout of a constrained ("extended") existential — `any P<Int>` or a
    /// same-type-constrained `any Sequence<Element == Int>` — encoded via an
    /// `extendedExistentialTypeShape` symbolic reference (SE-0353). The
    /// generalization arguments and requirement constraints do **not** change the
    /// container's size: `any P<Int>` has the same representation as `any P`
    /// (opaque buffer + metadata + one witness table per protocol). So the shape's
    /// inner existential (a plain `protocolList` / `…WithClass` / `…WithAnyObject`)
    /// is extracted and routed through the ordinary existential layout, which
    /// already handles the class-bound vs opaque distinction.
    func extendedExistentialLayout(forNode node: Node, in originImage: ImageReference<MachO>) throws -> StaticTypeLayout {
        guard let innerExistential = Self.constrainedExistentialInnerType(of: node) else {
            throw LayoutResolutionError.unknown(.unsupportedTypeKind(nodeKindName: "extendedExistential(no-shape)"))
        }
        // A constrained existential metatype (`any P<Int>.Type`) wraps the
        // existential in a metatype; route it through the metatype path.
        if innerExistential.kind == .existentialMetatype {
            return try existentialMetatypeLayout(forNode: innerExistential, in: originImage)
        }
        return try existentialLayout(forNode: innerExistential, in: originImage)
    }

    /// Extracts the plain existential type node (`protocolList` / `…WithClass` /
    /// `…WithAnyObject` / `existentialMetatype`) nested inside a
    /// `symbolicExtendedExistentialType`'s shape reference:
    /// `symbolicExtendedExistentialType → (unique|nonUnique)…ShapeSymbolicReference
    /// → constrainedExistential → Type → <existential>`.
    private static func constrainedExistentialInnerType(of node: Node) -> Node? {
        let unwrapped = (node.kind == .type ? node.firstChild : node) ?? node
        guard unwrapped.kind == .symbolicExtendedExistentialType else { return nil }
        guard let constrainedExistential = firstDescendant(of: unwrapped, kind: .constrainedExistential) else { return nil }
        // The constrained existential's first child is the `.type`-wrapped
        // existential (a protocol list); its second is the requirement list,
        // which does not affect layout.
        guard let typeChild = constrainedExistential.children.first(where: { $0.kind == .type }) else { return nil }
        return typeChild
    }

    /// The first descendant node of the given kind in a pre-order walk.
    private static func firstDescendant(of node: Node, kind: Node.Kind) -> Node? {
        if node.kind == kind { return node }
        for child in node.children {
            if let found = firstDescendant(of: child, kind: kind) { return found }
        }
        return nil
    }

    /// The layout of an existential metatype (`any P.Type`, `Any.Type`,
    /// `AnyObject.Type`): a metadata word plus one word per witness table.
    func existentialMetatypeLayout(forNode node: Node, in originImage: ImageReference<MachO>) throws -> StaticTypeLayout {
        guard let instanceType = node.firstChild else {
            throw LayoutResolutionError.unknown(.unsupportedTypeKind(nodeKindName: "existentialMetatype(no-instance)"))
        }
        let composition = try existentialComposition(of: instanceType, in: originImage)
        return Self.existentialContainer(wordCount: 1 + composition.witnessTableCount)
    }

    // MARK: - Composition analysis

    private struct ExistentialComposition {
        var witnessTableCount: Int
        var isClassBound: Bool
        var isError: Bool
    }

    /// Parses an existential node into its witness-table count and
    /// representation, resolving each protocol's class constraint.
    private func existentialComposition(
        of node: Node,
        in image: ImageReference<MachO>
    ) throws -> ExistentialComposition {
        let unwrapped = (node.kind == .type ? node.firstChild : node) ?? node
        let structurallyClassBound: Bool
        switch unwrapped.kind {
        case .protocolList:
            structurallyClassBound = false
        case .protocolListWithAnyObject, .protocolListWithClass:
            structurallyClassBound = true
        default:
            throw LayoutResolutionError.unknown(.unsupportedTypeKind(nodeKindName: "existential(\(unwrapped.kind))"))
        }

        let protocolNodes = Self.existentialProtocolNodes(in: unwrapped)

        // The bare `any Error` is the special boxed-error representation; an
        // `Error` appearing inside a composition is an ordinary witness table.
        if !structurallyClassBound,
           protocolNodes.count == 1,
           NodeTypeNaming.protocolQualifiedName(of: protocolNodes[0]) == errorProtocolName {
            return ExistentialComposition(witnessTableCount: 0, isClassBound: false, isError: true)
        }

        var isClassBound = structurallyClassBound
        var witnessTableCount = 0
        for protocolNode in protocolNodes {
            // An imported Objective-C protocol has no Swift protocol descriptor.
            // It is always class-bound and contributes no Swift witness table
            // (`id<P>` is a single class reference), so it forces the existential
            // class-bound and is not counted.
            if NodeTypeNaming.objCProtocolBareName(of: protocolNode) != nil {
                isClassBound = true
                continue
            }
            guard let qualifiedName = NodeTypeNaming.protocolQualifiedName(of: protocolNode) else {
                throw LayoutResolutionError.unknown(.demangleFailure)
            }
            let classConstraint = try resolveProtocolClassConstraint(forQualifiedName: qualifiedName)
            if classConstraint == .class { isClassBound = true }
            witnessTableCount += 1
        }
        return ExistentialComposition(
            witnessTableCount: witnessTableCount,
            isClassBound: isClassBound,
            isError: false
        )
    }

    /// Resolves a protocol's class constraint by qualified name, degrading the
    /// field when an out-of-image protocol (other than the well-known stdlib
    /// ones) cannot be resolved in single-image scope.
    private func resolveProtocolClassConstraint(forQualifiedName qualifiedName: String) throws -> ProtocolClassConstraint {
        if let constraint = imageUniverse.resolveProtocolClassConstraint(byQualifiedTypeName: qualifiedName) {
            return constraint
        }
        // `Error` reaching this point is part of a composition, where it
        // contributes an ordinary (non-class) witness table.
        if qualifiedName == errorProtocolName {
            return .any
        }
        throw LayoutResolutionError.unknown(.typeDescriptorNotFound(qualifiedTypeName: qualifiedName))
    }

    /// The `.protocol` component nodes of an existential node. For
    /// `.protocolList` the first child is the type list directly; for the
    /// `WithAnyObject` / `WithClass` variants the first child is a nested
    /// `.protocolList` whose first child is the type list.
    private static func existentialProtocolNodes(in node: Node) -> [Node] {
        var typeList = node.firstChild
        if typeList?.kind == .protocolList { typeList = typeList?.firstChild }
        guard let typeList, typeList.kind == .typeList else { return [] }
        return Array(typeList.children)
    }

    // MARK: - Containers

    /// An existential container of `wordCount` machine words: 8-byte aligned,
    /// with the metadata/object word providing the standard pointer extra
    /// inhabitants (so `Optional<any …>` stays the same size).
    private static func existentialContainer(wordCount: Int) -> StaticTypeLayout {
        let size = 8 * wordCount
        return StaticTypeLayout(
            size: size,
            stride: max(1, size),
            alignmentMask: 7,
            extraInhabitantCount: StaticTypeLayout.pointerSized.extraInhabitantCount,
            isBitwiseTakable: true
        )
    }
}
