/// The statically computed memory layout of a Swift type, mirroring the four
/// leading words of a runtime value-witness table's `TargetTypeLayout`
/// (`size`, `stride`, `flags`, `extraInhabitantCount`) but produced entirely
/// offline — without loading the process or reading a runtime value-witness
/// table.
///
/// This is the unit both consumed and produced by the layout engine: every
/// stored-property field resolves to a `TypeLayoutInfo`, and the aggregate
/// (`runBasicLayout`) folds a sequence of them into the enclosing type's own
/// `TypeLayoutInfo`.
public struct TypeLayoutInfo: Sendable, Hashable {
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

extension TypeLayoutInfo {
    /// A single machine pointer / class reference: 8 bytes, 8-byte aligned,
    /// with the runtime's standard 0x1000 pointer extra inhabitants (the low
    /// addresses reserved as invalid).
    public static let pointerSized = TypeLayoutInfo(
        size: 8,
        stride: 8,
        alignmentMask: 7,
        extraInhabitantCount: 0x1000,
        isBitwiseTakable: true
    )

    /// `Swift.Bool`: a single byte holding `0`/`1`, leaving 254 extra
    /// inhabitants (the patterns `2...255`).
    public static let bool = TypeLayoutInfo(
        size: 1,
        stride: 1,
        alignmentMask: 0,
        extraInhabitantCount: 254,
        isBitwiseTakable: true
    )

    /// A fixed-width integer / floating-point primitive whose `size` and
    /// `stride` equal `byteCount`, naturally aligned, with no extra
    /// inhabitants (every bit pattern is a valid value).
    public static func fixedWidthScalar(byteCount: Int) -> TypeLayoutInfo {
        TypeLayoutInfo(
            size: byteCount,
            stride: byteCount,
            alignmentMask: byteCount - 1,
            extraInhabitantCount: 0,
            isBitwiseTakable: true
        )
    }

    /// The empty layout (`size == stride == 0`): the unit/`Void` shape and the
    /// identity element for aggregate accumulation.
    public static let empty = TypeLayoutInfo(
        size: 0,
        stride: 1,
        alignmentMask: 0,
        extraInhabitantCount: 0,
        isBitwiseTakable: true
    )
}
