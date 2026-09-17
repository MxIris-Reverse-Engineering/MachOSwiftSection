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
/// The two non-verdict cases are deliberately distinct, because their scope
/// is: ``imageHasNoExportInformation`` is a fact about the IMAGE (no export
/// trie at all — nothing in it can be judged), while
/// ``descriptorSymbolNameUnresolvable`` is a fact about this one
/// DECLARATION (the image's trie is fine; this name cannot be spelled). Both
/// mean "no verdict", and a consumer must never read either as "not
/// exported" — collapsing the first would report every declaration of a
/// `.o` file as unexported.
///
/// Empirically neither occurs on shipped binaries: over SwiftUICore (dyld
/// shared cache and iOS 18.5 simulator runtime), in-process libswiftCore and
/// the `SymbolTestsCore` fixture, every type and protocol carried a symbol at
/// its own descriptor, so all 8171 declarations resolved to ``exported`` or
/// ``notExported``. They are correctness branches, not the common path.
public enum ExportStatus: Sendable, Hashable {
    /// The descriptor symbol is in the image's export trie.
    case exported

    /// The image has export information and this descriptor symbol is
    /// provably not in it.
    case notExported

    /// The image carries no export information whatsoever (an `.o` object
    /// file, a static-library product — anything without an export trie).
    /// Image-level: no declaration of this image can be judged.
    case imageHasNoExportInformation

    /// The image has export information, but no trustworthy symbol name
    /// could be produced for this declaration's descriptor, so it is not
    /// judged. Today's only source is a name whose context chain runs
    /// through a constrained `extension` — see
    /// ``ExportStatus/descriptorSymbolName(for:descriptorKind:)``.
    case descriptorSymbolNameUnresolvable
}

extension ExportStatus {
    /// The tri-state projection, shaped exactly like
    /// `SymbolIndexStore.isExported(name:in:)`: `nil` for both non-verdict
    /// cases. Use it where the caller only distinguishes "provably not
    /// exported" from everything else.
    public var isExported: Bool? {
        switch self {
        case .exported: true
        case .notExported: false
        case .imageHasNoExportInformation, .descriptorSymbolNameUnresolvable: nil
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
    package static func resolve<MachO: MachOSwiftSectionRepresentableWithCache>(
        forNominalTypeDescriptorAt descriptorOffset: Int,
        typeNameNode: NodeReference,
        in machO: MachO
    ) -> ExportStatus {
        resolve(
            descriptorOffset: descriptorOffset,
            nameNode: typeNameNode,
            descriptorKind: .nominalTypeDescriptor,
            descriptorSymbolSuffix: "Mn",
            in: machO
        )
    }

    /// A protocol's status, ruled by its protocol descriptor symbol (`…Mp`).
    package static func resolve<MachO: MachOSwiftSectionRepresentableWithCache>(
        forProtocolDescriptorAt descriptorOffset: Int,
        protocolNameNode: NodeReference,
        in machO: MachO
    ) -> ExportStatus {
        resolve(
            descriptorOffset: descriptorOffset,
            nameNode: protocolNameNode,
            descriptorKind: .protocolDescriptor,
            descriptorSymbolSuffix: "Mp",
            in: machO
        )
    }

    /// Two legs, authoritative first:
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
    ///    which is complete even when the symtab is not. Restricted to
    ///    canonical contexts — a name involving an `.extension` context is
    ///    exactly the shape leg 1 exists for, and yields no verdict here.
    private static func resolve<MachO: MachOSwiftSectionRepresentableWithCache>(
        descriptorOffset: Int,
        nameNode: NodeReference,
        descriptorKind: Node.Kind,
        descriptorSymbolSuffix: String,
        in machO: MachO
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
    /// unbound nominal, so both wrappers are peeled first. A context chain
    /// through an `.extension` node is refused (see leg 2 above). The
    /// remangling walks a transient tree materialized from the reference;
    /// nothing is interned or cached.
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
        guard !containsExtensionContext(contextNode) else { return nil }
        let descriptorNode = Node.createTransient(kind: descriptorKind, children: [contextNode])
        let globalNode = Node.createTransient(kind: .global, children: [descriptorNode])
        return try? mangleAsString(globalNode)
    }

    private static func containsExtensionContext(_ node: Node) -> Bool {
        if node.kind == .extension { return true }
        return node.children.contains { containsExtensionContext($0) }
    }
}
