/// The statically computed memory layout of a Swift type, mirroring the four
/// leading words of a runtime value-witness table's `TargetTypeLayout`
/// (`size`, `stride`, `flags`, `extraInhabitantCount`) but produced entirely
/// offline — without loading the process or reading a runtime value-witness
/// table.
///
/// This is the unit both consumed and produced by the layout engine: every
/// stored-property field resolves to a `StaticTypeLayout`, and the aggregate
/// (`runBasicLayout`) folds a sequence of them into the enclosing type's own
/// `StaticTypeLayout`.
public struct StaticTypeLayout: Sendable, Hashable {
    /// The number of bytes used by the type's significant data, excluding the
    /// trailing padding that distinguishes `stride` from `size`.
    public let size: Int

    /// The number of bytes from one element to the next in a contiguous array
    /// (`size` rounded up to `alignmentMask`). Always at least `1`.
    public let stride: Int

    /// The alignment requirement encoded as a mask: a value is aligned when
    /// `address & alignmentMask == 0`, so `alignment == alignmentMask + 1`.
    /// Matches the runtime's low-8-bits alignment-mask encoding.
    public let alignmentMask: Int

    /// The number of extra inhabitants — bit patterns that are invalid for the
    /// type and therefore available to encode enum tags (e.g. `Optional`).
    public let extraInhabitantCount: Int

    /// Whether the type can be moved with a plain bitwise copy. Propagated so
    /// an aggregate is bitwise-takable only when all its fields are.
    public let isBitwiseTakable: Bool

    public init(
        size: Int,
        stride: Int,
        alignmentMask: Int,
        extraInhabitantCount: Int,
        isBitwiseTakable: Bool
    ) {
        self.size = size
        self.stride = stride
        self.alignmentMask = alignmentMask
        self.extraInhabitantCount = extraInhabitantCount
        self.isBitwiseTakable = isBitwiseTakable
    }

    /// The alignment in bytes (`alignmentMask + 1`).
    public var alignment: Int { alignmentMask + 1 }

    /// Rounds `size` up to the given alignment mask, matching the runtime's
    /// `roundUpToAlignMask`.
    public func sizeRoundedUp(toAlignmentMask alignmentMask: Int) -> Int {
        (size + alignmentMask) & ~alignmentMask
    }
}

extension StaticTypeLayout {
    /// A single managed-pointer word — a class/heap-object reference, a
    /// metadata pointer (thick metatype, existential metadata word), a
    /// function pointer, an Objective-C block or `Unmanaged`/`unowned(unsafe)`
    /// reference: 8 bytes, 8-byte aligned, with the exact runtime
    /// extra-inhabitant count. On 64-bit Darwin every pointer below
    /// `LeastValidPointerValue` (0x1_0000_0000, the reserved low 4 GiB) is
    /// invalid, so the raw count saturates at
    /// `ValueWitnessFlags::MaxNumExtraInhabitants` (0x7FFF_FFFF) — the
    /// runtime's `getHeapObjectExtraInhabitantCount` (`KnownMetadata.cpp`) and
    /// IRGen's `ExtraInhabitants.cpp` agree, and the same saturated count was
    /// measured from live value-witness tables for function pointers, blocks,
    /// and metatype/existential metadata words alike.
    public static let pointerSized = StaticTypeLayout(
        size: 8,
        stride: 8,
        alignmentMask: 7,
        extraInhabitantCount: 0x7FFF_FFFF,
        isBitwiseTakable: true
    )

    /// A raw/typed *unsafe* pointer (`UnsafeRawPointer`, `UnsafePointer<T>`,
    /// `OpaquePointer`, `AutoreleasingUnsafeMutablePointer`, `CVaListPointer`,
    /// `Builtin.RawPointer`): one word whose **only** invalid representation is
    /// null — unlike a managed reference, it may legally hold any other bit
    /// pattern (a C pointer can point into the low 4 GiB). IRGen's
    /// `PointerInfo` nullable-only lowering and the stdlib's
    /// `Builtin.RawPointer` witness table both report exactly 1 extra
    /// inhabitant, which is why `Optional<Optional<UnsafeRawPointer>>` is 9
    /// bytes while `Optional<Optional<AnyObject>>` stays 8.
    public static let rawPointer = StaticTypeLayout(
        size: 8,
        stride: 8,
        alignmentMask: 7,
        extraInhabitantCount: 1,
        isBitwiseTakable: true
    )

    /// A `weak` reference's storage word: no extra inhabitants (a weak
    /// reference legally becomes null when the referent dies, so null cannot
    /// encode an enum tag) and **not** bitwise-takable (moving it must update
    /// the side-table registration — `swift_weakTakeInit`). Matches
    /// RemoteInspection `TypeLowering.cpp` (`ReferenceKind::Weak`:
    /// `numExtraInhabitants = 0; bitwiseTakable = false`) and the live
    /// value-witness tables of weak-containing aggregates.
    public static let weakReference = StaticTypeLayout(
        size: 8,
        stride: 8,
        alignmentMask: 7,
        extraInhabitantCount: 0,
        isBitwiseTakable: false
    )

    /// An `unowned` (safe) reference's storage word: exactly **1** extra
    /// inhabitant. With Objective-C interop the compiler must stay
    /// conservative about the referent's refcounting, so
    /// `IRGenModule::getReferenceStorageExtraInhabitantCount`
    /// (`GenHeap.cpp`) falls through to "pointer semantics, therefore null is
    /// the only extra inhabitant allowed" — measured: an enum with two empty
    /// cases over an unowned-containing struct grows a tag byte (size 9).
    /// Note RemoteInspection's `TypeLowering.cpp` instead claims unowned
    /// shares the underlying reference's count — that contradicts both IRGen
    /// and the live value-witness tables on Darwin, so the engine follows the
    /// runtime. (An unknown-refcounting `unowned` is additionally not
    /// bitwise-takable; the engine cannot always see the referent's ancestry,
    /// so it models the native, takable case — a flag-only divergence that
    /// never moves an offset.)
    public static let unownedReference = StaticTypeLayout(
        size: 8,
        stride: 8,
        alignmentMask: 7,
        extraInhabitantCount: 1,
        isBitwiseTakable: true
    )

    /// A thick Swift function value (`@escaping`/default convention): a
    /// (function pointer, context pointer) pair. Extra inhabitants come from
    /// the function-pointer word (`ThickFunctionBox` in `KnownMetadata.cpp`
    /// takes `FunctionPointerBox::numExtraInhabitants`), which saturates at
    /// 0x7FFF_FFFF on 64-bit Darwin like every managed pointer — so
    /// `Optional<() -> Void>` stays 16 bytes. Bitwise-takable: moving the pair
    /// transfers the context's ownership without any fixup (only `weak`
    /// storage pins its address).
    public static let thickFunction = StaticTypeLayout(
        size: 16,
        stride: 16,
        alignmentMask: 7,
        extraInhabitantCount: 0x7FFF_FFFF,
        isBitwiseTakable: true
    )

    /// `Swift.Bool`: a single byte holding `0`/`1`, leaving 254 extra
    /// inhabitants (the patterns `2...255`).
    public static let bool = StaticTypeLayout(
        size: 1,
        stride: 1,
        alignmentMask: 0,
        extraInhabitantCount: 254,
        isBitwiseTakable: true
    )

    /// A fixed-width integer / floating-point primitive whose `size` and
    /// `stride` equal `byteCount`, naturally aligned, with no extra
    /// inhabitants (every bit pattern is a valid value).
    public static func fixedWidthScalar(byteCount: Int) -> StaticTypeLayout {
        StaticTypeLayout(
            size: byteCount,
            stride: byteCount,
            alignmentMask: byteCount - 1,
            extraInhabitantCount: 0,
            isBitwiseTakable: true
        )
    }

    /// The empty layout (`size == stride == 0`): the unit/`Void` shape and the
    /// identity element for aggregate accumulation.
    public static let empty = StaticTypeLayout(
        size: 0,
        stride: 1,
        alignmentMask: 0,
        extraInhabitantCount: 0,
        isBitwiseTakable: true
    )
}
