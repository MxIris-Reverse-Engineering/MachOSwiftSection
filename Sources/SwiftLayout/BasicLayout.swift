/// The result of folding a sequence of field layouts into an aggregate: the
/// per-field byte offsets plus the aggregate's own `TypeLayoutInfo` components.
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

    /// The aggregate viewed as a `TypeLayoutInfo`. Extra inhabitants are not
    /// derived here (a struct/class does not inherit a field's spare patterns
    /// in general), so the caller supplies them — defaulting to `0`.
    public func typeLayoutInfo(extraInhabitantCount: Int = 0) -> TypeLayoutInfo {
        TypeLayoutInfo(
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
        fieldLayouts: [TypeLayoutInfo]
    ) -> AggregateLayout {
        var offsetAccumulator = startOffset
        var alignmentMask = startAlignmentMask
        var isBitwiseTakable = true
        var fieldOffsets: [Int] = []
        fieldOffsets.reserveCapacity(fieldLayouts.count)

        for fieldLayout in fieldLayouts {
            let fieldAlignmentMask = fieldLayout.alignmentMask
            let alignedOffset = (offsetAccumulator + fieldAlignmentMask) & ~fieldAlignmentMask
            fieldOffsets.append(alignedOffset)
            offsetAccumulator = alignedOffset + fieldLayout.size
            alignmentMask = max(alignmentMask, fieldAlignmentMask)
            isBitwiseTakable = isBitwiseTakable && fieldLayout.isBitwiseTakable
        }

        let size = offsetAccumulator
        let stride = max(1, (size + alignmentMask) & ~alignmentMask)

        return AggregateLayout(
            fieldOffsets: fieldOffsets,
            size: size,
            stride: stride,
            alignmentMask: alignmentMask,
            isBitwiseTakable: isBitwiseTakable
        )
    }
}
