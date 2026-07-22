import Foundation
import MachOSwiftSection
#if _ptrauth(_arm64e)
import MachOSwiftSectionC
#endif

/// Materializes an enum's per-case memory patterns by driving the enum's own
/// value witnesses over live in-process metadata.
///
/// `EnumLayoutCalculator` *predicts* case patterns from layout formulas. That
/// works when the tag lives in dedicated bytes (extra tag bytes, spare-bit
/// masks read from `__swift5_mpenum`), but a single-payload enum stores its
/// empty cases as the payload's **extra inhabitants** — invalid bit patterns
/// whose concrete bytes depend on the payload type (a class reference's extra
/// inhabitants are small invalid addresses `0x0, 0x1, 0x2, …`; `String`'s are
/// reserved `_StringObject` discriminator patterns; `Optional` wrapping shifts
/// the sequence by one) and compose recursively through nested payloads. No
/// formula over "how many" extra inhabitants can recover "which bytes".
///
/// When the enum's metadata is loaded in the current process there is no need
/// to predict: the compiler-emitted `destructiveInjectEnumTag` value witness
/// writes each case's exact discriminator pattern, and `getEnumTag` reads it
/// back (Swift runtime: `swift/stdlib/public/runtime/EnumImpl.h`,
/// `storeEnumTagSinglePayloadImpl` / `getEnumTagSinglePayloadImpl`).
///
/// Mechanism, per case tag:
/// 1. Fill one scratch buffer with `0x00` and another with `0xFF`.
/// 2. Call `destructiveInjectEnumTag(buffer, tag)` on both.
/// 3. A byte on which the two buffers agree afterwards was deterministically
///    written by the witness — it is part of the case's fixed pattern. A byte
///    on which they disagree was left untouched (payload storage or padding).
/// 4. For an empty case, read the tag back with `getEnumTag` from the zeroed
///    buffer and require it to round-trip. (A payload case cannot be
///    round-tripped this way: its injection writes no payload, and the
///    leftover zero bytes may themselves spell a valid extra-inhabitant
///    pattern — e.g. a null class reference.)
///
/// Injecting an empty case only writes tag machinery — an extra-inhabitant
/// pattern is by definition an *invalid* payload value, never a live object
/// reference — so the scratch buffers need no destruction.
///
/// The dual-baseline diff assumes the inject witness *stores* its pattern
/// rather than merging it with existing payload bits. That holds for the
/// single-payload strategy (extra-inhabitant stores and extra-tag stores are
/// plain writes). A multi-payload spare-bits inject ORs the tag into the
/// payload's spare bits, so callers must not use this projector for that
/// strategy — its patterns come exact from the `__swift5_mpenum` mask instead.
public enum RuntimeEnumCaseProjector {
    /// The bytes `destructiveInjectEnumTag` deterministically writes for one
    /// case, keyed by byte offset within the enum value. Offsets missing from
    /// `fixedBytes` are not part of the case's discriminator (they hold payload
    /// storage or padding).
    public struct CasePattern: Sendable {
        /// The case's tag index: payload cases first (`0 ..< payloadCaseCount`),
        /// then empty cases in declaration order — the same numbering the
        /// enum's field records and `getEnumTag` use.
        public let caseIndex: Int
        public let fixedBytes: [Int: UInt8]

        public init(caseIndex: Int, fixedBytes: [Int: UInt8]) {
            self.caseIndex = caseIndex
            self.fixedBytes = fixedBytes
        }
    }

    /// An upper bound on plausible enum sizes; a larger value read from a
    /// value-witness table almost certainly means a misread pointer.
    private static let enumSizeSanityLimit = 1 << 20

    /// Projects every case's fixed byte pattern of the enum whose metadata
    /// lives at `enumMetadataPointer` (an absolute in-process address).
    ///
    /// Returns `nil` — leaving the caller on its formula-derived patterns —
    /// when the metadata carries no enum witnesses, a size fails its sanity
    /// bound, or an empty case's pattern does not round-trip through
    /// `getEnumTag`.
    ///
    /// - Parameters:
    ///   - enumMetadataPointer: the enum's in-process metadata address (the
    ///     pointer `type(of:)` would expose as `Any.Type`).
    ///   - payloadCaseCount: the number of payload cases; tags below this are
    ///     payload cases and skip the read-back verification.
    ///   - caseCount: the total number of cases (payload + empty).
    public static func projectCasePatterns(
        enumMetadataPointer: UnsafeRawPointer,
        payloadCaseCount: Int,
        caseCount: Int
    ) -> [CasePattern]? {
        guard caseCount > 0, payloadCaseCount >= 0, payloadCaseCount <= caseCount else { return nil }

        // The value-witness table pointer sits one word before the metadata
        // (the `TargetFullMetadata` header). Loading the table's required
        // area as `ValueWitnessTable.Layout` gives size / flags; the enum
        // witnesses (`getEnumTag`, `destructiveProjectEnumData`,
        // `destructiveInjectEnumTag`) follow it in that order.
        let tablePointer = enumMetadataPointer.load(
            fromByteOffset: -MemoryLayout<UnsafeRawPointer>.size,
            as: UnsafeRawPointer.self
        )
        let requiredWitnesses = tablePointer.load(as: ValueWitnessTable.Layout.self)
        guard requiredWitnesses.flags.hasEnumWitnesses else { return nil }

        let size = Int(requiredWitnesses.size)
        guard size > 0, size <= enumSizeSanityLimit else { return nil }
        let alignment = Int(requiredWitnesses.flags.alignment)

        #if _ptrauth(_arm64e)
        // The enum witnesses are PAC-signed in the table (IA key, address
        // diversity, per-slot discriminators), and the clang importer skips
        // ptrauth-qualified members — so the calls go through the
        // `MachOSwiftSectionC` stubs, whose `EnumValueWitnessTable` declares
        // each slot with its `__ptrauth_swift_value_witness_function_pointer`
        // qualifier: the signature is auth-verified at the call, exactly as
        // the runtime itself invokes these witnesses.
        let getEnumTag: (UnsafeRawPointer, UnsafeRawPointer) -> UInt32 = { instance, metadata in
            swift_section_vwt_getEnumTag(tablePointer, instance, metadata)
        }
        let destructiveInjectEnumTag: (UnsafeMutableRawPointer, UInt32, UnsafeRawPointer) -> Void = { instance, tag, metadata in
            swift_section_vwt_destructiveInjectEnumTag(tablePointer, instance, tag, metadata)
        }
        #else
        typealias GetEnumTagWitness = @convention(c) (UnsafeRawPointer, UnsafeRawPointer) -> UInt32
        typealias DestructiveInjectEnumTagWitness = @convention(c) (UnsafeMutableRawPointer, UInt32, UnsafeRawPointer) -> Void

        let enumWitnessesOffset = MemoryLayout<ValueWitnessTable.Layout>.size
        let getEnumTag = unsafeBitCast(
            tablePointer.load(fromByteOffset: enumWitnessesOffset, as: UnsafeRawPointer.self),
            to: GetEnumTagWitness.self
        )
        let destructiveInjectEnumTag = unsafeBitCast(
            tablePointer.load(fromByteOffset: enumWitnessesOffset + 2 * MemoryLayout<UnsafeRawPointer>.size, as: UnsafeRawPointer.self),
            to: DestructiveInjectEnumTagWitness.self
        )
        #endif

        let zeroBaseline = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: alignment)
        let onesBaseline = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: alignment)
        defer {
            zeroBaseline.deallocate()
            onesBaseline.deallocate()
        }

        var casePatterns: [CasePattern] = []
        casePatterns.reserveCapacity(caseCount)

        for caseIndex in 0 ..< caseCount {
            zeroBaseline.initializeMemory(as: UInt8.self, repeating: 0x00, count: size)
            onesBaseline.initializeMemory(as: UInt8.self, repeating: 0xFF, count: size)

            destructiveInjectEnumTag(zeroBaseline, UInt32(caseIndex), enumMetadataPointer)
            destructiveInjectEnumTag(onesBaseline, UInt32(caseIndex), enumMetadataPointer)

            // An empty case's discriminator is fully determined by what the
            // witness just wrote, so the tag must read back exactly.
            if caseIndex >= payloadCaseCount {
                guard getEnumTag(zeroBaseline, enumMetadataPointer) == UInt32(caseIndex) else { return nil }
            }

            var fixedBytes: [Int: UInt8] = [:]
            for byteOffset in 0 ..< size {
                let zeroBaselineByte = zeroBaseline.load(fromByteOffset: byteOffset, as: UInt8.self)
                let onesBaselineByte = onesBaseline.load(fromByteOffset: byteOffset, as: UInt8.self)
                if zeroBaselineByte == onesBaselineByte {
                    fixedBytes[byteOffset] = zeroBaselineByte
                }
            }
            casePatterns.append(CasePattern(caseIndex: caseIndex, fixedBytes: fixedBytes))
        }

        return casePatterns
    }
}
