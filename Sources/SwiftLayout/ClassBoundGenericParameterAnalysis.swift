import MachOSwiftSection
@_spi(Internals) import SwiftInspection
import Demangling

/// The layout facts a generic type descriptor's requirement signature yields
/// **without any instantiation argument** — what the signature alone pins about
/// each parameter's storage.
struct RequirementSignatureLayoutFacts {
    /// Parameters constrained to a single object reference (`T: AnyObject` /
    /// `: SomeClass` / a class-bound protocol) — laid out as one pointer.
    let classBoundParameterKeys: Set<GenericParameterKey>

    /// Parameters pinned to a **concrete** type by a same-type requirement
    /// (`T == Foundation.Date`, from a constrained extension), mapped to the
    /// pinned type's unwrapped `Node`. A real substitution — the parameter is
    /// that concrete type in every valid use.
    let concreteSameTypeSubstitutions: [GenericParameterKey: Node]

    static let empty = RequirementSignatureLayoutFacts(classBoundParameterKeys: [], concreteSameTypeSubstitutions: [:])

    var isEmpty: Bool { classBoundParameterKeys.isEmpty && concreteSameTypeSubstitutions.isEmpty }
}

/// Derives, from a generic type descriptor's requirement signature, the layout
/// facts about its parameters that hold **without any substitution**:
///
/// - A parameter constrained to a class layout (`T: AnyObject`), a superclass
///   (`T: SomeClass`), or a class-bound protocol (`T: SomeClassBoundProtocol`,
///   `T: NSCopying`) has the identical single-object-reference layout in every
///   class instantiation, so a field typed by it lays out exactly. The
///   environment rewrites such an unsubstituted parameter to a placeholder
///   class node (see `GenericArgumentEnvironment`).
/// - A parameter pinned to a **concrete** type by a same-type requirement
///   (`T == Date`, contributed by a constrained extension — e.g. a type nested
///   in `extension Foo where Value == Date`) is that type in every valid use,
///   so it is a genuine substitution.
///
/// The requirement list read here is the descriptor's cumulative canonical
/// signature (inherited parent-context requirements included), and requirement
/// parameter references carry absolute `(depth, index)` coordinates — the same
/// coordinates field records use — so nested generic contexts need no extra
/// bookkeeping.
enum ClassBoundGenericParameterAnalysis {
    /// The requirement-signature layout facts of `descriptor` (class-bound
    /// parameters + concrete same-type pins) in a single pass over its
    /// requirements. `.empty` for a non-generic descriptor (a fast flag check)
    /// or one whose generic context cannot be read.
    static func layoutFacts<MachO: MachOSwiftSectionRepresentableWithCache>(
        of descriptor: some TypeContextDescriptorProtocol,
        in image: ImageReference<MachO>,
        imageUniverse: ImageUniverse<MachO>
    ) -> RequirementSignatureLayoutFacts {
        guard let genericContext = try? descriptor.genericContext(in: image.machO) else { return .empty }
        var classBoundParameterKeys: Set<GenericParameterKey> = []
        var concreteSameTypeSubstitutions: [GenericParameterKey: Node] = [:]
        for requirement in genericContext.requirements {
            // A pack requirement (`repeat each T: AnyObject`) constrains each
            // element to a pointer, but the pack's arity stays unknown — the
            // dependent fields cannot be laid out, so the parameter is not
            // marked. (Marking it would still be layout-safe — the expansion
            // machinery degrades on a non-pack count — but is never useful.)
            guard !requirement.layout.flags.contains(.isPackRequirement) else { continue }
            // Only a constraint on the parameter *itself* pins its storage: a
            // constraint on a dependent member (`T.Element: AnyObject`,
            // `T.Element == Int`) says nothing about `T`'s own layout.
            guard let parameterKey = bareParameterKey(of: requirement, in: image.machO) else { continue }
            switch requirement.layout.flags.kind {
            case .sameType:
                // `T == <concrete>`: a real substitution, but only when the RHS
                // is fully concrete (does not reference another parameter or a
                // dependent member — those cannot stand alone).
                if let concreteType = concreteSameType(of: requirement, in: image.machO) {
                    concreteSameTypeSubstitutions[parameterKey] = concreteType
                }
            default:
                if isClassBound(requirement, in: image, imageUniverse: imageUniverse) {
                    classBoundParameterKeys.insert(parameterKey)
                }
            }
        }
        return RequirementSignatureLayoutFacts(
            classBoundParameterKeys: classBoundParameterKeys,
            concreteSameTypeSubstitutions: concreteSameTypeSubstitutions
        )
    }

    /// The unwrapped concrete type a same-type requirement pins its subject to,
    /// or `nil` when the RHS is not `.type`, does not demangle, or is not fully
    /// concrete (it references a generic parameter / dependent member, so it
    /// cannot be substituted standalone).
    private static func concreteSameType<MachO: MachOSwiftSectionRepresentableWithCache>(
        of requirement: GenericRequirementDescriptor,
        in machO: MachO
    ) -> Node? {
        guard
            case .type(let rightHandSideName)? = try? requirement.resolvedContent(in: machO),
            let rightHandSideNode = try? MetadataReader.demangleType(for: rightHandSideName, in: machO)
        else { return nil }
        let unwrapped = rightHandSideNode.kind == .type ? (rightHandSideNode.firstChild ?? rightHandSideNode) : rightHandSideNode
        guard !nodeReferencesParameterOrMember(unwrapped) else { return nil }
        return unwrapped
    }

    /// Whether a demangled type node (transitively) references a generic
    /// parameter or a dependent member — i.e. is not a standalone concrete type.
    private static func nodeReferencesParameterOrMember(_ node: Node) -> Bool {
        if node.kind == .dependentGenericParamType || node.kind == .dependentMemberType { return true }
        for child in node.children where nodeReferencesParameterOrMember(child) { return true }
        return false
    }

    /// The `(depth, index)` of a requirement whose subject is a bare generic
    /// parameter, or `nil` when the subject is a dependent member type (or
    /// cannot be demangled).
    private static func bareParameterKey<MachO: MachOSwiftSectionRepresentableWithCache>(
        of requirement: GenericRequirementDescriptor,
        in machO: MachO
    ) -> GenericParameterKey? {
        guard
            let parameterMangledName = try? requirement.paramMangledName(in: machO),
            let parameterNode = try? MetadataReader.demangleType(for: parameterMangledName, in: machO)
        else { return nil }
        let unwrapped = parameterNode.kind == .type ? (parameterNode.firstChild ?? parameterNode) : parameterNode
        guard
            unwrapped.kind == .dependentGenericParamType,
            let depth = unwrapped.firstChild?.index,
            let index = unwrapped.children.at(1)?.index
        else { return nil }
        return GenericParameterKey(depth: depth, index: index)
    }

    /// Whether a requirement forces its subject to be a class reference:
    /// a `.layout(.class)` constraint, a superclass bound, or conformance to a
    /// class-bound protocol.
    private static func isClassBound<MachO: MachOSwiftSectionRepresentableWithCache>(
        _ requirement: GenericRequirementDescriptor,
        in image: ImageReference<MachO>,
        imageUniverse: ImageUniverse<MachO>
    ) -> Bool {
        switch requirement.layout.flags.kind {
        case .layout:
            guard case .layout(.class)? = try? requirement.resolvedContent(in: image.machO) else { return false }
            return true
        case .baseClass:
            return true
        case .protocol:
            guard case .protocol(let protocolReference)? = try? requirement.resolvedContent(in: image.machO) else { return false }
            return isClassBoundProtocolReference(protocolReference, in: image, imageUniverse: imageUniverse)
        default:
            // `sameType` to a concrete class is a genuine specialization, not a
            // representation constraint — out of scope here.
            return false
        }
    }

    /// Whether a requirement's protocol reference is class-bound. An imported
    /// Objective-C protocol always is; a Swift protocol descriptor carries the
    /// constraint in its flags; a cross-image reference (a bind symbol in a
    /// file-backed image) is recovered by name through the universe, falling
    /// back to "not class-bound" (the dependent fields then degrade, matching
    /// the engine's conservative direction).
    private static func isClassBoundProtocolReference<MachO: MachOSwiftSectionRepresentableWithCache>(
        _ protocolReference: SymbolOrElement<ProtocolDescriptorWithObjCInterop>,
        in image: ImageReference<MachO>,
        imageUniverse: ImageUniverse<MachO>
    ) -> Bool {
        switch protocolReference {
        case .element(let interopProtocol):
            switch interopProtocol {
            case .objc:
                return true
            case .swift(let protocolDescriptor):
                return protocolDescriptor.flags.kindSpecificFlags?.protocolFlags?.classConstraint == .class
            }
        case .symbol(let symbol):
            guard
                let symbolNode = try? MetadataReader.demangleType(for: symbol, in: image.machO),
                let protocolNode = symbolNode.kind == .protocol ? symbolNode : symbolNode.first(of: .protocol),
                let qualifiedProtocolName = NodeTypeNaming.protocolQualifiedName(of: protocolNode)
            else { return false }
            if imageUniverse.resolveProtocolClassConstraint(byQualifiedTypeName: qualifiedProtocolName) == .class {
                return true
            }
            // A Swift-declared `@objc` protocol emits no Swift protocol
            // descriptor; its `__objc_protolist` record is the recognition
            // signal, and such a protocol is always class-bound.
            return imageUniverse.isObjCProtocolDeclared(byQualifiedTypeName: qualifiedProtocolName)
        }
    }
}
