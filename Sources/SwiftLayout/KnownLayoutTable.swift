/// A hard-coded table of fully-qualified Swift standard-library type names to
/// their frozen ABI layouts.
///
/// These layouts are part of Swift's permanently stable ABI, so they can be
/// answered without reading any descriptor. The table is consulted *before*
/// recursing into a structure's field descriptor — critical for types like
/// `Array`/`Dictionary`/`Set` whose in-memory layout (a single buffer pointer)
/// is independent of their generic arguments and must NOT be derived by
/// expanding their internal storage fields.
///
/// Extra-inhabitant counts are the **exact** runtime values (verified against
/// live value-witness tables and the IRGen/runtime sources): an unsafe pointer
/// reserves only null (1), a managed buffer reference saturates at
/// `MaxNumExtraInhabitants` (0x7FFF_FFFF on 64-bit Darwin), and integers have
/// none. Exactness matters beyond display — a single-payload enum's size
/// depends on whether its empty cases fit the payload's extra inhabitants, so
/// an under- or over-estimate here moves real field offsets.
public enum KnownLayoutTable {
    /// Returns the frozen layout for a fully-qualified type name such as
    /// `"Swift.Int"`, or `nil` if the type is not a known fixed-layout
    /// primitive.
    public static func layout(forFullyQualifiedTypeName fullyQualifiedTypeName: String) -> StaticTypeLayout? {
        knownLayouts[fullyQualifiedTypeName]
    }

    private static let knownLayouts: [String: StaticTypeLayout] = {
        var table: [String: StaticTypeLayout] = [:]

        // Word-sized integers.
        for wordIntegerName in ["Swift.Int", "Swift.UInt", "Swift.Int64", "Swift.UInt64"] {
            table[wordIntegerName] = .fixedWidthScalar(byteCount: 8)
        }
        // 32-bit integers.
        for thirtyTwoBitIntegerName in ["Swift.Int32", "Swift.UInt32"] {
            table[thirtyTwoBitIntegerName] = .fixedWidthScalar(byteCount: 4)
        }
        // 16-bit integers.
        for sixteenBitIntegerName in ["Swift.Int16", "Swift.UInt16"] {
            table[sixteenBitIntegerName] = .fixedWidthScalar(byteCount: 2)
        }
        // 8-bit integers.
        for eightBitIntegerName in ["Swift.Int8", "Swift.UInt8"] {
            table[eightBitIntegerName] = .fixedWidthScalar(byteCount: 1)
        }
        // 128-bit integers.
        for hundredTwentyEightBitIntegerName in ["Swift.Int128", "Swift.UInt128"] {
            table[hundredTwentyEightBitIntegerName] = .fixedWidthScalar(byteCount: 16)
        }

        // Floating point.
        table["Swift.Double"] = .fixedWidthScalar(byteCount: 8)
        table["Swift.Float64"] = .fixedWidthScalar(byteCount: 8)
        table["Swift.Float"] = .fixedWidthScalar(byteCount: 4)
        table["Swift.Float32"] = .fixedWidthScalar(byteCount: 4)

        // Boolean.
        table["Swift.Bool"] = .bool

        // Raw / typed single pointers and opaque pointers — one machine word
        // whose only invalid representation is null (`Optional<Optional<…>>`
        // of any of these is 9 bytes, unlike a managed reference's 8).
        for singlePointerName in [
            "Swift.UnsafeRawPointer",
            "Swift.UnsafeMutableRawPointer",
            "Swift.OpaquePointer",
            "Swift.UnsafePointer",
            "Swift.UnsafeMutablePointer",
            "Swift.AutoreleasingUnsafeMutablePointer",
            "Swift.CVaListPointer",
        ] {
            table[singlePointerName] = .rawPointer
        }

        // `Unmanaged` is `unowned(unsafe)` storage: a bare reference that
        // still carries the full saturated heap-object extra-inhabitant count
        // (IRGen `UNCHECKED_REF_STORAGE`: "static types have the same spare
        // bits as managed heap objects").
        table["Swift.Unmanaged"] = .pointerSized

        // Buffer pointers are a (base pointer, count) pair — two words.
        let bufferPointerLayout = StaticTypeLayout(
            size: 16, stride: 16, alignmentMask: 7, extraInhabitantCount: 0, isBitwiseTakable: true
        )
        for bufferPointerName in [
            "Swift.UnsafeBufferPointer",
            "Swift.UnsafeMutableBufferPointer",
            "Swift.UnsafeRawBufferPointer",
            "Swift.UnsafeMutableRawBufferPointer",
        ] {
            table[bufferPointerName] = bufferPointerLayout
        }

        // Standard-library reference-backed containers: a single managed
        // buffer reference regardless of element type (with the saturated
        // heap-object extra-inhabitant count). Must be matched before field
        // recursion.
        for singleBufferContainerName in [
            "Swift.Array",
            "Swift.ContiguousArray",
            "Swift.Dictionary",
            "Swift.Set",
        ] {
            table[singleBufferContainerName] = .pointerSized
        }

        // `String` / `Character` are a 16-byte `_StringObject` whose second word
        // is a tagged discriminator reserving a vast number of invalid bit
        // patterns — the runtime reports `MaxNumExtraInhabitants` (0x7FFFFFFF).
        // A too-small count (the old value of `1`) kept `Optional<String>` at 16
        // but broke any single-payload enum with *two or more* empty cases over
        // a `String` payload (`enum { case value(String); case a; case b }`):
        // only one empty case fit the lone extra inhabitant, spilling the rest
        // into a spurious tag byte (size 17 instead of 16). Using the runtime's
        // count keeps every such enum unpadded.
        let stringLayout = StaticTypeLayout(
            size: 16,
            stride: 16,
            alignmentMask: 7,
            extraInhabitantCount: 0x7FFF_FFFF,
            isBitwiseTakable: true
        )
        table["Swift.String"] = stringLayout
        table["Swift.Character"] = stringLayout

        return table
    }()
}
