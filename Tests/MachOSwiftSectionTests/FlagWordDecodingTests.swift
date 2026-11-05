import Foundation
import Testing
@testable import MachOSwiftSection

/// Three flag-word accessors that read the wrong bits until the flag words of
/// the ABI layer were declared with `@BitField` (proposal
/// `abi-flag-words-bit-field`). Each of them stopped the process: two masked a
/// bit without shifting it down, and one converted the whole word.
///
/// The values come from live metadata where the runtime has it, so that a
/// test reads what a binary actually holds rather than a number written to
/// match the accessor.
@Suite
struct FlagWordDecodingTests {
    /// `Any` is not class-constrained, which the runtime records by SETTING
    /// bit 31 — the case every non-class existential is in. Masked but not
    /// shifted, the bit became `UInt8(0x8000_0000)` and trapped.
    @Test func existentialThatIsNotClassConstrainedReadsAny() throws {
        let metadata = try ExistentialTypeMetadata.resolve(
            at: unsafeBitCast(Any.self, to: UnsafeRawPointer.self),
            in: InProcessContext.shared
        )
        #expect(metadata.layout.flags.classConstraint == .any)
        #expect(!metadata.isClassBounded)

        let classBoundMetadata = try ExistentialTypeMetadata.resolve(
            at: unsafeBitCast(AnyObject.self, to: UnsafeRawPointer.self),
            in: InProcessContext.shared
        )
        #expect(classBoundMetadata.layout.flags.classConstraint == .class)
    }

    /// Bit 1 of a protocol descriptor's flags is set when the protocol is not
    /// class-constrained. Masked but not shifted, it read as the raw value 2,
    /// which `ProtocolClassConstraint` does not have, and the force-unwrap
    /// trapped.
    @Test func protocolDescriptorWhoseClassConstraintBitIsSetReadsAny() {
        #expect(ProtocolDescriptorFlags(rawValue: 0b10).classConstraint == .any)
        #expect(ProtocolDescriptorFlags(rawValue: 0b00).classConstraint == .class)
    }

    /// The calling convention is bits 16..<24. The accessor converted the
    /// whole word instead: a function type whose word is 255 or less read its
    /// parameter count as the convention, and any other trapped — every
    /// escaping function type has bit 26 set.
    @Test func functionTypeReadsItsConventionFromItsOwnBits() throws {
        let swiftFunction = try FunctionTypeMetadata.resolve(
            at: unsafeBitCast(((Int) -> Void).self, to: UnsafeRawPointer.self),
            in: InProcessContext.shared
        )
        #expect(swiftFunction.layout.flags.convention == .swift)

        let cFunction = try FunctionTypeMetadata.resolve(
            at: unsafeBitCast((@convention(c) (Int32) -> Int32).self, to: UnsafeRawPointer.self),
            in: InProcessContext.shared
        )
        #expect(cFunction.layout.flags.convention == .cFunctionPointer)

        let block = try FunctionTypeMetadata.resolve(
            at: unsafeBitCast((@convention(block) () -> Void).self, to: UnsafeRawPointer.self),
            in: InProcessContext.shared
        )
        #expect(block.layout.flags.convention == .block)
    }
}
