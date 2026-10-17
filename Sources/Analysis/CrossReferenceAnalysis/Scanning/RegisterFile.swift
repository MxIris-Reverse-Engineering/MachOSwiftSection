import Foundation
import ARM64InstructionDecoding

/// What the scanner knows about each general-purpose register — only what
/// is certain.
///
/// Register 31 is the zero register or the stack pointer, neither of which
/// is tracked: writing it changes nothing and reading it yields nothing.
final class RegisterFile {
    private enum State: UInt8 {
        case unknown = 0
        /// Holds an address `adrp` / `adr` / `add` built.
        case address
        /// Holds what was loaded from the slot at a known address.
        case loadedFromSlot
        /// Holds the receiver an Objective-C method arrived with.
        case methodReceiver
    }

    private static let registerCount = 32

    /// `x0`–`x18` and the link register: what a call may change.
    private static let callerSavedMask: UInt32 = 0x0007_FFFF | (1 << 30)

    /// Everything the file knows at one instruction. A value of fixed size,
    /// so a forward branch carries it to its target as a plain copy — the
    /// scan takes one at every forward branch, and arrays would allocate.
    struct Snapshot {
        fileprivate var states = SIMD32<UInt8>(repeating: 0)
        fileprivate var values = SIMD32<UInt64>(repeating: 0)
        fileprivate var loadDisplacements = SIMD32<Int64>(repeating: 0)
        fileprivate var constants = SIMD32<UInt16>(repeating: 0)
        /// Registers holding a value loaded from memory, by bit.
        fileprivate var loadedMask: UInt32 = 0
        /// Registers holding a pointer-authentication constant, by bit.
        fileprivate var constantMask: UInt32 = 0
        /// Of those, the ones whose constant was blended into an address.
        fileprivate var blendedMask: UInt32 = 0

        /// Keeps only what `other` agrees on: two paths that reach one
        /// instruction leave a register known there only when both put the
        /// same thing in it.
        mutating func meet(_ other: Snapshot) {
            for register in 0 ..< RegisterFile.registerCount where !agrees(with: other, on: register) {
                let bit: UInt32 = 1 << UInt32(register)
                states[register] = State.unknown.rawValue
                loadedMask &= ~bit
                constantMask &= ~bit
                blendedMask &= ~bit
            }
        }

        private func agrees(with other: Snapshot, on register: Int) -> Bool {
            let bit: UInt32 = 1 << UInt32(register)
            return states[register] == other.states[register]
                && (states[register] == State.unknown.rawValue || values[register] == other.values[register])
                && loadedMask & bit == other.loadedMask & bit
                && (loadedMask & bit == 0 || loadDisplacements[register] == other.loadDisplacements[register])
                && constantMask & bit == other.constantMask & bit
                && blendedMask & bit == other.blendedMask & bit
                && (constantMask & bit == 0 || constants[register] == other.constants[register])
        }
    }

    private var contents = Snapshot()

    func reset() {
        contents.states = SIMD32(repeating: 0)
        contents.loadedMask = 0
        contents.constantMask = 0
        contents.blendedMask = 0
    }

    // MARK: - Writes

    func setMethodReceiver(_ register: Int) {
        overwrite(register, state: .methodReceiver, value: 0)
    }

    func setAddress(_ address: UInt64, of register: Int) {
        overwrite(register, state: .address, value: address)
    }

    func add(_ addend: Int64, to source: Int, into destination: Int) {
        guard destination != 31 else { return }
        if source != 31, contents.states[source] == State.address.rawValue {
            overwrite(destination, state: .address, value: UInt64(bitPattern: Int64(bitPattern: contents.values[source]) &+ addend))
        } else {
            overwrite(destination, state: .unknown, value: 0)
        }
    }

    func load(into destination: Int, base: Int, displacement: Int64, writesBack: Bool) {
        let slotIsKnown = base != 31 && contents.states[base] == State.address.rawValue
        let slotAddress = UInt64(bitPattern: Int64(bitPattern: contents.values[base & 31]) &+ displacement)
        if writesBack, base != 31 { overwrite(base, state: .unknown, value: 0) }
        guard destination != 31 else { return }
        overwrite(destination, state: slotIsKnown ? .loadedFromSlot : .unknown, value: slotIsKnown ? slotAddress : 0)
        contents.loadedMask |= 1 << UInt32(destination)
        contents.loadDisplacements[destination] = displacement
    }

    func copy(_ source: Int, to destination: Int) {
        guard destination != 31 else { return }
        guard source != 31 else {
            overwrite(destination, state: .unknown, value: 0)
            return
        }
        contents.states[destination] = contents.states[source]
        contents.values[destination] = contents.values[source]
        contents.loadDisplacements[destination] = contents.loadDisplacements[source]
        contents.constants[destination] = contents.constants[source]
        copyBit(from: source, to: destination, in: &contents.loadedMask)
        copyBit(from: source, to: destination, in: &contents.constantMask)
        copyBit(from: source, to: destination, in: &contents.blendedMask)
    }

    /// `movz` / `movk`: a pointer-authentication constant is `movk xN, #imm,
    /// lsl #48` blended into an address, or `mov x17, #imm` on its own.
    func moveWide(into destination: Int, immediate: UInt16, shift: Int, keepsOtherBits: Bool) {
        guard destination != 31 else { return }
        let isConstant = keepsOtherBits ? shift == 48 : shift == 0
        overwrite(destination, state: .unknown, value: 0)
        guard isConstant else { return }
        contents.constants[destination] = immediate
        contents.constantMask |= 1 << UInt32(destination)
        if keepsOtherBits { contents.blendedMask |= 1 << UInt32(destination) }
    }

    func clobberCallerSavedRegisters() {
        for register in 0 ... 18 { contents.states[register] = State.unknown.rawValue }
        contents.states[30] = State.unknown.rawValue
        contents.loadedMask &= ~Self.callerSavedMask
        contents.constantMask &= ~Self.callerSavedMask
        contents.blendedMask &= ~Self.callerSavedMask
    }

    /// What a call to a function that returns its argument leaves: the
    /// caller-saved registers forgotten except `kept`, which still holds what
    /// it was handed.
    func clobberCallerSavedRegisters(keeping kept: Int) {
        let keptContents = contents
        clobberCallerSavedRegisters()
        let bit: UInt32 = 1 << UInt32(kept)
        contents.states[kept] = keptContents.states[kept]
        contents.values[kept] = keptContents.values[kept]
        contents.loadDisplacements[kept] = keptContents.loadDisplacements[kept]
        contents.constants[kept] = keptContents.constants[kept]
        contents.loadedMask = (contents.loadedMask & ~bit) | (keptContents.loadedMask & bit)
        contents.constantMask = (contents.constantMask & ~bit) | (keptContents.constantMask & bit)
        contents.blendedMask = (contents.blendedMask & ~bit) | (keptContents.blendedMask & bit)
    }

    /// Forgets the registers an instruction the scanner does not model
    /// writes. Erring toward forgetting only loses facts; never forgetting a
    /// write would keep a stale one.
    func forgetRegistersWritten(by word: UInt32) {
        forget(mask: Self.registersWritten(by: word))
    }

    /// The general-purpose registers `word` writes, by bit: every one it may
    /// write, never one it does not — except a pointer signed or
    /// authenticated in place, which keeps what it means. A call writes the
    /// caller-saved registers.
    static func registersWritten(by word: UInt32) -> UInt32 {
        let destination = word & 0x1F
        let base = (word >> 5) & 0x1F
        // Calls: `bl`, and `blr` and its authenticating forms.
        if word & 0xFC00_0000 == 0x9400_0000 || ARM64InstructionWord.registerBranch(word)?.isCall == true {
            return callerSavedMask
        }
        // Loads and stores. A write-back moves the base whether the
        // register transferred is a general one or a vector one.
        if word & 0x0A00_0000 == 0x0800_0000 {
            return registersWritten(byLoadOrStore: word, destination: destination, base: base)
        }
        // Data processing, immediate or register.
        if word & 0x1C00_0000 == 0x1000_0000 || word & 0x0E00_0000 == 0x0A00_0000 {
            // PAC and AUT sign or authenticate the register in place, which
            // keeps what it holds; XPAC, which strips it, is forgotten.
            if word & 0xFFFF_C000 == 0xDAC1_0000 { return 0 }
            return bit(destination)
        }
        // Floating point to a general register: moves and conversions, to an
        // integer or to fixed point.
        if word & 0x5F20_FC00 == 0x1E20_0000 || word & 0x5F20_0000 == 0x1E00_0000 {
            return bit(destination)
        }
        // `umov` / `smov`: a vector element to a general register.
        if word & 0xBFE0_EC00 == 0x0E00_2C00 {
            return bit(destination)
        }
        // SVE and SME: the few that yield a general register (`cntd`,
        // `addvl`, `rdsvl` …) write it here.
        if word & 0x1E00_0000 == 0x0400_0000 || word & 0x9E00_0000 == 0x8000_0000 {
            return bit(destination)
        }
        // System register reads, and `sysl`.
        if word & 0xFFE0_0000 == 0xD520_0000 {
            return bit(destination)
        }
        // `svc`: a system call returns in `x0` and `x1`.
        if word & 0xFFE0_001F == 0xD400_0001 {
            return 0b11
        }
        return 0
    }

    private static func registersWritten(byLoadOrStore word: UInt32, destination: UInt32, base: UInt32) -> UInt32 {
        let isVector = word & 0x0400_0000 != 0
        let secondRegister = (word >> 10) & 0x1F
        let statusRegister = (word >> 16) & 0x1F
        var written: UInt32 = 0
        switch (word >> 28) & 0x3 {
        case 0b11:
            // Single register. Bit 24 clear and bit 21 clear: bit 10 marks
            // the pre- and post-indexed forms. Bit 21 set: bits 11–10 are 00
            // for an atomic, x1 for a pointer-authenticated load, whose bit
            // 11 writes back.
            if word & 0x0100_0000 == 0, word & 0x0020_0000 == 0 {
                if word & 0x0400 != 0 { written |= bit(base) }
            } else if word & 0x0100_0000 == 0, word & 0x0400 != 0 {
                if word & 0x0800 != 0 { written |= bit(base) }
                return written | bit(destination)
            } else if word & 0x0100_0000 == 0, word & 0x0C00 == 0 {
                // An atomic returns the old value whatever its ordering,
                // which takes the bits a load's opc would.
                return isVector ? written : written | bit(destination)
            }
            // opc 00 is a store; everything else loads.
            if !isVector, (word >> 22) & 0x3 != 0 { written |= bit(destination) }
        case 0b10:
            // Register pair: bit 23 marks the pre- and post-indexed forms,
            // bit 22 a load.
            if word & 0x0080_0000 != 0 { written |= bit(base) }
            if !isVector, word & 0x0040_0000 != 0 { written |= bit(destination) | bit(secondRegister) }
        case 0b01:
            if word & 0x0100_0000 == 0 {
                // Load literal.
                if !isVector { written |= bit(destination) }
            } else if word & 0x0020_0C00 == 0 {
                // Load-acquire and store-release, unscaled: opc 00 stores.
                if !isVector, (word >> 22) & 0x3 != 0 { written |= bit(destination) }
            } else {
                // Memory copy and set, which move all three of their
                // registers along, memory tags, and the write-back forms of
                // load-acquire and store-release.
                written |= bit(destination) | bit(base) | bit(statusRegister)
            }
        default:
            if isVector {
                // Structure loads and stores: bit 23 marks the
                // post-indexed forms.
                if word & 0x0080_0000 != 0 { written |= bit(base) }
                return written
            }
            // Exclusives, ordered accesses, compare and swap: the register
            // transferred, the status or compared one, and with bit 23 clear
            // and bit 21 set a pair — a pair's second register, or for
            // `casp` (bit 31 clear) the register after the compared one.
            written |= bit(destination) | bit(statusRegister)
            if word & 0x00A0_0000 == 0x0020_0000 {
                written |= bit(secondRegister)
                if word & 0x8000_0000 == 0, statusRegister != 31 { written |= bit(statusRegister + 1) }
            }
        }
        return written
    }

    /// Register `register`'s bit; none for register 31, which is not tracked.
    private static func bit(_ register: UInt32) -> UInt32 {
        register == 31 ? 0 : 1 << register
    }

    // MARK: - Branches

    func snapshot() -> Snapshot {
        contents
    }

    /// Becomes `snapshot`: the instruction is reached only by the branches
    /// it was taken at.
    func restore(_ snapshot: Snapshot) {
        contents = snapshot
    }

    /// Keeps only what `snapshot` agrees on: the instruction is reached both
    /// by falling through and by the branches `snapshot` was taken at.
    func meet(_ snapshot: Snapshot) {
        contents.meet(snapshot)
    }

    // MARK: - Reads

    func wasLoadedFromMemory(_ register: Int) -> Bool {
        register != 31 && contents.loadedMask & (1 << UInt32(register)) != 0
    }

    func loadDisplacement(of register: Int) -> Int64? {
        wasLoadedFromMemory(register) ? contents.loadDisplacements[register] : nil
    }

    func constant(of register: Int) -> (value: UInt16, isBlended: Bool)? {
        guard register != 31, contents.constantMask & (1 << UInt32(register)) != 0 else { return nil }
        return (contents.constants[register], contents.blendedMask & (1 << UInt32(register)) != 0)
    }

    func holdsMethodReceiver(_ register: Int) -> Bool {
        register != 31 && contents.states[register] == State.methodReceiver.rawValue
    }

    /// The address a register holds, when `adrp` / `adr` / `add` built it.
    func builtAddress(of register: Int) -> UInt64? {
        guard register != 31, contents.states[register] == State.address.rawValue else { return nil }
        return contents.values[register]
    }

    /// The slot a register's value was loaded from, when that is known.
    func slotAddress(of register: Int) -> UInt64? {
        guard register != 31, contents.states[register] == State.loadedFromSlot.rawValue else { return nil }
        return contents.values[register]
    }

    // MARK: - Helpers

    private func overwrite(_ register: Int, state: State, value: UInt64) {
        guard register != 31 else { return }
        contents.states[register] = state.rawValue
        contents.values[register] = value
        let bit: UInt32 = 1 << UInt32(register)
        contents.loadedMask &= ~bit
        contents.constantMask &= ~bit
        contents.blendedMask &= ~bit
    }

    private func forget(_ register: Int) {
        overwrite(register, state: .unknown, value: 0)
    }

    /// Forgets every register `mask` has a bit for.
    func forget(mask: UInt32) {
        var remaining = mask & 0x7FFF_FFFF
        while remaining != 0 {
            let register = remaining.trailingZeroBitCount
            forget(register)
            remaining &= remaining - 1
        }
    }

    private func copyBit(from source: Int, to destination: Int, in mask: inout UInt32) {
        if mask & (1 << UInt32(source)) != 0 {
            mask |= 1 << UInt32(destination)
        } else {
            mask &= ~(1 << UInt32(destination))
        }
    }
}
