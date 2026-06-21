import Testing
@testable import SwiftLayout

/// Pure numeric tests for the `performBasicLayout` port — no Mach-O involved.
@Suite
struct BasicLayoutTests {
    private let int = TypeLayoutInfo.fixedWidthScalar(byteCount: 8)
    private let int32 = TypeLayoutInfo.fixedWidthScalar(byteCount: 4)
    private let int16 = TypeLayoutInfo.fixedWidthScalar(byteCount: 2)
    private let int8 = TypeLayoutInfo.fixedWidthScalar(byteCount: 1)

    @Test func threeWordFieldsArePackedAtEightByteStride() {
        let result = BasicLayout.compute(startOffset: 0, startAlignmentMask: 0, fieldLayouts: [int, int, int])
        #expect(result.fieldOffsets == [0, 8, 16])
        #expect(result.size == 24)
        #expect(result.stride == 24)
        #expect(result.alignmentMask == 7)
    }

    @Test func mixedAlignmentRoundsEachFieldUp() {
        // Int8 at 0, then Int needs 8-byte alignment -> jumps to offset 8.
        let result = BasicLayout.compute(startOffset: 0, startAlignmentMask: 0, fieldLayouts: [int8, int])
        #expect(result.fieldOffsets == [0, 8])
        #expect(result.size == 16)
        #expect(result.stride == 16)
        #expect(result.alignmentMask == 7)
    }

    @Test func smallFieldsPackTightlyByAlignment() {
        // Int8 at 0, Int16 aligned to 2 -> offset 2, Int32 aligned to 4 -> offset 4.
        let result = BasicLayout.compute(startOffset: 0, startAlignmentMask: 0, fieldLayouts: [int8, int16, int32])
        #expect(result.fieldOffsets == [0, 2, 4])
        #expect(result.size == 8)
        #expect(result.stride == 8)
        #expect(result.alignmentMask == 3)
    }

    @Test func trailingPaddingLandsOnlyInStride() {
        // Int at 0, Int8 at 8 -> size 9, but stride rounds up to 16.
        let result = BasicLayout.compute(startOffset: 0, startAlignmentMask: 0, fieldLayouts: [int, int8])
        #expect(result.fieldOffsets == [0, 8])
        #expect(result.size == 9)
        #expect(result.stride == 16)
        #expect(result.alignmentMask == 7)
    }

    @Test func emptyAggregateHasZeroSizeAndUnitStride() {
        let result = BasicLayout.compute(startOffset: 0, startAlignmentMask: 0, fieldLayouts: [])
        #expect(result.fieldOffsets == [])
        #expect(result.size == 0)
        #expect(result.stride == 1)
    }

    @Test func classStartsAtSuperclassInstanceSize() {
        // A root class instance starts at sizeof(HeapObject) == 16, 8-byte aligned.
        let result = BasicLayout.compute(startOffset: 16, startAlignmentMask: 7, fieldLayouts: [int, int8])
        #expect(result.fieldOffsets == [16, 24])
        #expect(result.size == 25)
        #expect(result.stride == 32)
    }
}
