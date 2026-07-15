import MachOSwiftSection
@_spi(Internals) import SwiftInspection
import Demangling

/// Resolves a `dependentMemberType` — an associated-type reference such as
/// `SomeType.Index` — to a concrete layout by looking up the conformance's
/// associated-type witness in `__swift5_assocty`.
///
/// This only fires **after** generic substitution has made the base concrete:
/// a generic type's field typed `A.Element` is reached only when the enclosing
/// type is a concrete instantiation (`Environment<Bool>`, `Wrapper<[Int16]>`),
/// at which point the environment has already replaced `A` with the concrete
/// argument, leaving `dependentMemberType(concreteBase, Protocol.Element)`. The
/// witness itself may still be dependent on the base's own generic parameters
/// (`Array`'s `Element` witness is `Array`'s element parameter), so it is
/// substituted a second time under an environment built from the base.
extension StaticTypeLayoutResolver {
    func dependentMemberTypeLayout(forNode node: Node, in originImage: ImageReference<MachO>) throws -> StaticTypeLayout {
        guard
            let baseTypeNode = node.firstChild,
            let associatedTypeReference = node.children.at(1),
            associatedTypeReference.kind == .dependentAssociatedTypeRef
        else {
            throw LayoutResolutionError.unknown(.unsupportedTypeKind(nodeKindName: "dependentMemberType(malformed)"))
        }

        // The base must have been substituted to a concrete nominal type. An
        // unsubstituted parameter (the type's own `A`, or a depth > 0 context)
        // degrades — matching the generic-parameter path.
        let unwrappedBase = unwrappedType(baseTypeNode)
        if unwrappedBase.kind == .dependentGenericParamType || unwrappedBase.kind == .dependentMemberType {
            throw LayoutResolutionError.unknown(.genericParameterUnsubstituted)
        }
        guard let conformingName = NodeTypeNaming.nominalQualifiedName(of: baseTypeNode) else {
            throw LayoutResolutionError.unknown(.demangleFailure)
        }

        // The associated-type reference carries the associated type's name and
        // the protocol declaring it.
        guard
            let associatedTypeName = associatedTypeReference.firstChild?.text,
            let protocolReferenceNode = associatedTypeReference.children.at(1),
            let protocolName = NodeTypeNaming.protocolQualifiedName(of: protocolReferenceNode)
        else {
            throw LayoutResolutionError.unknown(.demangleFailure)
        }

        let key = ImageReference<MachO>.associatedTypeWitnessKey(
            conformingName: conformingName,
            protocolName: protocolName,
            associatedTypeName: associatedTypeName
        )
        guard let witness = imageUniverse.resolveAssociatedTypeWitness(forKey: key) else {
            throw LayoutResolutionError.unknown(.typeDescriptorNotFound(qualifiedTypeName: "\(conformingName).\(associatedTypeName)"))
        }

        // Demangle the witness type in the image that declares the conformance
        // (its symbolic references are relative to that image).
        let witnessTypeName = try witness.record.substitutedTypeName(in: witness.image.machO)
        let witnessNode: Node
        do {
            witnessNode = try MetadataReader.demangleType(for: witnessTypeName, in: witness.image.machO)
        } catch {
            throw LayoutResolutionError.unknown(.demangleFailure)
        }

        // The witness may reference the conforming type's own generic parameters
        // (e.g. `Array`'s `Element` witness is parameter (0, 0)); substitute them
        // from the concrete base instantiation before resolving.
        let baseEnvironment = GenericArgumentEnvironment.make(forBoundGenericNode: baseTypeNode)
        let substitutedWitnessNode = baseEnvironment.substituting(in: witnessNode)
        return try layout(forTypeNode: substitutedWitnessNode, in: witness.image)
    }
}
