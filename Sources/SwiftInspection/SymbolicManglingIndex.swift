import Foundation
import MachOKit
import FoundationToolbox
@_spi(Internals) import Demangling
import MachOFoundation
import MachOSwiftSection
@_spi(Internals) import MachOCaches
@_spi(Internals) import MachOSymbols

/// One symbolic reference in a mangled name that a symbolic-mangling symbol
/// names, paired with the referent that symbol spells for it.
package struct SymbolicManglingReference: Hashable, Sendable {
    /// The reference's control byte. `IRGenModule::getAddrOfStringForTypeRef`
    /// emits only the five named here into these names; the byte is kept as
    /// read, so any other shows up rather than being dropped.
    package struct Kind: RawRepresentable, Hashable, Sendable {
        package let rawValue: UInt8

        package init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        /// `0x01`: a type, protocol or opaque type descriptor in this image.
        package static let directContextDescriptor = Kind(rawValue: 0x01)

        /// `0x02`: a pointer slot holding a context descriptor's address.
        package static let indirectContextDescriptor = Kind(rawValue: 0x02)

        /// `0x0A`: a unique extended existential type shape.
        package static let uniqueExtendedExistentialTypeShape = Kind(rawValue: 0x0A)

        /// `0x0B`: a non-unique extended existential type shape.
        package static let nonUniqueExtendedExistentialTypeShape = Kind(rawValue: 0x0B)

        /// `0x0C`: an Objective-C protocol reference — how every `@objc`
        /// protocol is referenced, a Swift-declared one included.
        package static let objectiveCProtocol = Kind(rawValue: 0x0C)
    }

    // Declared widest first, so a reference packs into 24 bytes.

    /// Where the reference's control byte sits, inside the mangled name.
    package let referenceOffset: Int

    /// Where the reference points — the descriptor for `0x01`, the pointer
    /// slot for `0x02`, the shape for `0x0A` / `0x0B`, the Objective-C protocol
    /// reference for `0x0C` — in the offset accounting every descriptor uses.
    /// The four-byte field after the control byte plus the relative offset in
    /// it, as `SymbolicDemangler` resolves it.
    package let referencedOffset: Int

    private let storedSymbolPosition: UInt32

    private let storedReferentIndex: UInt16

    package let kind: Kind

    init(kind: Kind, referenceOffset: Int, referencedOffset: Int, symbolPosition: UInt32, referentIndex: UInt16) {
        self.referenceOffset = referenceOffset
        self.referencedOffset = referencedOffset
        self.storedSymbolPosition = symbolPosition
        self.storedReferentIndex = referentIndex
        self.kind = kind
    }

    /// The position, in the image's `SymbolicManglingSymbols`, of the symbol
    /// naming the mangled name.
    package var symbolPosition: Int {
        Int(storedSymbolPosition)
    }

    /// Which of that symbol's referents is this reference's.
    package var referentIndex: Int {
        Int(storedReferentIndex)
    }
}

/// Per-image index of the symbolic references in the mangled names an image's
/// symbolic-mangling symbols name, each paired with the referent the symbol
/// spells for it (evolution proposal `symbolic-mangling-symbol-index`).
///
/// A symbolic reference is five bytes — a control byte and a relative offset —
/// so a mangled name says where its referents are but not what they are
/// called. The symbol the compiler names each such mangled name by spells every
/// referent out in full: module, enclosing types, private discriminator. This
/// index joins the two: it reads the mangled name each symbol sits on, pairs
/// its references with the symbol's referents in order, and keys them by where
/// they point.
///
/// A referent is not a mangling of its own. The compiler appends a symbol's
/// referents with one mangler, so a later referent may use a substitution
/// standing for part of an earlier one — AppKit has `AA08ModifiedD0V` after
/// `7SwiftUI19_ConditionalContentV`, the `AA` being `SwiftUI` and the `0`/`D`
/// word references reaching into the earlier name. Demangled alone it fails, or
/// means something else. The referents are therefore demangled together, one
/// `$s` in front of all of them: the demangler rebuilds the substitution and
/// word tables in the order the mangler filled them and hands back one
/// top-level node per referent. For the same reason there is no textual
/// "expanded" mangled name — splicing the referents into the mangled name
/// would renumber both sides' substitutions.
///
/// Nothing is stored as a `String` or a `Node`: a reference records the
/// position of its symbol and the index of its referent, and the referent is
/// demangled, transiently, when asked for.
///
/// Built once per image, lazily, from what `SymbolIndexStore` collected, and
/// evicted with that store (`SwiftDeclarationIndexer`'s symbol-store claim):
/// the storage holds the store's symbolic-mangling table. This module sits
/// below the event layer, so symbols that do not pair are reported through
/// `#log` and counted by ``unpairedSymbolCount(in:)``.
@Loggable(.private, subsystem: "com.machoswiftsection.swift-inspection", category: "SymbolicManglingIndex")
package final class SymbolicManglingIndex: SharedCache<SymbolicManglingIndex.Storage>, @unchecked Sendable {
    package static let shared = SymbolicManglingIndex()

    private override init() {
        super.init()
    }

    package final class Storage: @unchecked Sendable {
        let symbols: SymbolicManglingSymbols

        /// Every reference of every paired symbol: in symbol order, and within
        /// a symbol in the order its mangled name has them.
        let references: [SymbolicManglingReference]

        /// Indexes into `references`, ordered by `referencedOffset` (ties in
        /// `references` order), for binary search.
        let referenceIndexesOrderedByReferencedOffset: [UInt32]

        /// Symbols whose mangled name and referents did not pair up, and so
        /// contributed no references.
        let unpairedSymbolCount: Int

        init(symbols: SymbolicManglingSymbols, references: [SymbolicManglingReference], unpairedSymbolCount: Int) {
            self.symbols = symbols
            self.references = references
            self.referenceIndexesOrderedByReferencedOffset = (0 ..< UInt32(references.count)).sorted { leftIndex, rightIndex in
                (references[Int(leftIndex)].referencedOffset, leftIndex) < (references[Int(rightIndex)].referencedOffset, rightIndex)
            }
            self.unpairedSymbolCount = unpairedSymbolCount
        }

        /// The references pointing at `referencedOffset`, in `references` order.
        func references(to referencedOffset: Int) -> [SymbolicManglingReference] {
            var lowerBound = 0
            var upperBound = referenceIndexesOrderedByReferencedOffset.count
            while lowerBound < upperBound {
                let middle = (lowerBound + upperBound) / 2
                if references[Int(referenceIndexesOrderedByReferencedOffset[middle])].referencedOffset < referencedOffset {
                    lowerBound = middle + 1
                } else {
                    upperBound = middle
                }
            }
            var matchingReferences: [SymbolicManglingReference] = []
            for referenceIndex in referenceIndexesOrderedByReferencedOffset[lowerBound...] {
                let reference = references[Int(referenceIndex)]
                guard reference.referencedOffset == referencedOffset else { break }
                matchingReferences.append(reference)
            }
            return matchingReferences
        }

        /// The first `count` referents of the symbol at `symbolPosition` —
        /// all of them when `count` is `nil` — demangled together.
        func referentNodes(ofSymbolAt symbolPosition: Int, count: Int? = nil) -> [Node]? {
            guard symbols.indices.contains(symbolPosition),
                  let symbolName = SymbolicManglingSymbolName(symbols[symbolPosition].name)
            else { return nil }
            let referentCount = count ?? symbolName.referentManglings.count
            guard referentCount > 0, referentCount <= symbolName.referentManglings.count else { return nil }
            return SymbolicManglingIndex.demangleTogether(symbolName.referentManglings.prefix(referentCount))
        }

        func referentNode(of reference: SymbolicManglingReference) -> Node? {
            referentNodes(ofSymbolAt: reference.symbolPosition, count: reference.referentIndex + 1)?.last
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

    /// The symbols the index was built from.
    package func symbols(in machO: some MachORepresentableWithCache) -> SymbolicManglingSymbols? {
        storage(in: machO)?.symbols
    }

    /// Every paired reference of the image: in symbol order, and within a
    /// symbol in the order its mangled name has them.
    package func references(in machO: some MachORepresentableWithCache) -> [SymbolicManglingReference] {
        storage(in: machO)?.references ?? []
    }

    /// The references pointing at `referencedOffset`.
    package func references(to referencedOffset: Int, in machO: some MachORepresentableWithCache) -> [SymbolicManglingReference] {
        storage(in: machO)?.references(to: referencedOffset) ?? []
    }

    /// What `reference` points at, as the compiler spelled it: its referent,
    /// demangled together with the referents before it (transient). For a
    /// direct context reference this is the descriptor's full name — the
    /// nominal or protocol node itself, no `.type` wrapper. `reference` must
    /// come from this image's index.
    package func referentNode(of reference: SymbolicManglingReference, in machO: some MachORepresentableWithCache) -> Node? {
        storage(in: machO)?.referentNode(of: reference)
    }

    /// The compiler's spelling of the context descriptor at `offset`, from the
    /// first direct context reference to it that demangles — or `nil` when no
    /// symbolic-mangling symbol references it directly.
    package func referentNode(forContextDescriptorAt offset: Int, in machO: some MachORepresentableWithCache) -> Node? {
        guard let storage = storage(in: machO) else { return nil }
        for reference in storage.references(to: offset) where reference.kind == .directContextDescriptor {
            if let referentNode = storage.referentNode(of: reference) {
                return referentNode
            }
        }
        return nil
    }

    /// Every referent of the symbol at `symbolPosition`, in reference order,
    /// demangled together (transient); `nil` when they do not demangle as one
    /// sequence.
    package func referentNodes(ofSymbolAt symbolPosition: Int, in machO: some MachORepresentableWithCache) -> [Node]? {
        storage(in: machO)?.referentNodes(ofSymbolAt: symbolPosition)
    }

    /// How many of the image's symbols did not pair with the mangled names
    /// they name — expected zero.
    package func unpairedSymbolCount(in machO: some MachORepresentableWithCache) -> Int {
        storage(in: machO)?.unpairedSymbolCount ?? 0
    }

    // MARK: - Referent decoding

    /// Demangles `referentManglings` as the one sequence the compiler mangled
    /// them as — behind a single `$s`, so each substitution and word reference
    /// resolves against the referents before it. `nil` unless the demangler
    /// hands back exactly one top-level node per referent.
    static func demangleTogether(_ referentManglings: some Collection<Substring>) -> [Node]? {
        guard let global = try? demangleAsNodeTransient("$s" + referentManglings.joined()),
              global.kind == .global,
              global.children.count == referentManglings.count
        else { return nil }
        return Array(global.children)
    }

    // MARK: - Build

    private static func build(in machO: some MachOSwiftSectionRepresentableWithCache) -> Storage? {
        guard let symbols = SymbolIndexStore.shared.symbolicManglingSymbols(in: machO) else { return nil }
        var references: [SymbolicManglingReference] = []
        var unpairedSymbolCount = 0
        for symbolPosition in symbols.indices {
            let symbol = symbols[symbolPosition]
            guard let symbolName = SymbolicManglingSymbolName(symbol.name) else {
                unpairedSymbolCount += 1
                continue
            }
            // A name with no referents has no references to pair, and reading
            // its bytes could only confirm that.
            guard !symbolName.referentManglings.isEmpty else { continue }
            guard let symbolReferences = pairedReferences(ofSymbolAt: symbolPosition, offset: symbol.offset, referentCount: symbolName.referentManglings.count, in: machO) else {
                unpairedSymbolCount += 1
                continue
            }
            references.append(contentsOf: symbolReferences)
        }
        if unpairedSymbolCount > 0 {
            #log(.error, "\(unpairedSymbolCount, privacy: .public) of \(symbols.count, privacy: .public) symbolic-mangling symbols did not pair with the mangled names they name")
        }
        return Storage(symbols: symbols, references: references, unpairedSymbolCount: unpairedSymbolCount)
    }

    /// The references of the mangled name at `offset`, paired in order with
    /// the symbol's referents; `nil` when the two do not pair up — a different
    /// count, or an absolute reference, which the compiler never writes into
    /// these names.
    ///
    /// `offset` is the symbol's value, which the binary supplies. A negative
    /// one — an `n_value` of 2^63 or more in a standalone file, or below the
    /// shared region in a cache image — is refused before any read: the file
    /// reader converts every offset to `UInt64` first, and that conversion
    /// traps where no `try?` can catch it. The binary under analysis must not
    /// decide whether the host process lives.
    private static func pairedReferences(
        ofSymbolAt symbolPosition: Int,
        offset: Int,
        referentCount: Int,
        in machO: some MachOSwiftSectionRepresentableWithCache
    ) -> [SymbolicManglingReference]? {
        guard offset >= 0, let mangledName = try? MangledName.resolve(from: offset, in: machO) else { return nil }
        let lookups = mangledName.lookupElements
        guard lookups.count == referentCount, referentCount <= Int(UInt16.max) else { return nil }
        var references: [SymbolicManglingReference] = []
        references.reserveCapacity(lookups.count)
        for (referentIndex, lookup) in lookups.enumerated() {
            guard case .relative(let relativeReference) = lookup.reference else { return nil }
            references.append(SymbolicManglingReference(
                kind: .init(rawValue: relativeReference.kind),
                referenceOffset: lookup.offset,
                referencedOffset: lookup.offset + Int(relativeReference.relativeOffset),
                symbolPosition: UInt32(symbolPosition),
                referentIndex: UInt16(referentIndex)
            ))
        }
        return references
    }
}
