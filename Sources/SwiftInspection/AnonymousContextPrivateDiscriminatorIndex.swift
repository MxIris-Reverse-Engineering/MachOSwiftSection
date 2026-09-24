import Foundation
import MachOKit
@_spi(Internals) import Demangling
import MachOFoundation
import MachOSwiftSection
@_spi(Internals) import MachOCaches

/// Per-image index of the private discriminators of anonymous contexts,
/// recovered from the image's `_symbolic` symbols.
///
/// The compiler parents every outermost `private` / `fileprivate` type on an
/// anonymous context, and the discriminator the type's name needs is recorded
/// in two places `SymbolicDemangler` reads first: the anonymous context's own
/// mangled name, which the compiler writes only under
/// `-enable-anonymous-context-mangled-names` (a debugger flag, off by
/// default), and a symbol on the anonymous descriptor. An OS framework in the
/// dyld shared cache has neither, so its private types demangled as if they
/// were internal — `AppKit.FontPanelBIUSPopUpButton` where the Objective-C
/// runtime name says `_TtC6AppKitP33_05EA0EB8E781FFE22747790FC22932B124…`.
///
/// What such an image does keep is the symbol the compiler gives every mangled
/// name it emits with symbolic references in it
/// (`IRGenMangler::mangleSymbolNameForSymbolicMangling`), which spells out the
/// full context mangling of each referent, discriminator included —
/// `SymbolicManglingIndex` pairs those referents with the references they
/// stand for. A type with a field descriptor always has one, since the
/// descriptor's own type name references the type. So for a direct reference
/// to a type descriptor whose parent is an anonymous context, the
/// discriminator of the referent is that anonymous context's.
///
/// The symbol sits on the mangled name in `__swift5_typeref`, never on either
/// descriptor, which is why an offset lookup at the anonymous context cannot
/// find it and the index goes through the reference instead.
///
/// Built once per image, lazily — only a demangling that meets an anonymous
/// context with neither a mangled name nor a symbol asks for it — and evicted
/// with the demangle memo (`SymbolicDemangler.removeCache(for:)`). It keeps
/// nothing of `SymbolicManglingIndex`, whose storage goes with the symbol
/// store instead.
package final class AnonymousContextPrivateDiscriminatorIndex: SharedCache<AnonymousContextPrivateDiscriminatorIndex.Storage>, @unchecked Sendable {
    package static let shared = AnonymousContextPrivateDiscriminatorIndex()

    private override init() {
        super.init()
    }

    package final class Storage: @unchecked Sendable {
        /// Anonymous context descriptor offset → the private discriminator of
        /// the type it wraps (`_05EA0EB8E781FFE22747790FC22932B1`).
        let privateDiscriminatorsByAnonymousContextOffset: [Int: String]

        init(privateDiscriminatorsByAnonymousContextOffset: [Int: String]) {
            self.privateDiscriminatorsByAnonymousContextOffset = privateDiscriminatorsByAnonymousContextOffset
        }
    }

    override package func buildStorage(for machO: some MachORepresentableWithCache) -> Storage? {
        if let machOFile = machO as? MachOFile {
            return Self.build(in: machOFile)
        } else if let machOImage = machO as? MachOImage {
            return Self.build(in: machOImage)
        }
        return nil
    }

    // MARK: - Queries

    /// The private discriminator of the anonymous context at `offset`, or
    /// `nil` when no `_symbolic` symbol references a type directly inside it.
    package func privateDiscriminator(forAnonymousContextAt offset: Int, in machO: some MachORepresentableWithCache) -> String? {
        storage(in: machO)?.privateDiscriminatorsByAnonymousContextOffset[offset]
    }

    // MARK: - Build

    /// A referenced descriptor that sits directly in an anonymous context.
    private struct AnonymousContextMember {
        let anonymousContextOffset: Int
        let name: String
    }

    /// Only direct references: the indirect form (`0x02`) goes through a
    /// pointer into another image, whose anonymous contexts are that image's to
    /// name.
    private static func build(in machO: some MachOSwiftSectionRepresentableWithCache) -> Storage {
        var privateDiscriminatorsByAnonymousContextOffset: [Int: String] = [:]
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
                  let referentNode = SymbolicManglingIndex.shared.referentNode(of: reference, in: machO),
                  let privateDiscriminator = privateDiscriminator(ofReferentNode: referentNode, named: anonymousContextMember.name)
            else { continue }
            privateDiscriminatorsByAnonymousContextOffset[anonymousContextMember.anonymousContextOffset] = privateDiscriminator
        }
        return Storage(privateDiscriminatorsByAnonymousContextOffset: privateDiscriminatorsByAnonymousContextOffset)
    }

    private static func anonymousContextMember(at offset: Int, in machO: some MachOSwiftSectionRepresentableWithCache) -> AnonymousContextMember? {
        guard let referencedContext = try? ContextDescriptorWrapper.resolve(from: offset, in: machO),
              case .element(.anonymous(let anonymousContext))? = try? referencedContext.parent(in: machO),
              let name = try? referencedContext.namedContextDescriptor?.name(in: machO)
        else { return nil }
        return AnonymousContextMember(anonymousContextOffset: anonymousContext.offset, name: name)
    }

    /// The discriminator on the referent's own name, provided that name is the
    /// referenced descriptor's — a referent that demangles to anything else is
    /// not trusted with the anonymous context.
    private static func privateDiscriminator(ofReferentNode referentNode: Node, named expectedName: String) -> String? {
        var nominal = referentNode
        while nominal.kind == .global || nominal.kind == .type, let child = nominal.children.first {
            nominal = child
        }
        guard nominal.children.count >= 2 else { return nil }
        let nameNode = nominal.children[1]
        guard nameNode.kind == .privateDeclName,
              nameNode.children.count >= 2,
              nameNode.children[1].text == expectedName
        else { return nil }
        return nameNode.children[0].text
    }
}
