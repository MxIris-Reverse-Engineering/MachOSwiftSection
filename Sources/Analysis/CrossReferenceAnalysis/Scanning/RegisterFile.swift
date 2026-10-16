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

    private let states: UnsafeMutablePointer<UInt8>
    private let values: UnsafeMutablePointer<UInt64>
    private let loadDisplacements: UnsafeMutablePointer<Int64>
    private let constants: UnsafeMutablePointer<UInt16>
    /// Registers holding a value loaded from memory, by bit.
    private var loadedMask: UInt32 = 0
    /// Registers holding a pointer-authentication constant, by bit.
    private var constantMask: UInt32 = 0
    /// Of those, the ones whose constant was blended into an address.
    private var blendedMask: UInt32 = 0

    /// `x0`–`x18` and the link register: what a call may change.
    private static let callerSavedMask: UInt32 = 0x0007_FFFF | (1 << 30)

    init() {
        states = .allocate(capacity: Self.registerCount)
        values = .allocate(capacity: Self.registerCount)
        loadDisplacements = .allocate(capacity: Self.registerCount)
        constants = .allocate(capacity: Self.registerCount)
        states.initialize(repeating: 0, count: Self.registerCount)
        values.initialize(repeating: 0, count: Self.registerCount)
        loadDisplacements.initialize(repeating: 0, count: Self.registerCount)
        constants.initialize(repeating: 0, count: Self.registerCount)
    }

    deinit {
        states.deallocate()
        values.deallocate()
        loadDisplacements.deallocate()
        constants.deallocate()
    }

    func reset() {
        states.update(repeating: 0, count: Self.registerCount)
        loadedMask = 0
        constantMask = 0
        blendedMask = 0
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
        if source != 31, states[source] == State.address.rawValue {
            overwrite(destination, state: .address, value: UInt64(bitPattern: Int64(bitPattern: values[source]) &+ addend))
        } else {
            overwrite(destination, state: .unknown, value: 0)
        }
    }

    func load(into destination: Int, base: Int, displacement: Int64, writesBack: Bool) {
        let slotIsKnown = base != 31 && states[base] == State.address.rawValue
        let slotAddress = UInt64(bitPattern: Int64(bitPattern: values[base]) &+ displacement)
        if writesBack, base != 31 { overwrite(base, state: .unknown, value: 0) }
        guard destination != 31 else { return }
        overwrite(destination, state: slotIsKnown ? .loadedFromSlot : .unknown, value: slotIsKnown ? slotAddress : 0)
        loadedMask |= 1 << UInt32(destination)
        loadDisplacements[destination] = displacement
    }

    func copy(_ source: Int, to destination: Int) {
        guard destination != 31 else { return }
        guard source != 31 else {
            overwrite(destination, state: .unknown, value: 0)
            return
        }
        states[destination] = states[source]
        values[destination] = values[source]
        loadDisplacements[destination] = loadDisplacements[source]
        constants[destination] = constants[source]
        copyBit(from: source, to: destination, in: &loadedMask)
        copyBit(from: source, to: destination, in: &constantMask)
        copyBit(from: source, to: destination, in: &blendedMask)
    }

    /// `movz` / `movk`: a pointer-authentication constant is `movk xN, #imm,
    /// lsl #48` blended into an address, or `mov x17, #imm` on its own.
    func moveWide(into destination: Int, immediate: UInt16, shift: Int, keepsOtherBits: Bool) {
        guard destination != 31 else { return }
        let isConstant = keepsOtherBits ? shift == 48 : shift == 0
        overwrite(destination, state: .unknown, value: 0)
        guard isConstant else { return }
        constants[destination] = immediate
        constantMask |= 1 << UInt32(destination)
        if keepsOtherBits { blendedMask |= 1 << UInt32(destination) }
    }

    func clobberCallerSavedRegisters() {
        for register in 0 ... 18 { states[register] = State.unknown.rawValue }
        states[30] = State.unknown.rawValue
        loadedMask &= ~Self.callerSavedMask
        constantMask &= ~Self.callerSavedMask
        blendedMask &= ~Self.callerSavedMask
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

    // MARK: - Reads

    func wasLoadedFromMemory(_ register: Int) -> Bool {
        register != 31 && loadedMask & (1 << UInt32(register)) != 0
    }

    func loadDisplacement(of register: Int) -> Int64? {
        wasLoadedFromMemory(register) ? loadDisplacements[register] : nil
    }

    func constant(of register: Int) -> (value: UInt16, isBlended: Bool)? {
        guard register != 31, constantMask & (1 << UInt32(register)) != 0 else { return nil }
        return (constants[register], blendedMask & (1 << UInt32(register)) != 0)
    }

    func holdsMethodReceiver(_ register: Int) -> Bool {
        register != 31 && states[register] == State.methodReceiver.rawValue
    }

    /// The slot a register's value was loaded from, when that is known.
    func slotAddress(of register: Int) -> UInt64? {
        guard register != 31, states[register] == State.loadedFromSlot.rawValue else { return nil }
        return values[register]
    }

    // MARK: - Helpers

    private func overwrite(_ register: Int, state: State, value: UInt64) {
        guard register != 31 else { return }
        states[register] = state.rawValue
        values[register] = value
        let bit: UInt32 = 1 << UInt32(register)
        loadedMask &= ~bit
        constantMask &= ~bit
        blendedMask &= ~bit
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
