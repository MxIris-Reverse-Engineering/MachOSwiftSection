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
/// (`IRGenMangler::mangleSymbolNameForSymbolicMangling`): `symbolic `, the
/// name with each five-byte reference spelled `_____`, then one space-separated
/// referent per reference — the full context mangling of what the reference
/// points at, discriminator included. A type with a field descriptor always
/// has one, since the descriptor's own type name references the type. So for a
/// reference to a type descriptor whose parent is an anonymous context, the
/// discriminator of the referent is that anonymous context's.
///
/// The symbol sits on the mangled name in `__swift5_typeref`, never on either
/// descriptor, which is why an offset lookup at the anonymous context cannot
/// find it and the index goes through the reference instead.
///
/// Built once per image, lazily — only a demangling that meets an anonymous
/// context with neither a mangled name nor a symbol asks for it — and evicted
/// with the demangle memo (`SymbolicDemangler.removeCache(for:)`).
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
            return Self.build(from: Self.symbolicSymbols(in: machOFile), in: machOFile)
        } else if let machOImage = machO as? MachOImage {
            return Self.build(from: Self.symbolicSymbols(in: machOImage), in: machOImage)
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

    private static let symbolicSymbolNamePrefix = "_symbolic "

    /// A direct symbolic reference to a context descriptor. The indirect form
    /// (`0x02`) goes through a pointer into another image, whose anonymous
    /// contexts are that image's to name.
    private static let directContextDescriptorReferenceKind: UInt8 = 0x01

    private struct SymbolicSymbol {
        let offset: Int
        let name: String
    }

    private static func symbolicSymbols(in machOImage: MachOImage) -> [SymbolicSymbol] {
        guard let symbols64 = machOImage.symbols64 else {
            return machOImage.symbols.compactMap { symbol in
                symbol.name.hasPrefix(symbolicSymbolNamePrefix) ? SymbolicSymbol(offset: symbol.offset, name: symbol.name) : nil
            }
        }
        // The prefix test runs on the mapped name bytes, so the hundreds of
        // thousands of other symbols never materialize a `String`.
        let prefixLength = symbolicSymbolNamePrefix.utf8.count
        var symbolicSymbols: [SymbolicSymbol] = []
        for symbol in symbols64 where strncmp(symbol.nameC, symbolicSymbolNamePrefix, prefixLength) == 0 {
            symbolicSymbols.append(SymbolicSymbol(offset: symbol.offset, name: String(cString: symbol.nameC)))
        }
        return symbolicSymbols
    }

    /// A cache image's symbol offsets are unslid addresses; the descriptor
    /// offsets this index is keyed by are measured from the shared region's
    /// start — the same adjustment `SymbolIndexStore` applies.
    private static func symbolicSymbols(in machOFile: MachOFile) -> [SymbolicSymbol] {
        var symbolicSymbols: [SymbolicSymbol] = []
        for symbol in machOFile.symbols where symbol.name.hasPrefix(symbolicSymbolNamePrefix) {
            var offset = symbol.offset
            if let cache = machOFile.cache, offset >= 0 {
                offset -= cache.mainCacheHeader.sharedRegionStart.cast()
            }
            symbolicSymbols.append(SymbolicSymbol(offset: offset, name: symbol.name))
        }
        return symbolicSymbols
    }

    private static func build(from symbolicSymbols: [SymbolicSymbol], in machO: some MachOSwiftSectionRepresentableWithCache) -> Storage {
        var privateDiscriminatorsByAnonymousContextOffset: [Int: String] = [:]
        for symbolicSymbol in symbolicSymbols {
            let referentManglings = referentManglings(ofSymbolNamed: symbolicSymbol.name)
            guard !referentManglings.isEmpty, let mangledName = try? MangledName.resolve(from: symbolicSymbol.offset, in: machO) else { continue }
            let lookups = mangledName.lookupElements
            // The referents follow the references in order; a count that
            // disagrees means the name is not the one the symbol spells.
            guard lookups.count == referentManglings.count else { continue }
            for (lookup, referentMangling) in zip(lookups, referentManglings) {
                guard case .relative(let relativeReference) = lookup.reference,
                      relativeReference.kind == directContextDescriptorReferenceKind,
                      let referencedContext = try? RelativeDirectPointer<ContextDescriptorWrapper?>(relativeOffset: relativeReference.relativeOffset).resolve(from: lookup.offset, in: machO),
                      case .element(.anonymous(let anonymousContext))? = try? referencedContext.parent(in: machO),
                      privateDiscriminatorsByAnonymousContextOffset[anonymousContext.offset] == nil,
                      let referencedName = try? referencedContext.namedContextDescriptor?.name(in: machO),
                      let privateDiscriminator = privateDiscriminator(ofReferentMangling: referentMangling, named: referencedName)
                else { continue }
                privateDiscriminatorsByAnonymousContextOffset[anonymousContext.offset] = privateDiscriminator
            }
        }
        return Storage(privateDiscriminatorsByAnonymousContextOffset: privateDiscriminatorsByAnonymousContextOffset)
    }

    /// `_symbolic <name> <referent> <referent>…` → the referents, in the order
    /// of the references they stand for. A mangling never contains a space, so
    /// splitting on it is exact.
    private static func referentManglings(ofSymbolNamed symbolName: String) -> [Substring] {
        let components = symbolName.dropFirst(symbolicSymbolNamePrefix.count).split(separator: " ", omittingEmptySubsequences: false)
        return Array(components.dropFirst())
    }

    /// The discriminator on the referent's own name, provided that name is the
    /// referenced descriptor's — a referent that demangles to anything else is
    /// not trusted with the anonymous context.
    private static func privateDiscriminator(ofReferentMangling referentMangling: Substring, named expectedName: String) -> String? {
        guard var nominal = try? demangleAsNodeTransient("$s" + referentMangling) else { return nil }
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
