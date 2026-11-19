@_spi(Internals) import MachOCodeReferences

/// What an address is: where it lies — the image, segment and section — and
/// what it means there. What `atos` answers for a function, and what it does
/// not: a stub and the function it leads to, a pointer slot and what it
/// holds, a string's characters.
public struct AddressSymbolication: Hashable, Sendable {
    /// The address asked about, unslid.
    public let address: UInt64
    /// The image the address lies in; `nil` between images or nowhere.
    public let imagePath: String?
    public let segmentName: String?
    public let sectionName: String?
    public let meaning: Meaning

    public init(address: UInt64, imagePath: String?, segmentName: String?, sectionName: String?, meaning: Meaning) {
        self.address = address
        self.imagePath = imagePath
        self.segmentName = segmentName
        self.sectionName = sectionName
        self.meaning = meaning
    }

    public enum Meaning: Hashable, Sendable {
        /// Inside a function's body: where the function starts, its name —
        /// from its symbol, its export, an Objective-C method list or the
        /// Swift metadata — and how far into it the address lies.
        case function(start: CodeLocation, name: String?, offset: UInt64)
        /// A stub or a stub island's trampoline: every trampoline passed
        /// through, starting with the address asked about, and where the
        /// chain leads.
        case stub(hops: [UInt64], target: CodeReferenceTarget)
        /// A pointer slot and what it holds.
        case pointerSlot(PointerSlotKind, target: CodeReferenceTarget)
        case cString(String)
        case constantString(String)
        /// None of the above: the nearest symbol at or below the address.
        case symbol(name: String, offset: UInt64)
        /// Mapped by an image, but none of the above, and no symbol lies at
        /// or below it.
        case data
        /// Not inside any image the analyzer covers, nor between the images
        /// of its shared cache.
        case unmapped
    }

    /// Which kind of pointer slot: the section it lies in says.
    public enum PointerSlotKind: Hashable, Sendable {
        /// `__got`, `__auth_got`, a lazy or non-lazy symbol pointer, or the
        /// GOT a shared cache keeps outside every image.
        case globalOffsetTable
        /// `__objc_selrefs`.
        case selectorReference
        /// `__objc_classrefs`.
        case classReference
        /// `__objc_superrefs`.
        case superclassReference
        /// `__objc_protorefs`.
        case protocolReference
        /// `__objc_ivar`: an instance variable's offset variable, a 32-bit
        /// value rather than a pointer.
        case instanceVariableOffset
    }
}
