/// The result of folding a sequence of field layouts into an aggregate: the
/// per-field byte offsets plus the aggregate's own `StaticTypeLayout` components.
public struct AggregateLayout: Sendable, Hashable {
    /// The byte offset of each field, in declaration order.
    public let fieldOffsets: [Int]
    /// The aggregate's significant size (offset of the last field plus its
    /// size), excluding trailing stride padding.
    public let size: Int
    /// The aggregate's stride (`size` rounded up to `alignmentMask`).
    public let stride: Int
    /// The aggregate's alignment mask (max of the start and all field masks).
    public let alignmentMask: Int
    /// Whether every field is bitwise-takable.
    public let isBitwiseTakable: Bool
    /// The value-aggregate extra-inhabitant count: the maximum over the
    /// fields' extra inhabitants, matching the runtime's value-type rule
    /// (`swift_initStructMetadata` / `swift_getTupleTypeMetadata`: "use the
    /// field with the most"). For a **class instance** layout this word is not
    /// a class *value*'s XI — a class reference's extra inhabitants are supplied
    /// at the field site (`.pointerSized`), so this value is simply unused
    /// there.
    public let extraInhabitantCount: Int

    /// The aggregate viewed as a `StaticTypeLayout`, carrying the value-aggregate
    /// extra-inhabitant count derived in `compute` (the max over fields).
    public func asStaticTypeLayout() -> StaticTypeLayout {
        StaticTypeLayout(
            size: size,
            stride: stride,
            alignmentMask: alignmentMask,
            extraInhabitantCount: extraInhabitantCount,
            isBitwiseTakable: isBitwiseTakable
        )
    }
}

/// Offline port of the Swift runtime's `performBasicLayout`
/// (`stdlib/public/runtime/Metadata.cpp`), the shared core that lays out
/// struct, class, and tuple fields.
public enum BasicLayout {
    /// Folds `fieldLayouts` into an `AggregateLayout`, starting the offset
    /// accumulator at `startOffset` (0 for structs/tuples, the superclass
    /// instance size for classes) with initial alignment `startAlignmentMask`.
    ///
    /// Mirrors the runtime exactly: each field is placed at the accumulator
    /// rounded up to the field's alignment, the accumulator then advances by
    /// the field's **size** (not stride), and trailing padding lands only in
    /// `stride`, never in `size`.
    public static func compute(
        startOffset: Int,
        startAlignmentMask: Int,
        fieldLayouts: [StaticTypeLayout]
    ) -> AggregateLayout {
        var offsetAccumulator = startOffset
        var alignmentMask = startAlignmentMask
        var isBitwiseTakable = true
        var extraInhabitantCount = 0
        var fieldOffsets: [Int] = []
        fieldOffsets.reserveCapacity(fieldLayouts.count)

        for fieldLayout in fieldLayouts {
            let fieldAlignmentMask = fieldLayout.alignmentMask
            let alignedOffset = (offsetAccumulator + fieldAlignmentMask) & ~fieldAlignmentMask
            fieldOffsets.append(alignedOffset)
            offsetAccumulator = alignedOffset + fieldLayout.size
            alignmentMask = max(alignmentMask, fieldAlignmentMask)
            isBitwiseTakable = isBitwiseTakable && fieldLayout.isBitwiseTakable
            // A value aggregate takes its extra inhabitants from the field with
            // the most (runtime `swift_initStructMetadata` / tuple metadata).
            extraInhabitantCount = max(extraInhabitantCount, fieldLayout.extraInhabitantCount)
        }

        let size = offsetAccumulator
        let stride = max(1, (size + alignmentMask) & ~alignmentMask)

        return AggregateLayout(
            fieldOffsets: fieldOffsets,
            size: size,
            stride: stride,
            alignmentMask: alignmentMask,
            isBitwiseTakable: isBitwiseTakable,
            extraInhabitantCount: extraInhabitantCount
        )
    }
}
