import Demangling
import MachOSwiftSection
@_spi(Internals) import SwiftInspection

extension ImageUniverse {
    /// What a conformance's associated-type witness record says a member of a
    /// concrete type is (evolution proposal
    /// `opaque-reference-spelling-and-member-projection`).
    public struct ProjectedAssociatedTypeWitness {
        /// The witness type with the base's generic arguments substituted —
        /// `Array<Int>.Element` for `IndexingIterator<[Int]>.Element`, whose
        /// record says `Elements.Element`. Demangled in `image`, so any
        /// symbolic reference it still carries is that image's.
        public let witnessNode: Node
        /// The image whose `__swift5_assocty` record answered.
        public let image: MachO
        /// The conformance the record belongs to, as qualified names:
        /// `Swift.IndexingIterator` for `Swift.IteratorProtocol`.
        public let conformingQualifiedName: String
        public let protocolQualifiedName: String

        public init(witnessNode: Node, image: MachO, conformingQualifiedName: String, protocolQualifiedName: String) {
            self.witnessNode = witnessNode
            self.image = image
            self.conformingQualifiedName = conformingQualifiedName
            self.protocolQualifiedName = protocolQualifiedName
        }
    }

    /// Projects `base.Name` — a `dependentMemberType` whose base is a concrete
    /// nominal type — through the type-witness record of the base's
    /// conformance to the protocol the reference names, or answers `nil`
    /// when the projection cannot be made: the base is not a concrete
    /// nominal (a generic parameter, another member), the reference carries
    /// no protocol (IRGen qualifies every associated type it mangles, so an
    /// unqualified one is not worth a scan over every conformance), or no
    /// image in the closure declares that conformance's record.
    ///
    /// The same lookup `StaticTypeLayoutResolver.dependentMemberTypeLayout`
    /// makes, minus the layout: the rendering layer needs the type itself,
    /// to print a witness the way the generics book's "Map type parameter
    /// into opaque generic environment" reduces it.
    public func projectedAssociatedTypeWitness(base baseTypeNode: Node, associatedTypeReference: Node) -> ProjectedAssociatedTypeWitness? {
        guard associatedTypeReference.kind == .dependentAssociatedTypeRef,
              let associatedTypeName = associatedTypeReference.firstChild?.text,
              let protocolReferenceNode = associatedTypeReference.children.at(1),
              let protocolQualifiedName = NodeTypeNaming.protocolQualifiedName(of: protocolReferenceNode),
              let conformingQualifiedName = NodeTypeNaming.nominalQualifiedName(of: baseTypeNode)
        else { return nil }

        let key = ImageReference<MachO>.associatedTypeWitnessKey(
            conformingName: conformingQualifiedName,
            protocolName: protocolQualifiedName,
            associatedTypeName: associatedTypeName
        )
        guard let witness = resolveAssociatedTypeWitness(forKey: key) else { return nil }

        // Demangled in the image that declares the conformance: its symbolic
        // references are relative to that image.
        guard let witnessTypeName = try? witness.record.substitutedTypeName(in: witness.image.machO),
              let witnessNode = try? SymbolicDemangler.demangleType(for: witnessTypeName, in: witness.image.machO)
        else { return nil }

        // The record speaks in the conforming type's own generic parameters
        // (`Array`'s `Element` witness is parameter (0, 0)); the base
        // instantiation supplies them.
        let substitutedWitnessNode = GenericArgumentEnvironment.make(forInstantiatedTypeNode: baseTypeNode).substituting(in: witnessNode)
        return ProjectedAssociatedTypeWitness(
            witnessNode: substitutedWitnessNode,
            image: witness.image.machO,
            conformingQualifiedName: conformingQualifiedName,
            protocolQualifiedName: protocolQualifiedName
        )
    }
}
