@_spi(Internals) import Demangling
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
        guard let witnessTypeName = try? witness.record.substitutedTypeName(in: witness.image.machO.context),
              let witnessNode = try? SymbolicDemangler.demangleType(for: witnessTypeName, in: witness.image.machO.context)
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

// MARK: - Projecting every concrete member of a type

extension ImageUniverse {
    /// `node` with every dependent member whose base is concrete replaced by
    /// the type its conformance's witness record names — `[Swift.Int].Element`
    /// becomes `Swift.Int` (evolution proposal `offline-generic-specialization`).
    ///
    /// What a substitution leaves behind: a field typed `Elements.Element`
    /// reads `[Swift.Int].Element` once `Elements` is `[Swift.Int]`, a member
    /// of a concrete type the runtime would have resolved through the
    /// conformance. A member whose base still holds a generic parameter, or
    /// whose record no image in the universe carries, stays as it is. A
    /// witness may itself name a member of the base's arguments
    /// (`IndexingIterator`'s `Element` is `Elements.Element`), so a projection
    /// is projected again, a bounded number of hops deep.
    public func projectingConcreteMembers(in node: Node) -> Node {
        // Most nodes name no member at all; they come back as they are,
        // without a rebuilt copy of every node on the way.
        guard node.contains(.dependentMemberType) else { return node }
        var rewrittenNodes: [ObjectIdentifier: Node] = [:]
        return projectingConcreteMembers(in: node, remainingHops: Self.maximumProjectionHops, rewrittenNodes: &rewrittenNodes)
    }

    /// How many witness records one member may be projected through. A real
    /// chain is a handful deep; the bound only keeps a malformed record from
    /// looping.
    private static var maximumProjectionHops: Int { 8 }

    private func projectingConcreteMembers(in node: Node, remainingHops: Int, rewrittenNodes: inout [ObjectIdentifier: Node]) -> Node {
        if let rewrittenNode = rewrittenNodes[ObjectIdentifier(node)] {
            return rewrittenNode
        }
        var rewrittenChildren: [Node] = []
        rewrittenChildren.reserveCapacity(node.children.count)
        var hasRewrittenChild = false
        for child in node.children {
            let rewrittenChild = projectingConcreteMembers(in: child, remainingHops: remainingHops, rewrittenNodes: &rewrittenNodes)
            hasRewrittenChild = hasRewrittenChild || rewrittenChild !== child
            rewrittenChildren.append(rewrittenChild)
        }
        // A node's children and contents are mutually exclusive, so a node
        // rebuilt from its children alone loses nothing.
        var rewrittenNode = hasRewrittenChild ? Node.createTransient(kind: node.kind, children: rewrittenChildren) : node
        if rewrittenNode.kind == .dependentMemberType,
           remainingHops > 0,
           let baseTypeNode = rewrittenNode.children.first,
           let associatedTypeReference = rewrittenNode.children.at(1),
           !Self.containsGenericParameter(baseTypeNode),
           let projection = projectedAssociatedTypeWitness(base: baseTypeNode, associatedTypeReference: associatedTypeReference),
           !Self.containsUnspellableReference(projection.witnessNode) {
            var nestedRewrittenNodes: [ObjectIdentifier: Node] = [:]
            let projectedWitness = projectingConcreteMembers(in: projection.witnessNode, remainingHops: remainingHops - 1, rewrittenNodes: &nestedRewrittenNodes)
            // The member sits inside a `.type` wrapper already; the witness's
            // own wrapper is dropped to leave exactly one.
            rewrittenNode = projectedWitness.kind == .type ? (projectedWitness.firstChild ?? projectedWitness) : projectedWitness
        }
        rewrittenNodes[ObjectIdentifier(node)] = rewrittenNode
        return rewrittenNode
    }

    private static func containsGenericParameter(_ node: Node) -> Bool {
        node.kind == .dependentGenericParamType || node.children.contains(where: containsGenericParameter)
    }

    /// Whether `node` holds a reference that prints as a placeholder rather
    /// than a type: an opaque type — the record keeps one for the result of a
    /// `dynamic` declaration, an availability-conditional `some` (SE-0360) and
    /// a non-inlinable `some` of another resilient module, whose underlying
    /// type it cannot fix — or a kind-9 accessor function. Spliced into a
    /// field's type it read `opaque type symbolic reference 0x….0`; the member
    /// it would replace, `Concrete.Body`, names the type better.
    private static func containsUnspellableReference(_ node: Node) -> Bool {
        switch node.kind {
        case .opaqueType, .opaqueReturnType, .opaqueReturnTypeOf, .opaqueTypeDescriptorSymbolicReference, .accessorFunctionReference:
            return true
        default:
            return node.children.contains(where: containsUnspellableReference)
        }
    }
}
