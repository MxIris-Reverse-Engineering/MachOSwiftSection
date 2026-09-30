import Foundation
import Testing
@testable import MachOSwiftSection

/// An accessor that answers an Optional must read its field at the field's
/// own width. Asked for the Optional directly, the generic `readElement`
/// is instantiated at `Optional<Field>` and reads the Optional's in-memory
/// shape — the field plus one tag byte — so a non-zero byte after the field
/// turns the answer into `nil`. The runtime leaves padding like that
/// unwritten, which is what made the live-metadata assertions of
/// `FunctionTypeMetadataTests` pass alone and fail in a full run.
///
/// Each record here is laid out by hand with `0x01` — the Optional's "no
/// value" tag — right after the field, so the outcome does not depend on
/// what an allocator happens to leave behind.
@Suite
struct OptionalAccessorReadTests {
    /// Runs `body` over zeroed, pointer-aligned memory of `byteCount` bytes.
    private func withRecord<Outcome>(byteCount: Int, _ body: (UnsafeMutableRawPointer) throws -> Outcome) rethrows -> Outcome {
        let record = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 8)
        defer { record.deallocate() }
        record.initializeMemory(as: UInt8.self, repeating: 0, count: byteCount)
        return try body(record)
    }

    /// `() throws(E) -> ()` without a global actor: the extended flag word
    /// directly follows the three-word header, and the four bytes after it
    /// are the padding before the thrown error type.
    @Test func extendedFlagsIgnoreTheByteAfterTheFlagWord() throws {
        let extendedFlags = try withRecord(byteCount: 40) { record in
            record.storeBytes(of: 0x302, toByteOffset: 0, as: UInt64.self)  // kind: function
            record.storeBytes(of: 0x8000_0000, toByteOffset: 8, as: UInt64.self)  // has extended flags, no parameters
            record.storeBytes(of: 0x0000_0001, toByteOffset: 24, as: UInt32.self)  // typed throws
            record.storeBytes(of: 0x01, toByteOffset: 28, as: UInt8.self)
            let metadata = try FunctionTypeMetadata.resolve(at: UnsafeRawPointer(record), in: InProcessContext.shared)
            return try metadata.extendedFlags(in: InProcessContext.shared)
        }
        #expect(extendedFlags?.rawValue == 0x0000_0001)
    }

    /// A multi-payload enum whose metadata keeps its payload size in the
    /// word after the descriptor pointer — the slot the descriptor's
    /// `payloadSizeOffset` names for a generic multi-payload enum.
    @Test func payloadSizeIgnoresTheByteAfterTheSizeWord() throws {
        let payloadSize = try withRecord(byteCount: 28) { descriptorRecord in
            // Two payload cases; the payload size is two words into the metadata.
            descriptorRecord.storeBytes(of: 2 << 24 | 2, toByteOffset: 20, as: UInt32.self)
            let descriptor = try EnumDescriptor.resolve(at: UnsafeRawPointer(descriptorRecord), in: InProcessContext.shared)
            return try withRecord(byteCount: 32) { metadataRecord in
                metadataRecord.storeBytes(of: 0x201, toByteOffset: 0, as: UInt64.self)  // kind: enum
                metadataRecord.storeBytes(of: 0x10, toByteOffset: 16, as: UInt64.self)
                metadataRecord.storeBytes(of: 0x01, toByteOffset: 24, as: UInt8.self)
                let metadata = try EnumMetadata.resolve(at: UnsafeRawPointer(metadataRecord), in: InProcessContext.shared)
                return try metadata.payloadSize(descriptor: descriptor, in: InProcessContext.shared)
            }
        }
        #expect(payloadSize == 0x10)
    }
}
