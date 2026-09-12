import Foundation

/// One general-purpose ARM64 register, with the 32-bit and 64-bit spellings of
/// the same register folded together.
///
/// A thunk sets up the availability check's arguments as `w0`–`w3` and reads
/// the result back as `w0`, while the candidate addresses it selects between
/// live in `x8` / `x9`. Those are the same four registers seen at two widths,
/// so an analysis that kept `w0` and `x0` apart would lose the connection
/// between "the call returned into `w0`" and "the `cmp` reads `x0`".
public struct ThunkRegister: Sendable, Hashable, CustomStringConvertible {
    /// `0`–`30` for `x0`–`x30`; ``zeroRegister``'s `31` for `xzr` / `wzr`.
    public let number: Int

    public init(number: Int) {
        self.number = number
    }

    /// `xzr` / `wzr`, which reads as zero and discards what is written to it.
    public static let zeroRegister = ThunkRegister(number: 31)

    /// `sp` / `wsp`. Numbered past the general-purpose file because it is
    /// not one of them: encoding 31 means the zero register in most
    /// instructions and the stack pointer only in the few that take it as a
    /// base, and the two must never be confused — a load "from `xzr`" is
    /// meaningless while a load from `sp` is how a type-construction thunk
    /// reads back an argument buffer it just built.
    public static let stackPointer = ThunkRegister(number: 32)

    public var isZeroRegister: Bool { number == ThunkRegister.zeroRegister.number }

    public var isStackPointer: Bool { number == ThunkRegister.stackPointer.number }

    public var description: String {
        if isZeroRegister { return "zr" }
        if isStackPointer { return "sp" }
        return "x\(number)"
    }
}

/// The condition an ARM64 conditional instruction tests.
///
/// Only the two a thunk actually uses are modelled. Everything else decodes as
/// ``unsupported`` rather than to a nearest neighbour: picking the wrong branch
/// of a version check would report a type that the target OS never produces,
/// and an honest "cannot read this shape" degrades to the placeholder instead.
public enum ThunkCondition: Sendable, Hashable {
    case equal
    case notEqual
    case unsupported
}

/// The ARM64 subset a Swift metadata accessor thunk is built from.
///
/// A deliberately small vocabulary rather than a general instruction model:
/// what the analysis needs is the flow of *known addresses* through registers
/// and the one branch that selects between candidates. Instructions outside
/// that vocabulary decode as ``unmodelled`` and are stepped over, which is
/// correct for the prologue (`pacibsp`, `stp`, `nop`) and is why the analysis
/// does not have to be taught every instruction a compiler might emit.
///
/// Keeping this independent of Capstone is the point of the file split: the
/// register tracker and the shape recognizer above it are testable from
/// synthesized instruction sequences, with no bytes and no disassembler, and a
/// second decoder (a different engine, or x86_64) would replace exactly one
/// file.
public enum ThunkOperation: Sendable, Hashable {
    /// `adrp <destination>, #<pageBaseAddress>` — the 4 KiB-aligned page base.
    /// Capstone resolves this against the instruction's own address, so the
    /// value is already absolute and the caller does not redo the PC-relative
    /// arithmetic (getting that wrong by using a *file offset* as the program
    /// counter is what produced fabricated addresses during the proposal's
    /// research).
    case materializePageAddress(destination: ThunkRegister, pageBaseAddress: UInt64)

    /// `add <destination>, <source>, #<addend>` — the second half of the
    /// `adrp` / `add` pair that materializes a full address.
    case addImmediate(destination: ThunkRegister, source: ThunkRegister, addend: Int64)

    /// `mov <destination>, #<value>`.
    case moveImmediate(destination: ThunkRegister, value: Int64)

    /// `mov <destination>, <source>`.
    case moveRegister(destination: ThunkRegister, source: ThunkRegister)

    /// `ldr <destination>, [<base>, #<displacement>]` — the value is in the
    /// binary, not in the instruction, so the tracker marks the destination
    /// unknown and leaves the read to a caller that has the Mach-O.
    case loadFromMemory(destination: ThunkRegister, base: ThunkRegister, displacement: Int64)

    /// `ldp <first>, <second>, [<base>, #<displacement>]` — two consecutive
    /// words. `adjustsBase` is the write-back form (`[sp], #32`,
    /// `[sp, #-32]!`), which also moves the base register: a stack model
    /// keyed on that register's old value has nothing valid left after it.
    case loadPairFromMemory(first: ThunkRegister, second: ThunkRegister, base: ThunkRegister, displacement: Int64, adjustsBase: Bool)

    /// `str <source>, [<base>, #<displacement>]`.
    case storeToMemory(source: ThunkRegister, base: ThunkRegister, displacement: Int64)

    /// `stp <first>, <second>, [<base>, #<displacement>]`; `adjustsBase` as
    /// for ``loadPairFromMemory(first:second:base:displacement:adjustsBase:)``.
    case storePairToMemory(first: ThunkRegister, second: ThunkRegister, base: ThunkRegister, displacement: Int64, adjustsBase: Bool)

    /// `bl #<target>`.
    case call(target: UInt64)

    /// `b #<target>`.
    case branch(target: UInt64)

    /// `br <register>` / `braa <register>, <modifier>` — an indirect jump.
    /// Control does not come back, so it ends a function the way a tail
    /// call does; where it goes is not tracked.
    case indirectBranch(register: ThunkRegister)

    /// `cbz <register>, #<target>`.
    case branchIfZero(register: ThunkRegister, target: UInt64)

    /// `cbnz <register>, #<target>`.
    case branchIfNotZero(register: ThunkRegister, target: UInt64)

    /// `cmp <register>, #<value>`.
    case compareImmediate(register: ThunkRegister, value: Int64)

    /// `csel <destination>, <whenConditionHolds>, <otherwise>, <condition>` —
    /// the destination takes `whenConditionHolds` when the condition is true.
    case conditionalSelect(
        destination: ThunkRegister,
        whenConditionHolds: ThunkRegister,
        otherwise: ThunkRegister,
        condition: ThunkCondition
    )

    /// `ret`.
    case returnFromFunction

    /// Anything else. Stepped over, not treated as an error.
    case unmodelled
}

/// One decoded instruction: its address, its modelled operation, and the
/// mnemonic it decoded from.
///
/// The mnemonic is carried even for ``ThunkOperation/unmodelled`` operations
/// so a diagnostic can name what stopped the analysis, rather than reporting
/// only that something did.
public struct ThunkInstruction: Sendable, Hashable {
    public let address: UInt64
    public let operation: ThunkOperation
    public let mnemonic: String

    public init(address: UInt64, operation: ThunkOperation, mnemonic: String) {
        self.address = address
        self.operation = operation
        self.mnemonic = mnemonic
    }
}
