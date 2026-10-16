import Foundation

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

    /// Forgets the registers an instruction the scanner does not model
    /// writes. Erring toward forgetting only loses facts; never forgetting a
    /// write would keep a stale one.
    func forgetRegistersWritten(by word: UInt32) {
        let destination = Int(word & 0x1F)
        // Loads and stores.
        if word & 0x0A00_0000 == 0x0800_0000 {
            // A SIMD or floating-point register is no general-purpose one.
            guard word & 0x0400_0000 == 0 else { return }
            if word & 0x3800_0000 == 0x2800_0000 {
                // Register pair: bit 22 tells a load from a store.
                if word & 0x0040_0000 != 0 {
                    forget(destination)
                    forget(Int((word >> 10) & 0x1F))
                }
            } else if word & 0x3800_0000 == 0x3800_0000 {
                // Single register: opc 00 is a store, everything else loads.
                if (word >> 22) & 0x3 != 0 { forget(destination) }
            } else if word & 0x3B00_0000 == 0x1800_0000 {
                // Load literal.
                forget(destination)
            } else {
                // Exclusives and atomics write their transfer or status register.
                forget(destination)
                forget(Int((word >> 16) & 0x1F))
            }
            return
        }
        // Data processing, immediate or register.
        if word & 0x1C00_0000 == 0x1000_0000 || word & 0x0E00_0000 == 0x0A00_0000 {
            // PAC, AUT and XPAC sign or strip the register in place.
            if word & 0xFFFF_C000 == 0xDAC1_0000 { return }
            forget(destination)
            return
        }
        // Moves and conversions from floating point to a general register.
        if word & 0x5F20_FC00 == 0x1E20_0000 {
            forget(destination)
            return
        }
        // System register reads.
        if word & 0xFFF0_0000 == 0xD530_0000 {
            forget(destination)
        }
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

    private func copyBit(from source: Int, to destination: Int, in mask: inout UInt32) {
        if mask & (1 << UInt32(source)) != 0 {
            mask |= 1 << UInt32(destination)
        } else {
            mask &= ~(1 << UInt32(destination))
        }
    }
}
