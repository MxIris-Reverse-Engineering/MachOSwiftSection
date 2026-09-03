import MachOResolving
import Foundation
import MachOKit

/// One retained symbol row: 16 bytes. The row holds the canonical
/// (cache-adjusted) offset plus a packed reference to the name's bytes;
/// the name itself is materialized on demand from the table's name source
/// (evolution proposal 0001 — the previous representation retained a
/// 32-byte `Symbol` with an interned `String` per row).
struct SymbolRow {
    var canonicalOffset: Int64

    var packedNameReference: PackedNameReference
}

/// Packed location of a symbol name's bytes within a `SymbolTable`'s name
/// source. Layout (most significant bit first): 1 bit name source
/// (0 = mapped string table, 1 = private name buffer), 1 bit `isExternal`,
/// 22 bits byte length, 40 bits byte offset into the source.
struct PackedNameReference {
    let rawValue: UInt64

    private static let byteOffsetBitCount: UInt64 = 40
    private static let byteLengthBitCount: UInt64 = 22
    private static let byteOffsetMask: UInt64 = (1 << byteOffsetBitCount) - 1
    private static let byteLengthMask: UInt64 = (1 << byteLengthBitCount) - 1
    private static let privateNameBufferFlag: UInt64 = 1 << 63
    private static let isExternalFlag: UInt64 = 1 << 62

    /// The widest name byte length / source byte offset the packed layout
    /// can represent. Values beyond these arrive only from malformed or
    /// hostile input — no legitimate mangled name approaches the 4 MB
    /// length budget — so the initializer refuses them instead of trapping:
    /// these components are binary-supplied (strlen over a string table,
    /// accumulated buffer offsets), and a `precondition` would let the
    /// analyzed binary decide whether the host process lives.
    static var maximumByteLength: Int { Int(byteLengthMask) }
    static var maximumByteOffset: Int { Int(byteOffsetMask) }

    private init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    init?(usesPrivateNameBuffer: Bool, isExternal: Bool, byteOffset: Int, byteLength: Int) {
        guard byteOffset >= 0, UInt64(byteOffset) <= Self.byteOffsetMask,
              byteLength >= 0, UInt64(byteLength) <= Self.byteLengthMask else { return nil }
        var packed = UInt64(byteOffset) | (UInt64(byteLength) << Self.byteOffsetBitCount)
        if isExternal {
            packed |= Self.isExternalFlag
        }
        if usesPrivateNameBuffer {
            packed |= Self.privateNameBufferFlag
        }
        self.rawValue = packed
    }

    /// The same reference with only the external bit replaced — raw bit
    /// surgery, no re-validation, for updating an already-packed row in
    /// place.
    func replacingIsExternal(_ isExternal: Bool) -> PackedNameReference {
        var packed = rawValue & ~Self.isExternalFlag
        if isExternal {
            packed |= Self.isExternalFlag
        }
        return PackedNameReference(rawValue: packed)
    }

    var usesPrivateNameBuffer: Bool {
        rawValue & Self.privateNameBufferFlag != 0
    }

    var isExternal: Bool {
        rawValue & Self.isExternalFlag != 0
    }

    var byteOffset: Int {
        Int(rawValue & Self.byteOffsetMask)
    }

    var byteLength: Int {
        Int((rawValue >> Self.byteOffsetBitCount) & Self.byteLengthMask)
    }
}

/// The frozen per-image symbol table: compact rows plus the bytes their
/// names point into. Replaces the former bare `[Symbol]` (whose every row
/// retained a name `String`) and the name-keyed row dictionary.
///
/// Names come from one of two sources per row:
/// - the image's mmap'd LINKEDIT string table (`MachOImage` rows) — clean
///   pages the kernel can reclaim, read zero-copy at materialization;
/// - the table's own private contiguous byte buffer (`MachOFile` rows and
///   export-trie names, whose decoded strings exist nowhere in mapped
///   memory).
///
/// Lifetime constraint (accepted in proposal 0001): `mappedStringTableBase`
/// points into the loaded image and dangles if the image is ever unloaded.
/// Name materialization therefore requires the image to stay loaded — the
/// same requirement every other in-process read path already has, but now
/// extending to vended values' `symbol` accessor. Empirically the unload
/// cannot happen on Darwin (probed 2026-08-09, macOS 26): dyld pins every
/// image carrying Swift/ObjC content as never-unload — `dlclose` leaves
/// even a class-less Swift dylib mapped — and the only images that DO
/// unmap (pure C, no ObjC/Swift) contain no Swift-mangling-prefixed names,
/// so they never mint mapped rows in the first place. See
/// `Documentations/Internal/ReviewAdjudications.md` (A4).
///
/// The byte access layer uses `UnsafeBufferPointer` rather than
/// `Span`/`UTF8Span`: the Span family is only available at runtime on
/// macOS 26 / iOS 26 and newer, above this package's deployment floor.
///
/// `@unchecked Sendable`: every stored property is immutable after `init`.
final class SymbolTable: @unchecked Sendable {
    /// Base of the image's mmap'd string table; `nil` for tables whose rows
    /// all live in `privateNameBuffer`.
    let mappedStringTableBase: UnsafeRawPointer?

    /// Name bytes for rows outside the mapped string table — one contiguous
    /// allocation appended during the build sweep, exact-capacity at freeze.
    let privateNameBuffer: [UInt8]

    let rows: [SymbolRow]

    /// Name-order permutation over `rows`: binary search over it replaces
    /// the former `[String: UInt32]` row dictionary. Ordering and equality
    /// are exact byte comparisons — mangled names are ASCII by construction,
    /// and byte equality is precisely the identity a mangled name needs.
    let rowsSortedByName: [UInt32]

    init(mappedStringTableBase: UnsafeRawPointer?, privateNameBuffer: [UInt8], rows: [SymbolRow], rowsSortedByName: [UInt32]) {
        self.mappedStringTableBase = mappedStringTableBase
        self.privateNameBuffer = privateNameBuffer
        self.rows = rows
        self.rowsSortedByName = rowsSortedByName
    }

    /// A one-row table for a standalone value (`DemangledSymbol(symbol:demangledNode:)`
    /// and `detachedFromSharedTable()`): the name is copied into a private
    /// buffer so the detached value retains nothing image-scoped.
    convenience init(standaloneSymbol symbol: Symbol) {
        // Clamped, not trapped: the packed reference cannot represent a name
        // beyond `PackedNameReference.maximumByteLength` (4 MB — far past
        // any legitimate mangled name), and this initializer backs the
        // public `DemangledSymbol(symbol:demangledNode:)`, so absurd caller
        // input degrades to a truncated materialized name instead of
        // killing the process. Rows minted by the build sweep are
        // budget-checked there and never reach the clamp.
        let nameBytes = Array(symbol.name.utf8.prefix(PackedNameReference.maximumByteLength))
        // Never nil: byteOffset is 0 and the clamp above bounds the length.
        let packedNameReference = PackedNameReference(usesPrivateNameBuffer: true, isExternal: symbol.isExternal, byteOffset: 0, byteLength: nameBytes.count)!
        self.init(
            mappedStringTableBase: nil,
            privateNameBuffer: nameBytes,
            rows: [SymbolRow(canonicalOffset: Int64(symbol.offset), packedNameReference: packedNameReference)],
            rowsSortedByName: [0]
        )
    }

    var rowCount: Int {
        rows.count
    }

    func canonicalOffset(atRow row: UInt32) -> Int {
        Int(rows[Int(row)].canonicalOffset)
    }

    func isExternal(atRow row: UInt32) -> Bool {
        rows[Int(row)].packedNameReference.isExternal
    }

    /// Scoped access to a row's raw name bytes (no terminator). The buffer
    /// is only valid inside `body` — for mapped rows it points straight into
    /// the image's string table.
    func withNameBytes<Result>(atRow row: UInt32, _ body: (UnsafeBufferPointer<UInt8>) throws -> Result) rethrows -> Result {
        let nameReference = rows[Int(row)].packedNameReference
        if nameReference.usesPrivateNameBuffer {
            return try privateNameBuffer.withUnsafeBufferPointer { buffer in
                try body(UnsafeBufferPointer(rebasing: buffer[nameReference.byteOffset ..< nameReference.byteOffset + nameReference.byteLength]))
            }
        } else {
            let baseAddress = mappedStringTableBase.unsafelyUnwrapped.advanced(by: nameReference.byteOffset).assumingMemoryBound(to: UInt8.self)
            return try body(UnsafeBufferPointer(start: baseAddress, count: nameReference.byteLength))
        }
    }

    /// Builds the row's name `String` on demand. `String(decoding:)` repairs
    /// invalid UTF-8 exactly like the `String(cString:)` the eager
    /// representation used, so materialized names match it byte for byte.
    func materializedName(atRow row: UInt32) -> String {
        withNameBytes(atRow: row) { String(decoding: $0, as: UTF8.self) }
    }

    /// The row's `Symbol` with its canonical (cache-adjusted) offset.
    func symbol(atRow row: UInt32) -> Symbol {
        let symbolRow = rows[Int(row)]
        return Symbol(offset: Int(symbolRow.canonicalOffset), name: materializedName(atRow: row), isExternal: symbolRow.packedNameReference.isExternal)
    }

    /// The table row holding `name`, via binary search over the name-order
    /// permutation. Comparison is on raw bytes, so a hit means exact byte
    /// equality with the queried string's UTF-8.
    func row(forName name: String) -> UInt32? {
        var mutableName = name
        return mutableName.withUTF8 { nameBytes -> UInt32? in
            var lowerBound = 0
            var upperBound = rowsSortedByName.count
            while lowerBound < upperBound {
                let middle = (lowerBound + upperBound) / 2
                let candidateRow = rowsSortedByName[middle]
                let ordering = withNameBytes(atRow: candidateRow) { compareSymbolNameBytes($0, nameBytes) }
                if ordering == 0 {
                    return candidateRow
                } else if ordering < 0 {
                    lowerBound = middle + 1
                } else {
                    upperBound = middle
                }
            }
            return nil
        }
    }
}

/// Build-time accumulator for `SymbolTable`. Holds a name-keyed dedup
/// dictionary that exists only until `freeze()` — the frozen table answers
/// name lookups by binary search instead.
struct SymbolTableBuilder {
    private let mappedStringTableBase: UnsafeRawPointer?

    private var rows: [SymbolRow] = []

    private var privateNameBuffer: [UInt8] = []

    /// Build-time dedup only; discarded at freeze. Keys are transient
    /// `String`s materialized per Swift-flagged symbol.
    private var tableRowByName: [String: UInt32] = [:]

    init(mappedStringTableBase: UnsafeRawPointer?) {
        self.mappedStringTableBase = mappedStringTableBase
    }

    var rowCount: Int {
        rows.count
    }

    func existingRow(forName name: String) -> UInt32? {
        tableRowByName[name]
    }

    /// The table row for a symbol whose name lives in the mapped string
    /// table, plus whether this call created it. A duplicate name updates
    /// the existing row's offset and external bit in place (last-wins, like
    /// the former name-keyed collection pass) and keeps the first
    /// occurrence's name reference — the bytes are equal by definition.
    mutating func canonicalRow(forName name: String, mappedNameByteOffset: Int, nameByteLength: Int, canonicalOffset: Int, isExternal: Bool) -> (row: UInt32, isNewRow: Bool)? {
        precondition(mappedStringTableBase != nil, "mapped name references require a mapped string table base")
        // The offset and length are binary-supplied (a pointer difference
        // into the mapped string table, and strlen over it): a name whose
        // geometry cannot pack is malformed input, and its row is refused —
        // the caller skips the symbol — rather than trapping the process.
        guard let nameReference = PackedNameReference(usesPrivateNameBuffer: false, isExternal: isExternal, byteOffset: mappedNameByteOffset, byteLength: nameByteLength) else {
            return nil
        }
        return canonicalRow(
            forName: name,
            nameReference: nameReference,
            canonicalOffset: canonicalOffset
        )
    }

    /// The table row for a symbol whose name has no mapped-memory home
    /// (`MachOFile` rows, export-trie names): a new row appends the name's
    /// bytes to the private buffer. Refuses (returns `nil` for) a name
    /// whose geometry cannot pack — same budget rule as the mapped
    /// overload, validated BEFORE appending so a refused name leaves no
    /// orphan bytes in the buffer.
    mutating func canonicalRow(forName name: String, canonicalOffset: Int, isExternal: Bool) -> (row: UInt32, isNewRow: Bool)? {
        if let existingRow = tableRowByName[name] {
            updateRowInPlace(existingRow, canonicalOffset: canonicalOffset, isExternal: isExternal)
            return (existingRow, false)
        }
        let byteOffset = privateNameBuffer.count
        guard name.utf8.count <= PackedNameReference.maximumByteLength,
              byteOffset <= PackedNameReference.maximumByteOffset else {
            return nil
        }
        privateNameBuffer.append(contentsOf: name.utf8)
        // Never nil: both components were bounds-checked above.
        let nameReference = PackedNameReference(usesPrivateNameBuffer: true, isExternal: isExternal, byteOffset: byteOffset, byteLength: privateNameBuffer.count - byteOffset)!
        return appendRow(forName: name, nameReference: nameReference, canonicalOffset: canonicalOffset)
    }

    private mutating func canonicalRow(forName name: String, nameReference: PackedNameReference, canonicalOffset: Int) -> (row: UInt32, isNewRow: Bool) {
        if let existingRow = tableRowByName[name] {
            updateRowInPlace(existingRow, canonicalOffset: canonicalOffset, isExternal: nameReference.isExternal)
            return (existingRow, false)
        }
        return appendRow(forName: name, nameReference: nameReference, canonicalOffset: canonicalOffset)
    }

    private mutating func updateRowInPlace(_ row: UInt32, canonicalOffset: Int, isExternal: Bool) {
        rows[Int(row)] = SymbolRow(
            canonicalOffset: Int64(canonicalOffset),
            packedNameReference: rows[Int(row)].packedNameReference.replacingIsExternal(isExternal)
        )
    }

    private mutating func appendRow(forName name: String, nameReference: PackedNameReference, canonicalOffset: Int) -> (row: UInt32, isNewRow: Bool) {
        let newRow = UInt32(rows.count)
        rows.append(SymbolRow(canonicalOffset: Int64(canonicalOffset), packedNameReference: nameReference))
        tableRowByName[name] = newRow
        return (newRow, true)
    }

    /// Freezes into the immutable table: exact-capacity copies drop the
    /// append-time growth slack, the dedup dictionary is discarded, and the
    /// name-order permutation is sorted for binary search.
    consuming func freeze() -> SymbolTable {
        let frozenRows = exactCapacityCopy(rows)
        let frozenNameBuffer = exactCapacityCopy(privateNameBuffer)
        var permutation = Array(UInt32(0) ..< UInt32(frozenRows.count))
        let frozenMappedStringTableBase = mappedStringTableBase
        frozenNameBuffer.withUnsafeBufferPointer { privateBuffer in
            func nameBytes(ofRow row: UInt32) -> UnsafeBufferPointer<UInt8> {
                let nameReference = frozenRows[Int(row)].packedNameReference
                if nameReference.usesPrivateNameBuffer {
                    return UnsafeBufferPointer(rebasing: privateBuffer[nameReference.byteOffset ..< nameReference.byteOffset + nameReference.byteLength])
                } else {
                    let baseAddress = frozenMappedStringTableBase.unsafelyUnwrapped.advanced(by: nameReference.byteOffset).assumingMemoryBound(to: UInt8.self)
                    return UnsafeBufferPointer(start: baseAddress, count: nameReference.byteLength)
                }
            }
            permutation.sort { compareSymbolNameBytes(nameBytes(ofRow: $0), nameBytes(ofRow: $1)) < 0 }
        }
        return SymbolTable(
            mappedStringTableBase: frozenMappedStringTableBase,
            privateNameBuffer: frozenNameBuffer,
            rows: frozenRows,
            rowsSortedByName: permutation
        )
    }

    private func exactCapacityCopy<Element>(_ elements: [Element]) -> [Element] {
        guard elements.capacity > elements.count else { return elements }
        var copy: [Element] = []
        copy.reserveCapacity(elements.count)
        copy.append(contentsOf: elements)
        return copy
    }
}

/// Three-way byte comparison (`memcmp` order with length tiebreak) — the
/// ordering `rowsSortedByName` is sorted by and searched with.
func compareSymbolNameBytes(_ left: UnsafeBufferPointer<UInt8>, _ right: UnsafeBufferPointer<UInt8>) -> Int {
    let commonByteCount = min(left.count, right.count)
    if commonByteCount > 0 {
        let ordering = Int(memcmp(left.baseAddress.unsafelyUnwrapped, right.baseAddress.unsafelyUnwrapped, commonByteCount))
        if ordering != 0 {
            return ordering
        }
    }
    return left.count - right.count
}

/// Byte-level `isSwiftSymbol` over a C string: mirrors
/// `Demangling.getManglingPrefixLength`'s prefix set exactly (`_T0`, `_$S`,
/// `_$s`, `_$e`, `$S`, `$s`, `$e`, `@__swiftmacro_`) so the build sweep can
/// reject a non-Swift symbol without materializing its name. `strncmp`
/// stops at the terminator, so short names are safe. Pinned equal to
/// `String.isSwiftSymbol` over a full real symbol table by
/// `SymbolTableEquivalenceTests`.
func nameBytesHaveSwiftManglingPrefix(_ nameC: UnsafePointer<CChar>) -> Bool {
    switch nameC.pointee {
    case 0x5F: // "_"
        return strncmp(nameC, "_T0", 3) == 0 || strncmp(nameC, "_$S", 3) == 0 || strncmp(nameC, "_$s", 3) == 0 || strncmp(nameC, "_$e", 3) == 0
    case 0x24: // "$"
        return strncmp(nameC, "$S", 2) == 0 || strncmp(nameC, "$s", 2) == 0 || strncmp(nameC, "$e", 2) == 0
    case 0x40: // "@"
        return strncmp(nameC, "@__swiftmacro_", 14) == 0
    default:
        return false
    }
}
