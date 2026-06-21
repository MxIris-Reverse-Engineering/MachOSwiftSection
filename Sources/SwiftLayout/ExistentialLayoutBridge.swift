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
    func existentialLayout(forNode node: Node, in originImage: ImageReference<MachO>) throws -> TypeLayoutInfo {
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

    /// The layout of an existential metatype (`any P.Type`, `Any.Type`,
    /// `AnyObject.Type`): a metadata word plus one word per witness table.
    func existentialMetatypeLayout(forNode node: Node, in originImage: ImageReference<MachO>) throws -> TypeLayoutInfo {
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
    private static func existentialContainer(wordCount: Int) -> TypeLayoutInfo {
        let size = 8 * wordCount
        return TypeLayoutInfo(
            size: size,
            stride: max(1, size),
            alignmentMask: 7,
            extraInhabitantCount: TypeLayoutInfo.pointerSized.extraInhabitantCount,
            isBitwiseTakable: true
        )
    }
}
