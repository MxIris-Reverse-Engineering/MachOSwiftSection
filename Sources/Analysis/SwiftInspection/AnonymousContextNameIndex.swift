import Foundation
import MachOKit
@_spi(Internals) import Demangling
import MachOFoundation
import MachOSwiftSection
@_spi(Internals) import MachOCaches

/// Per-image index of what the image's `_symbolic` symbols record about the
/// types that sit directly in an anonymous context: the private
/// discriminator of an outermost `private` / `fileprivate` type, and the full
/// name of a type declared in a function or closure body.
///
/// The compiler parents both on an anonymous context of their own — the
/// private type for its unstable identity, the local type for the function or
/// closure, which no descriptor can name — and the name the type needs is
/// recorded in two places `SymbolicDemangler` reads first: the anonymous
/// context's own mangled name, which the compiler writes only under
/// `-enable-anonymous-context-mangled-names` (added to `-g -Onone` builds
/// alone), and a symbol on the anonymous descriptor. An OS framework in the
/// dyld shared cache has neither, so its private types demangled as if they
/// were internal — `AppKit.FontPanelBIUSPopUpButton` where the Objective-C
/// runtime name says `_TtC6AppKitP33_05EA0EB8E781FFE22747790FC22932B124…` —
/// and its local types as members of the enclosing type
/// (`AppKit.NSWMDeferrableWMWindowTransaction.DeferralState`, declared in
/// `deferCompletionUntil()`; evolution proposal `local-type-context-names`).
///
/// What such an image does keep is the symbol the compiler gives every mangled
/// name it emits with symbolic references in it
/// (`IRGenMangler::mangleSymbolNameForSymbolicMangling`), which spells out the
/// full context mangling of each referent, discriminator and enclosing
/// function included — `SymbolicManglingIndex` pairs those referents with the
/// references they stand for. A type with a field descriptor always has one,
/// since the descriptor's own type name references the type. So for a direct
/// reference to a type descriptor whose parent is an anonymous context, the
/// referent is the name that anonymous context gives the type.
///
/// The symbol sits on the mangled name in `__swift5_typeref`, never on either
/// descriptor, which is why an offset lookup at the anonymous context cannot
/// find it and the index goes through the reference instead.
///
/// Built once per image, lazily — only a demangling that meets an anonymous
/// context with neither a mangled name nor a symbol asks for it — and evicted
/// with the demangle memo (`SymbolicDemangler.removeCache(for:)`). It keeps
/// nothing of `SymbolicManglingIndex`, whose storage goes with the symbol
/// store instead: a private type keeps its discriminator as text, a local
/// type its name as a type mangling, demangled again when asked for — an
/// image has few local types, and each is asked for once per demangling.
package final class AnonymousContextNameIndex: @unchecked Sendable {
    package static let shared = AnonymousContextNameIndex()

    private let cache = SharedCache<Storage>(evictionGroup: .demangleMemo)

    private init() {}

    package final class Storage: @unchecked Sendable {
        /// Anonymous context descriptor offset → the private discriminator of
        /// the type it wraps (`_05EA0EB8E781FFE22747790FC22932B1`).
        let privateDiscriminatorsByAnonymousContextOffset: [Int: String]

        /// Anonymous context descriptor offset → the full name of the local
        /// type it wraps, as a type mangling with no `$s` prefix
        /// (`6AppKit33NSWMDeferrableWMWindowTransactionC20deferCompletionUntilyycyF13DeferralStateL_V`).
        let localTypeManglingsByAnonymousContextOffset: [Int: String]

        init(privateDiscriminatorsByAnonymousContextOffset: [Int: String], localTypeManglingsByAnonymousContextOffset: [Int: String]) {
            self.privateDiscriminatorsByAnonymousContextOffset = privateDiscriminatorsByAnonymousContextOffset
            self.localTypeManglingsByAnonymousContextOffset = localTypeManglingsByAnonymousContextOffset
        }
    }

    /// The image's index, built on first use. The build re-types the reader
    /// once (`swiftSectionReader`): the cache is typed with the reader
    /// protocol every consumer holds, the build reads descriptors.
    package func storage(in machO: some MachORepresentableWithCache) -> Storage? {
        cache.storage(in: machO) { machO in
            machO.swiftSectionReader.map { Self.build(in: $0) }
        }
    }

    package func contains(in machO: some MachORepresentableWithCache) -> Bool {
        cache.contains(in: machO)
    }

    package func remove(for machO: some MachORepresentableWithCache) {
        cache.remove(for: machO)
    }

    // MARK: - Queries

    /// The private discriminator of the anonymous context at `offset`, or
    /// `nil` when no `_symbolic` symbol references a private type directly
    /// inside it.
    package func privateDiscriminator(forAnonymousContextAt offset: Int, in machO: some MachORepresentableWithCache) -> String? {
        storage(in: machO)?.privateDiscriminatorsByAnonymousContextOffset[offset]
    }

    /// The compiler's name of the local type the anonymous context at `offset`
    /// wraps — the nominal, `Structure(Function(…), LocalDeclName(…))` — or
    /// `nil` when no `_symbolic` symbol references a local type directly
    /// inside it.
    package func localTypeName(forAnonymousContextAt offset: Int, in machO: some MachORepresentableWithCache) -> Node? {
        guard let mangling = storage(in: machO)?.localTypeManglingsByAnonymousContextOffset[offset],
              let typeNode = try? demangleAsNodeTransient(mangling, isType: true)
        else { return nil }
        return Self.nominal(of: typeNode)
    }

    // MARK: - Build

    /// A referenced descriptor that sits directly in an anonymous context.
    private struct AnonymousContextMember {
        let anonymousContextOffset: Int
        let name: String
    }

    /// What a referent records for the anonymous context its type sits in.
    private enum RecordedName {
        case privateDiscriminator(String)
        case localTypeMangling(String)
    }

    /// Only direct references: the indirect form (`0x02`) goes through a
    /// pointer into another image, whose anonymous contexts are that image's to
    /// name.
    private static func build(in machO: some MachOSwiftSectionRepresentableWithCache) -> Storage {
        var privateDiscriminatorsByAnonymousContextOffset: [Int: String] = [:]
        var localTypeManglingsByAnonymousContextOffset: [Int: String] = [:]
        // Each referenced descriptor is read once. Its referent is not settled
        // with it: when one reference's referent fails to demangle, the next
        // reference to the same descriptor is still tried.
        var anonymousContextMemberByReferencedOffset: [Int: AnonymousContextMember?] = [:]
        for reference in SymbolicManglingIndex.shared.references(in: machO) where reference.kind == .directContextDescriptor {
            let anonymousContextMember: AnonymousContextMember?
            if let readMember = anonymousContextMemberByReferencedOffset[reference.referencedOffset] {
                anonymousContextMember = readMember
            } else {
                anonymousContextMember = Self.anonymousContextMember(at: reference.referencedOffset, in: machO)
                // `updateValue`, not the subscript: assigning `nil` through the
                // subscript would remove the key instead of recording "read,
                // not in an anonymous context".
                anonymousContextMemberByReferencedOffset.updateValue(anonymousContextMember, forKey: reference.referencedOffset)
            }
            guard let anonymousContextMember,
                  privateDiscriminatorsByAnonymousContextOffset[anonymousContextMember.anonymousContextOffset] == nil,
                  localTypeManglingsByAnonymousContextOffset[anonymousContextMember.anonymousContextOffset] == nil,
                  let referentNode = SymbolicManglingIndex.shared.referentNode(of: reference, in: machO),
                  let recordedName = recordedName(ofReferentNode: referentNode, named: anonymousContextMember.name)
            else { continue }
            switch recordedName {
            case .privateDiscriminator(let privateDiscriminator):
                privateDiscriminatorsByAnonymousContextOffset[anonymousContextMember.anonymousContextOffset] = privateDiscriminator
            case .localTypeMangling(let localTypeMangling):
                localTypeManglingsByAnonymousContextOffset[anonymousContextMember.anonymousContextOffset] = localTypeMangling
            }
        }
        return Storage(privateDiscriminatorsByAnonymousContextOffset: privateDiscriminatorsByAnonymousContextOffset, localTypeManglingsByAnonymousContextOffset: localTypeManglingsByAnonymousContextOffset)
    }

    private static func anonymousContextMember(at offset: Int, in machO: some MachOSwiftSectionRepresentableWithCache) -> AnonymousContextMember? {
        guard let referencedContext = try? ContextDescriptorWrapper.resolve(at: offset, in: machO.context),
              case .element(.anonymous(let anonymousContext))? = try? referencedContext.parent(in: machO.context),
              let name = try? referencedContext.namedContextDescriptor?.name(in: machO.context)
        else { return nil }
        return AnonymousContextMember(anonymousContextOffset: anonymousContext.offset, name: name)
    }

    /// The private discriminator or the local type name on the referent's own
    /// name, provided that name is the referenced descriptor's — a referent
    /// that demangles to anything else is not trusted with the anonymous
    /// context.
    private static func recordedName(ofReferentNode referentNode: Node, named expectedName: String) -> RecordedName? {
        let nominal = nominal(of: referentNode)
        guard nominal.children.count >= 2 else { return nil }
        let nameNode = nominal.children[1]
        guard nameNode.children.count >= 2, nameNode.children[1].text == expectedName else { return nil }
        switch nameNode.kind {
        case .privateDeclName:
            return nameNode.children[0].text.map { .privateDiscriminator($0) }
        case .localDeclName:
            let typeNode = Node.createTransient(kind: .type, children: [nominal])
            return (try? mangleAsString(typeNode)).map { .localTypeMangling($0) }
        default:
            return nil
        }
    }

    private static func nominal(of node: Node) -> Node {
        var nominal = node
        while nominal.kind == .global || nominal.kind == .type, let child = nominal.children.first {
            nominal = child
        }
        return nominal
    }
}
