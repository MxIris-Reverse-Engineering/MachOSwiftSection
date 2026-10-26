import Foundation

/// Encoders for the A64 instructions the decoding tests build by hand,
/// written straight from the architecture's encoding tables so the readers
/// are checked against an independent spelling of each format.
enum InstructionEncoding {
    static func adrp(_ destination: Int, at address: UInt64, page target: UInt64) -> UInt32 {
        let pageDelta = (Int64(bitPattern: target & ~UInt64(0xFFF)) - Int64(bitPattern: address & ~UInt64(0xFFF))) >> 12
        let immediate = UInt32(truncatingIfNeeded: pageDelta) & 0x1F_FFFF
        return 0x9000_0000 | ((immediate & 0x3) << 29) | ((immediate >> 2) << 5) | UInt32(destination)
    }

    static func add(_ destination: Int, _ source: Int, immediate: UInt32) -> UInt32 {
        0x9100_0000 | (immediate << 10) | (UInt32(source) << 5) | UInt32(destination)
    }

    static func sub(_ destination: Int, _ source: Int, immediate: UInt32) -> UInt32 {
        0xD100_0000 | (immediate << 10) | (UInt32(source) << 5) | UInt32(destination)
    }

    static func loadUnsignedOffset(_ destination: Int, base: Int, byteOffset: UInt32) -> UInt32 {
        0xF940_0000 | ((byteOffset / 8) << 10) | (UInt32(base) << 5) | UInt32(destination)
    }

    static func loadPreIndexed(_ destination: Int, base: Int, byteOffset: Int32) -> UInt32 {
        0xF840_0C00 | ((UInt32(bitPattern: byteOffset) & 0x1FF) << 12) | (UInt32(base) << 5) | UInt32(destination)
    }

    static func branch(at address: UInt64, to target: UInt64) -> UInt32 {
        0x1400_0000 | (UInt32(truncatingIfNeeded: Int64(bitPattern: target &- address) >> 2) & 0x03FF_FFFF)
    }

    static func branchWithLink(at address: UInt64, to target: UInt64) -> UInt32 {
        0x9400_0000 | (UInt32(truncatingIfNeeded: Int64(bitPattern: target &- address) >> 2) & 0x03FF_FFFF)
    }

    static func branchToRegister(_ register: Int) -> UInt32 {
        0xD61F_0000 | (UInt32(register) << 5)
    }

    static func branchToRegisterAuthenticated(_ register: Int, modifier: Int) -> UInt32 {
        0xD71F_0800 | (UInt32(register) << 5) | UInt32(modifier)
    }

    static func callRegisterAuthenticated(_ register: Int, modifier: Int) -> UInt32 {
        0xD73F_0800 | (UInt32(register) << 5) | UInt32(modifier)
    }

    static func moveKeep(_ destination: Int, immediate: UInt16, shift: Int) -> UInt32 {
        0xF280_0000 | (UInt32(shift / 16) << 21) | (UInt32(immediate) << 5) | UInt32(destination)
    }

    static func moveZero(_ destination: Int, immediate: UInt16) -> UInt32 {
        0xD280_0000 | (UInt32(immediate) << 5) | UInt32(destination)
    }

    static func moveRegister(_ destination: Int, _ source: Int) -> UInt32 {
        0xAA00_03E0 | (UInt32(source) << 16) | UInt32(destination)
    }

    static func compareBranchZero(_ register: Int, at address: UInt64, to target: UInt64) -> UInt32 {
        0xB400_0000 | ((UInt32(truncatingIfNeeded: Int64(bitPattern: target &- address) >> 2) & 0x7FFFF) << 5) | UInt32(register)
    }

    static func bytes(of words: [UInt32]) -> Data {
        var data = Data()
        for word in words {
            withUnsafeBytes(of: word.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }
}
