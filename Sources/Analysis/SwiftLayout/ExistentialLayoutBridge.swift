import MachOSwiftSection
import Demangling
@_spi(Internals) import SwiftInspection

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

    /// The layout of a constrained ("extended") existential still in its
    /// symbolic form — a shape reference plus generalization arguments
    /// (SE-0353). `SymbolicDemangler` hands a field's over as the
    /// `constrainedExistential` it stands for (evolution proposal
    /// `existential-any`), which ``existentialLayout(forNode:in:)`` lays out;
    /// this path serves a tree that did not come through it. The arguments and
    /// requirements do **not** change the container's size: `any P<Int>` has the
    /// same representation as `any P` (opaque buffer + metadata + one witness
    /// table per protocol).
    func extendedExistentialLayout(forNode node: Node, in originImage: ImageReference<MachO>) throws -> StaticTypeLayout {
        let unwrapped = (node.kind == .type ? node.firstChild : node) ?? node
        guard let existentialType = ExtendedExistentialTypeResolution.existentialType(of: unwrapped) else {
            throw LayoutResolutionError.unknown(.unsupportedTypeKind(nodeKindName: "extendedExistential(no-shape)"))
        }
        let resolvedExistential = (existentialType.kind == .type ? existentialType.firstChild : existentialType) ?? existentialType
        // A constrained existential metatype (`any P<Int>.Type`) is a metadata
        // word plus the witness tables, not an existential container.
        if resolvedExistential.kind == .existentialMetatype {
            return try existentialMetatypeLayout(forNode: resolvedExistential, in: originImage)
        }
        return try existentialLayout(forNode: resolvedExistential, in: originImage)
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
        // A constrained existential (`any P<Int>`, or the instance of
        // `any P<Int>.Type`) is laid out as its protocol list: the constraints
        // pick the witness tables, they do not add any.
        if unwrapped.kind == .constrainedExistential, let constrainedProtocols = unwrapped.firstChild {
            return try existentialComposition(of: constrainedProtocols, in: image)
        }
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
            switch imageUniverse.resolveProtocol(byQualifiedTypeName: qualifiedName) {
            case .swift(let classConstraint):
                if classConstraint == .class { isClassBound = true }
                witnessTableCount += 1
            case .objC:
                // A Swift-declared `@objc` protocol also has no Swift protocol
                // descriptor — its only runtime artifact is the ObjC protocol
                // record. Like an imported ObjC protocol it is class-bound and
                // contributes no Swift witness table.
                isClassBound = true
            case nil:
                // `Error` reaching this point is part of a composition, where it
                // contributes an ordinary (non-class) witness table.
                guard qualifiedName == errorProtocolName else {
                    throw LayoutResolutionError.unknown(.typeDescriptorNotFound(qualifiedTypeName: qualifiedName))
                }
                witnessTableCount += 1
            }
        }
        return ExistentialComposition(
            witnessTableCount: witnessTableCount,
            isClassBound: isClassBound,
            isError: false
        )
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
    /// with the metadata/object word providing the saturated managed-pointer
    /// extra-inhabitant count (0x7FFF_FFFF on 64-bit Darwin — measured
    /// identically for opaque, class-bound, `Error`, and existential-metatype
    /// containers), so `Optional<any …>` stays the same size.
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
