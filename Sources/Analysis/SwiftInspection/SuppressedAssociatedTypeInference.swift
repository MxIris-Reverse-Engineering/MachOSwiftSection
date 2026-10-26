import MachOSwiftSection
@_spi(Internals) import Demangling
@_spi(Internals) import MachOSymbols

/// Which of a protocol's own associated types are declared `~Copyable` or
/// `~Escapable` (SE-0503), inferred from the image's extensions of the
/// protocol (evolution proposal `borrow-accessors-and-suppressed-associated-types`).
///
/// The binary does not record the declaration itself. IRGen encodes an
/// inverted-protocols requirement only for a generic parameter and drops the
/// one `associatedtype Element: ~Copyable` states (`addGenericRequirements`
/// skips a subject that does not reduce to a generic parameter), and the
/// protocol's requirement symbols do not mangle it either — the descriptor of
/// `protocol P { associatedtype Element: ~Copyable }` reads exactly like the
/// one without the suppression.
///
/// What survives is an extension that suppresses the default an extension of
/// the protocol would otherwise get: `extension P where Element: ~Copyable`
/// mangles `Self.Element: ~Swift.Copyable` into every member's context. SE-0503
/// rejects that inverse unless the protocol declares `Element` suppressible, so
/// one such signature proves the declaration. The inference therefore has
/// positive evidence only — an associated type no extension suppresses keeps
/// the default reading, which can be wrong, but nothing reads as `~Copyable`
/// that is not.
///
/// Only a PRIMARY associated type (`protocol P<Element>`) can leave that
/// evidence: SE-0503 gives an extension the default `Element: Copyable` for
/// primary associated types alone, so `where Strategy: ~Copyable` on an
/// ordinary one suppresses nothing and mangles to nothing.
package enum SuppressedAssociatedTypeInference {
    /// The member kinds an extension of a protocol can hold.
    private static let extensionMemberKinds: [SymbolIndexStore.MemberKind] = SymbolIndexStore.MemberKind.allCases.filter(\.isInExtension)

    /// The suppressed invertible protocols of `descriptor`'s own associated
    /// types, by associated type name; an associated type without evidence
    /// has no entry. Empty when the protocol declares no associated types or
    /// its context does not demangle.
    package static func suppressedInvertibleProtocolsByAssociatedTypeName(
        of descriptor: ProtocolDescriptor,
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) -> [String: InvertibleProtocolSet] {
        guard let associatedTypeNames = try? descriptor.associatedTypes(in: machO.context), !associatedTypeNames.isEmpty,
              let protocolNode = try? SymbolicDemangler.demangleContext(for: .protocol(descriptor), in: machO.context)
        else { return [:] }
        return suppressedInvertibleProtocolsByAssociatedTypeName(
            ofAssociatedTypesNamed: Set(associatedTypeNames),
            protocolNode: protocolNode,
            in: machO
        )
    }

    /// The same, for a caller already holding the protocol's context node
    /// (`type(protocol(…))`, as `SymbolicDemangler.demangleContext` returns
    /// it) and its associated type names.
    package static func suppressedInvertibleProtocolsByAssociatedTypeName(
        ofAssociatedTypesNamed associatedTypeNames: Set<String>,
        protocolNode: Node,
        in machO: some MachORepresentableWithCache
    ) -> [String: InvertibleProtocolSet] {
        guard !associatedTypeNames.isEmpty else { return [:] }
        let typeNode = protocolNode.kind == .type ? protocolNode : Node.createTransient(kind: .type, child: protocolNode)
        let protocolName = typeNode.print(using: .interfaceTypeBuilderOnly)
        var result: [String: InvertibleProtocolSet] = [:]
        for kind in extensionMemberKinds {
            for memberSymbol in SymbolIndexStore.shared.memberSymbols(of: kind, for: protocolName, node: typeNode, in: machO) {
                // The member's context is the first `extension` in preorder:
                // its own entity's first child, ahead of every type the
                // signature or the member's type mentions.
                guard let extensionNode = memberSymbol.demangledNode.first(of: .extension),
                      let genericSignature = extensionNode.children.at(2), genericSignature.kind == .dependentGenericSignature
                else { continue }
                for requirement in genericSignature.children where requirement.kind == .dependentGenericInverseConformanceRequirement {
                    guard let suppressed = suppressedProtocol(of: requirement),
                          let associatedTypeName = selfAssociatedTypeName(of: requirement, protocolName: protocolName),
                          associatedTypeNames.contains(associatedTypeName)
                    else { continue }
                    result[associatedTypeName, default: []].insert(suppressed)
                }
            }
        }
        return result
    }

    /// `Swift.Copyable` is inverse index 0, `Swift.Escapable` index 1 — the
    /// order the demangler prints them in.
    private static func suppressedProtocol(of requirement: some DemanglingNode) -> InvertibleProtocolSet? {
        switch requirement.children.at(1)?.index {
        case 0: .copyable
        case 1: .escapable
        default: nil
        }
    }

    /// `X` when the requirement's subject is `Self.X` — the protocol's own
    /// generic parameter, depth 0 index 0, one member deep — and the
    /// associated type reference, if it names a protocol at all, names this
    /// one. A deeper path (`Self.X.Y`) says nothing about the protocol's own
    /// declarations.
    private static func selfAssociatedTypeName(of requirement: some DemanglingNode, protocolName: String) -> String? {
        guard var subject = requirement.children.first else { return nil }
        if subject.kind == .type, let unwrapped = subject.children.first {
            subject = unwrapped
        }
        guard subject.kind == .dependentMemberType,
              var base = subject.children.first,
              let associatedTypeReference = subject.children.at(1), associatedTypeReference.kind == .dependentAssociatedTypeRef
        else { return nil }
        if base.kind == .type, let unwrapped = base.children.first {
            base = unwrapped
        }
        guard base.kind == .dependentGenericParamType,
              base.children.at(0)?.index == 0,
              base.children.at(1)?.index == 0
        else { return nil }
        // `type(protocol(…))` prints the same name with or without its
        // `type` wrapper, so the comparison needs no normalizing.
        if let referencedProtocol = associatedTypeReference.children.at(1),
           referencedProtocol.print(using: .interfaceTypeBuilderOnly) != protocolName {
            return nil
        }
        return associatedTypeReference.children.first?.text
    }
}

extension SymbolIndexStore.MemberKind {
    fileprivate var isInExtension: Bool {
        switch self {
        case .allocator(let inExtension),
             .constructor(let inExtension),
             .subscript(let inExtension, _),
             .variable(let inExtension, _, _),
             .function(let inExtension, _):
            inExtension
        case .deallocator,
             .destructor:
            false
        }
    }
}
