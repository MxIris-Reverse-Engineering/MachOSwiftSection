import Foundation
import Dependencies
import MachOSwiftSection
@_spi(Internals) import Demangling
@_spi(Internals) import MachOSymbols

/// Whether a declaration's own descriptor symbol has an entry in the image's
/// export trie — the fact evolution proposal 0008 annotates with
/// (`// not exported`) and proposal 0016 filters on (`--exported-only`),
/// lifted onto the declaration model so a host can read it per declaration
/// without holding the Mach-O or reimplementing the verdict.
///
/// The non-verdict cases are deliberately distinct, because their scope is:
/// ``imageHasNoExportInformation`` is a fact about the IMAGE (no export
/// trie at all — nothing in it can be judged), while the others are facts
/// about one DECLARATION (the image's trie is fine; this declaration has no
/// symbol of its own to judge by). All of them mean "no verdict", and a
/// consumer must never read one as "not exported" — collapsing the first
/// would report every declaration of a `.o` file as unexported, and
/// collapsing ``declarationIsCImported`` would drop this image's public
/// extensions of the C types it uses.
///
/// The first two are rare on shipped binaries, and which images reach the
/// second depends on how they were stripped. An image that keeps its local
/// symbols carries one at every descriptor: over SwiftUICore (dyld shared
/// cache and iOS 18.5 simulator runtime), in-process libswiftCore and the
/// `SymbolTestsCore` fixture, all 8171 declarations resolved to ``exported``
/// or ``notExported``. One that does not — AppKit in the macOS 27.2 dyld
/// shared cache keeps only its exported, imported and `_symbolic` symbols —
/// has nothing at a non-exported descriptor, and every Swift type it
/// declares in an extension of an Objective-C class runs through an
/// extension context (`(extension in AppKit):__C.NSView`). Until the
/// remangling leg learned to spell an unconstrained extension context, about
/// 45 AppKit types got no verdict that way (evolution proposal
/// `export-verdict-without-local-symbols`).
public enum ExportStatus: Sendable, Hashable {
    /// The descriptor symbol is in the image's export trie.
    case exported

    /// The image has export information and this descriptor symbol is
    /// provably not in it — or the declaration has no symbol to judge by and
    /// is private, fileprivate or local, itself or a declaration it is nested
    /// in, which the compiler never exports (evolution proposal
    /// `export-verdict-without-local-symbols`).
    case notExported

    /// The image carries no export information whatsoever (an `.o` object
    /// file, a static-library product — anything without an export trie).
    /// Image-level: no declaration of this image can be judged.
    case imageHasNoExportInformation

    /// The image has export information, but no trustworthy symbol name
    /// could be produced for this declaration's descriptor, so it is not
    /// judged. Today's only source is a declaration that is neither private
    /// nor local, in an image that keeps no symbol at its descriptor, whose
    /// context chain runs through a constrained `extension` — see
    /// ``ExportStatus/descriptorSymbolName(for:descriptorKind:)``.
    case descriptorSymbolNameUnresolvable

    /// The declaration has no symbol of its own to judge by: an `@objc`
    /// protocol declared in Swift gets no protocol descriptor, and its
    /// Objective-C protocol record is never exported (evolution proposal
    /// `swift-declared-objc-protocols`). Not judged — unless the protocol is
    /// private, or nested in a private type: its private discriminator says
    /// that no other file, let alone another image, can name it, and it is
    /// ``notExported``.
    case declarationHasNoSymbol

    /// The declaration is imported from C or Objective-C (`__C.CGSize`, or
    /// a `__C_Synthesized` type the importer makes up), and the descriptor
    /// in this image is not the declaration's own: the compiler gives a
    /// Clang declaration non-unique linkage, so every module that uses the
    /// type emits a copy of its descriptor and none exports it. That says
    /// nothing about whether the type can be used from outside — this
    /// image's extensions of it can be public API
    /// (`extension CGSize: VectorArithmetic` in SwiftUI). Not judged
    /// (evolution proposal `exported-only-marking-mode`).
    case declarationIsCImported
}

extension ExportStatus {
    /// The tri-state projection, shaped exactly like
    /// `SymbolIndexStore.isExported(name:in:)`: `nil` for every non-verdict
    /// case. Use it where the caller only distinguishes "provably not
    /// exported" from everything else.
    public var isExported: Bool? {
        switch self {
        case .exported: true
        case .notExported: false
        case .imageHasNoExportInformation, .descriptorSymbolNameUnresolvable, .declarationHasNoSymbol, .declarationIsCImported: nil
        }
    }

    /// The one condition filtering and annotation may act on: a definitive
    /// negative verdict. Every other case keeps the declaration.
    public var isDefinitelyNotExported: Bool {
        self == .notExported
    }
}

// MARK: - Resolution

extension ExportStatus {
    /// A type's status, ruled by its nominal type descriptor symbol (`…Mn`).
    /// The descriptor is the one symbol every nominal type owns regardless of
    /// what else got exported — on the `SymbolTestsCore` fixture the exported
    /// `Mn` and `Ma` (metadata accessor) sets coincide exactly.
    package static func resolve(
        forNominalTypeDescriptor descriptor: some ContextDescriptorProtocol,
        typeNameNode: NodeReference,
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) -> ExportStatus {
        resolve(
            descriptor: descriptor,
            nameNode: typeNameNode,
            descriptorKind: .nominalTypeDescriptor,
            descriptorSymbolSuffix: "Mn",
            in: machO
        )
    }

    /// A protocol's status, ruled by its protocol descriptor symbol (`…Mp`).
    package static func resolve(
        forProtocolDescriptor descriptor: some ContextDescriptorProtocol,
        protocolNameNode: NodeReference,
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) -> ExportStatus {
        resolve(
            descriptor: descriptor,
            nameNode: protocolNameNode,
            descriptorKind: .protocolDescriptor,
            descriptorSymbolSuffix: "Mp",
            in: machO
        )
    }

    /// A Swift-declared `@objc` protocol's status. It has no protocol
    /// descriptor and its Objective-C protocol record is never exported, so
    /// its name is the only evidence there is: a private protocol, or one
    /// nested in a private type, is ``notExported`` (leg 3 below); any other
    /// is ``declarationHasNoSymbol``.
    package static func resolve(
        forSwiftDeclaredObjCProtocolNamed protocolNameNode: NodeReference,
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) -> ExportStatus {
        isPrivateOrLocal(protocolNameNode) ? statusOfPrivateOrLocalDeclaration(in: machO) : .declarationHasNoSymbol
    }

    /// A descriptor in the `__C` or `__C_Synthesized` module is the image's
    /// own copy of a C declaration's (``declarationIsCImported``) and is not
    /// judged; a descriptor whose module cannot be read is judged as usual.
    ///
    /// Leg 3 runs here, where both the name and the descriptor are at hand:
    /// when the first two legs leave the declaration unjudged, a private or
    /// local one is ``notExported``. It is recognized by its name
    /// (`isPrivateOrLocal(_:)`) or by the anonymous context enclosing its
    /// descriptor (`isEnclosedByAnonymousContext(_:in:)`) — the second still
    /// answers in an image that names no anonymous context, where a private
    /// type's name comes out without its discriminator. Leg 1 has already
    /// looked at the descriptor, where the trie would have put a row had the
    /// module exported it.
    private static func resolve(
        descriptor: some ContextDescriptorProtocol,
        nameNode: NodeReference,
        descriptorKind: Node.Kind,
        descriptorSymbolSuffix: String,
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) -> ExportStatus {
        if (try? descriptor.isCImportedContextDescriptor(in: machO.context)) == true {
            return .declarationIsCImported
        }
        let status = resolve(
            descriptorOffset: descriptor.offset,
            nameNode: nameNode,
            descriptorKind: descriptorKind,
            descriptorSymbolSuffix: descriptorSymbolSuffix,
            in: machO
        )
        guard status == .descriptorSymbolNameUnresolvable,
              isPrivateOrLocal(nameNode) || isEnclosedByAnonymousContext(descriptor, in: machO) else {
            return status
        }
        return statusOfPrivateOrLocalDeclaration(in: machO)
    }

    /// The first two legs, authoritative first; the third is in the
    /// descriptor-taking `resolve` above:
    ///
    /// 1. The symbol actually located AT the descriptor. Every exported
    ///    descriptor has a trie row at its offset, and an unstripped image
    ///    also carries a local symtab row for a non-exported one, so this leg
    ///    answers with the compiler's own spelling of the name — which is
    ///    what makes it authoritative: a type nested in a CONSTRAINED
    ///    extension (`extension Foo where A: P { public struct Nested {} }`)
    ///    mangles only the extension's own requirements into its context,
    ///    while the model's name node carries the full signature, so a
    ///    remangled name misses the trie and would drop an exported type.
    /// 2. Only when no symbol sits at the descriptor (a stripped image's
    ///    non-exported type): the remangled descriptor name against the trie,
    ///    which is complete even when the symtab is not. Refused for a name
    ///    involving a constrained extension — exactly the shape leg 1 exists
    ///    for. An unconstrained one (`extension NSView { struct Nested {} }`,
    ///    the shape of every Swift type nested in an Objective-C class)
    ///    spells as the compiler does, and is remangled.
    private static func resolve(
        descriptorOffset: Int,
        nameNode: NodeReference,
        descriptorKind: Node.Kind,
        descriptorSymbolSuffix: String,
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) -> ExportStatus {
        @Dependency(\.symbolIndexStore)
        var symbolIndexStore

        if let symbolsAtDescriptor = symbolIndexStore.symbols(for: descriptorOffset, in: machO),
           let descriptorSymbol = symbolsAtDescriptor.first(where: { $0.name.isSwiftSymbol && $0.name.hasSuffix(descriptorSymbolSuffix) }) {
            return ExportStatus(trieVerdict: symbolIndexStore.isExported(name: descriptorSymbol.name, in: machO))
        }
        guard let symbolName = descriptorSymbolName(for: nameNode, descriptorKind: descriptorKind) else {
            return .descriptorSymbolNameUnresolvable
        }
        return ExportStatus(trieVerdict: symbolIndexStore.isExported(name: symbolName, in: machO))
    }

    /// Leg 3's verdict on a private or local declaration with no symbol of
    /// its own to judge by: ``notExported`` in an image that has export
    /// information, ``imageHasNoExportInformation`` in one that has none.
    private static func statusOfPrivateOrLocalDeclaration(in machO: some MachOSwiftSectionRepresentableWithCache) -> ExportStatus {
        @Dependency(\.symbolIndexStore)
        var symbolIndexStore
        return symbolIndexStore.hasExportInformation(in: machO) ? .notExported : .imageHasNoExportInformation
    }

    /// Whether an anonymous context encloses the descriptor. The compiler
    /// puts one around a private or fileprivate declaration and around the
    /// function declaring a local one, so this reads leg 3's fact from the
    /// binary's own structure — and still reads it where no symbol names
    /// the anonymous context and the declaration's name comes out without
    /// its private discriminator.
    private static func isEnclosedByAnonymousContext(
        _ descriptor: some ContextDescriptorProtocol,
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) -> Bool {
        var parent = try? descriptor.parent(in: machO.context)
        while let parentDescriptor = parent?.resolved {
            if parentDescriptor.isAnonymous {
                return true
            }
            parent = try? parentDescriptor.parent(in: machO.context)
        }
        return false
    }

    /// `nil` — the store's "this image has no export information" answer — is
    /// the only way ``imageHasNoExportInformation`` is produced.
    private init(trieVerdict: Bool?) {
        switch trieVerdict {
        case true: self = .exported
        case false: self = .notExported
        case nil: self = .imageHasNoExportInformation
        }
    }

    /// Remangles a name node into the symbol name of its `descriptorKind`
    /// descriptor (`_$s<context>Mn` / `_$s<context>Mp`), or `nil` when the
    /// spelling cannot be trusted. The name node may arrive wrapped in a
    /// `.type` envelope, and a specialized definition's name is a
    /// bound-generic node (`Box<Int>`) — the descriptor belongs to the
    /// unbound nominal, so both wrappers are peeled first. A name involving
    /// a constrained `.extension` node — one carrying a generic signature —
    /// is refused (see leg 2 above). The remangling walks a transient tree
    /// materialized from the reference; nothing is interned or cached.
    package static func descriptorSymbolName(for node: NodeReference, descriptorKind: Node.Kind) -> String? {
        var contextNode = node.materialize()
        if contextNode.kind == .type, let wrappedNode = contextNode.children.first {
            contextNode = wrappedNode
        }
        switch contextNode.kind {
        case .boundGenericStructure, .boundGenericClass, .boundGenericEnum, .boundGenericProtocol, .boundGenericOtherNominalType, .boundGenericTypeAlias:
            guard var nominalNode = contextNode.children.first else { return nil }
            if nominalNode.kind == .type, let wrappedNode = nominalNode.children.first {
                nominalNode = wrappedNode
            }
            contextNode = nominalNode
        default:
            break
        }
        guard !containsConstrainedExtensionContext(contextNode) else { return nil }
        let descriptorNode = Node.createTransient(kind: descriptorKind, children: [contextNode])
        let globalNode = Node.createTransient(kind: .global, children: [descriptorNode])
        return try? mangleAsString(globalNode)
    }

    /// An extension node's children are the extending module, the extended
    /// type and — only when the extension is constrained — its generic
    /// signature.
    private static func containsConstrainedExtensionContext(_ node: Node) -> Bool {
        if node.kind == .extension, node.children.contains(where: { $0.kind == .dependentGenericSignature }) {
            return true
        }
        return node.children.contains { containsConstrainedExtensionContext($0) }
    }

    /// Whether the declaration a name node names is private, fileprivate or
    /// local — itself, or any declaration it is nested in. The compiler gives
    /// every one of them a non-public linkage, so none is in an export trie.
    /// The exception, a module built with `-enable-private-imports`, exports
    /// its private descriptors, and leg 1 finds those first.
    ///
    /// Only the declaration's context chain is read: its own name, the types
    /// it is nested in, an extension's extended type, and an anonymous
    /// context or a function, closure or accessor declaring a local type.
    /// Generic arguments, an extension's requirements and a function's
    /// signature are not — a specialized `Box<Private>` is exactly as
    /// exported as `Box`. A node of a shape not handled here reads as
    /// neither, which leaves the declaration unjudged.
    package static func isPrivateOrLocal(_ nameNode: NodeReference) -> Bool {
        var currentNode = nameNode
        while true {
            let children = currentNode.children
            switch currentNode.kind {
            case .type,
                 .boundGenericStructure, .boundGenericClass, .boundGenericEnum, .boundGenericProtocol, .boundGenericOtherNominalType, .boundGenericTypeAlias:
                guard let wrappedNode = children.first else { return false }
                currentNode = wrappedNode
            case .extension:
                // The module, then the extended type.
                guard children.count > 1 else { return false }
                currentNode = children[1]
            case .structure, .class, .enum, .protocol, .typeAlias, .otherNominalType:
                // The context, then the declared name.
                guard children.count > 1 else { return false }
                if children[1].kind == .privateDeclName || children[1].kind == .localDeclName {
                    return true
                }
                currentNode = children[0]
            case .anonymousContext, .function, .explicitClosure, .implicitClosure, .variable, .subscript, .getter, .setter, .constructor, .allocator:
                // Only a local type, or a private one whose context the
                // binary does not name, is declared in one of these.
                return true
            default:
                return false
            }
        }
    }
}
