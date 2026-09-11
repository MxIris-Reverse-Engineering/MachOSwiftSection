#if THUNK_ANALYSIS

import Foundation

/// Tracks, instruction by instruction, which registers hold a value the
/// analysis can name.
///
/// A deliberately minimal abstract interpretation: the only thing a thunk does
/// that this module needs to follow is *materializing an address* — an `adrp`
/// establishing a page base, an `add` completing it — and *loading a small
/// integer*, which is how the availability check's four arguments arrive. A
/// value it cannot derive is simply absent; nothing is guessed.
public struct ThunkRegisterTracker: Sendable {
    /// What a register is known to hold.
    ///
    /// Addresses and immediates are kept apart on purpose: `add x8, x8, #2064`
    /// completes an address when `x8` holds one and computes an integer when
    /// it holds an integer, and conflating the two would let a loop counter be
    /// read as a candidate address.
    public enum Value: Sendable, Hashable {
        case address(UInt64)
        case immediate(Int64)
    }

    private var valuesByRegister: [ThunkRegister: Value] = [:]

    public init() {}

    public func value(of register: ThunkRegister) -> Value? {
        valuesByRegister[register]
    }

    public func address(of register: ThunkRegister) -> UInt64? {
        guard case .address(let address) = valuesByRegister[register] else { return nil }
        return address
    }

    public func immediate(of register: ThunkRegister) -> Int64? {
        guard case .immediate(let value) = valuesByRegister[register] else { return nil }
        return value
    }

    public mutating func apply(_ operation: ThunkOperation) {
        switch operation {
        case .materializePageAddress(let destination, let pageBaseAddress):
            assign(.address(pageBaseAddress), to: destination)
        case .addImmediate(let destination, let source, let addend):
            switch valuesByRegister[source] {
            case .address(let base):
                assign(.address(base &+ UInt64(bitPattern: addend)), to: destination)
            case .immediate(let base):
                assign(.immediate(base &+ addend), to: destination)
            case nil:
                forget(destination)
            }
        case .moveImmediate(let destination, let value):
            assign(.immediate(value), to: destination)
        case .moveRegister(let destination, let source):
            if let value = valuesByRegister[source] {
                assign(value, to: destination)
            } else {
                forget(destination)
            }
        case .loadFromMemory(let destination, _, _):
            // The value is in the binary, not in the instruction. Reading it
            // is a caller's job — one that has the Mach-O — so the register
            // becomes unknown rather than wrong.
            forget(destination)
        case .call:
            // AAPCS64: x0–x17 are caller-saved, so after a call only x19–x28
            // (and the frame/link registers) still hold what they held. The
            // availability check's own result lands in x0 and is read by the
            // `cmp` / `cbz` that follows, which the analysis handles by
            // position rather than by tracked value.
            for registerNumber in 0 ... 17 {
                forget(ThunkRegister(number: registerNumber))
            }
        case .conditionalSelect(let destination, _, _, _):
            // Which of the two the destination takes is exactly the question
            // the analysis is asking; it must not be answered here.
            forget(destination)
        case .branch, .branchIfZero, .branchIfNotZero, .compareImmediate, .returnFromFunction, .unmodelled:
            break
        }
    }

    private mutating func assign(_ value: Value, to register: ThunkRegister) {
        guard !register.isZeroRegister else { return }
        valuesByRegister[register] = value
    }

    private mutating func forget(_ register: ThunkRegister) {
        valuesByRegister.removeValue(forKey: register)
    }
}

#endif
