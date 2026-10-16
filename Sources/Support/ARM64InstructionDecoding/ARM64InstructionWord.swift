/// Readers for the few A64 encodings this package decodes by hand.
///
/// Each reader answers `nil` for a word that is not the instruction it reads.
/// Addresses may be in any address space — unslid or runtime — as long as
/// the instruction's own address is given in the same one: `adrp`, `adr` and
/// the immediate branches are relative to it.
///
/// Hand decoding exists for throughput: scanning every function of a dyld
/// shared cache through Capstone costs about 950 CPU seconds, through these
/// readers about 20 (measured on macOS 27.2, evolution proposal
/// `cross-reference-analysis`).
package enum ARM64InstructionWord {
    /// The register number that names the zero register or the stack
    /// pointer, depending on the instruction.
    package static let zeroOrStackPointerRegister = 31

    @inlinable
    package static func signExtended(_ value: UInt64, bitWidth: Int) -> Int64 {
        let shift = UInt64(64 - bitWidth)
        return Int64(bitPattern: value << shift) >> Int64(shift)
    }

    @inlinable
    package static func adding(_ displacement: Int64, to address: UInt64) -> UInt64 {
        UInt64(bitPattern: Int64(bitPattern: address) &+ displacement)
    }

    /// `bl label`: the call's target.
    @inlinable
    package static func callTarget(_ word: UInt32, at address: UInt64) -> UInt64? {
        guard word & 0xFC00_0000 == 0x9400_0000 else { return nil }
        return adding(signExtended(UInt64(word & 0x03FF_FFFF) << 2, bitWidth: 28), to: address)
    }

    /// `b label`, the unconditional form: the branch's target.
    @inlinable
    package static func branchTarget(_ word: UInt32, at address: UInt64) -> UInt64? {
        guard word & 0xFC00_0000 == 0x1400_0000 else { return nil }
        return adding(signExtended(UInt64(word & 0x03FF_FFFF) << 2, bitWidth: 28), to: address)
    }

    /// `b.cond`, `cbz` / `cbnz` and `tbz` / `tbnz`: the target taken when the
    /// condition holds.
    @inlinable
    package static func conditionalBranchTarget(_ word: UInt32, at address: UInt64) -> UInt64? {
        if word & 0xFF00_0010 == 0x5400_0000 || word & 0x7E00_0000 == 0x3400_0000 {
            return adding(signExtended(UInt64((word >> 5) & 0x7FFFF) << 2, bitWidth: 21), to: address)
        }
        if word & 0x7E00_0000 == 0x3600_0000 {
            return adding(signExtended(UInt64((word >> 5) & 0x3FFF) << 2, bitWidth: 16), to: address)
        }
        return nil
    }

    /// `adrp xd, label` and `adr xd, label`: the register written and the
    /// address it receives.
    @inlinable
    package static func addressMaterialization(_ word: UInt32, at address: UInt64) -> (destination: Int, address: UInt64)? {
        let destination = Int(word & 0x1F)
        let immediate = (UInt64((word >> 5) & 0x7FFFF) << 2) | UInt64((word >> 29) & 0x3)
        if word & 0x9F00_0000 == 0x9000_0000 {
            return (destination, adding(signExtended(immediate << 12, bitWidth: 33), to: address & ~UInt64(0xFFF)))
        }
        if word & 0x9F00_0000 == 0x1000_0000 {
            return (destination, adding(signExtended(immediate, bitWidth: 21), to: address))
        }
        return nil
    }

    /// `add xd, xn, #imm{, lsl #12}` and `sub xd, xn, #imm{, lsl #12}` on
    /// 64-bit registers, the subtraction as a negative addend.
    @inlinable
    package static func addImmediate(_ word: UInt32) -> (destination: Int, source: Int, addend: Int64)? {
        let opcode = word & 0xFF80_0000
        guard opcode == 0x9100_0000 || opcode == 0xD100_0000 else { return nil }
        let shift: UInt64 = (word >> 22) & 1 == 1 ? 12 : 0
        let magnitude = Int64(bitPattern: UInt64((word >> 10) & 0xFFF) << shift)
        return (Int(word & 0x1F), Int((word >> 5) & 0x1F), opcode == 0x9100_0000 ? magnitude : -magnitude)
    }

    /// A 64-bit load from a base register plus a constant displacement:
    /// `ldr xt, [xn, #imm]`, `ldur xt, [xn, #simm]`, the pre-indexed
    /// `ldr xt, [xn, #simm]!`, and `ldraa` / `ldrab`.
    @inlinable
    package static func load(_ word: UInt32) -> (destination: Int, base: Int, displacement: Int64, writesBack: Bool)? {
        let destination = Int(word & 0x1F)
        let base = Int((word >> 5) & 0x1F)
        if word & 0xFFC0_0000 == 0xF940_0000 {
            return (destination, base, Int64((word >> 10) & 0xFFF) << 3, false)
        }
        if word & 0xFFE0_0C00 == 0xF840_0000 {
            return (destination, base, signExtended(UInt64((word >> 12) & 0x1FF), bitWidth: 9), false)
        }
        if word & 0xFFE0_0C00 == 0xF840_0C00 {
            return (destination, base, signExtended(UInt64((word >> 12) & 0x1FF), bitWidth: 9), true)
        }
        if word & 0xFF20_0400 == 0xF820_0400 {
            let immediate = (UInt64((word >> 22) & 1) << 9) | UInt64((word >> 12) & 0x1FF)
            return (destination, base, signExtended(immediate, bitWidth: 10) << 3, (word >> 11) & 1 == 1)
        }
        return nil
    }

    /// `ret`, `retaa`, `retab`.
    @inlinable
    package static func isReturn(_ word: UInt32) -> Bool {
        word & 0xFFFF_FC1F == 0xD65F_0000 || word == 0xD65F_0BFF || word == 0xD65F_0FFF
    }

    /// A branch or a call through a register.
    package struct RegisterBranch: Equatable, Sendable {
        /// The register holding the destination.
        package let target: Int
        /// The register holding the pointer-authentication modifier
        /// (`blraa` / `blrab` / `braa` / `brab`); `nil` for the forms without one.
        package let modifier: Int?
        package let isCall: Bool
        package let isAuthenticated: Bool

        @inlinable
        package init(target: Int, modifier: Int?, isCall: Bool, isAuthenticated: Bool) {
            self.target = target
            self.modifier = modifier
            self.isCall = isCall
            self.isAuthenticated = isAuthenticated
        }
    }

    /// `blr`, `br`, and their authenticating forms `blraa` / `blrab` /
    /// `blraaz` / `blrabz` / `braa` / `brab` / `braaz` / `brabz`.
    @inlinable
    package static func registerBranch(_ word: UInt32) -> RegisterBranch? {
        let target = Int((word >> 5) & 0x1F)
        switch word & 0xFFFF_FC1F {
        case 0xD63F_0000:
            return RegisterBranch(target: target, modifier: nil, isCall: true, isAuthenticated: false)
        case 0xD61F_0000:
            return RegisterBranch(target: target, modifier: nil, isCall: false, isAuthenticated: false)
        case 0xD63F_081F, 0xD63F_0C1F:
            return RegisterBranch(target: target, modifier: nil, isCall: true, isAuthenticated: true)
        case 0xD61F_081F, 0xD61F_0C1F:
            return RegisterBranch(target: target, modifier: nil, isCall: false, isAuthenticated: true)
        default:
            break
        }
        switch word & 0xFFFF_F800 {
        case 0xD73F_0800:
            return RegisterBranch(target: target, modifier: Int(word & 0x1F), isCall: true, isAuthenticated: true)
        case 0xD71F_0800:
            return RegisterBranch(target: target, modifier: Int(word & 0x1F), isCall: false, isAuthenticated: true)
        default:
            return nil
        }
    }

    /// `movz xd, #imm{, lsl #shift}` and `movk xd, #imm{, lsl #shift}` on
    /// 64-bit registers. `keepsOtherBits` is true for `movk`.
    @inlinable
    package static func moveWide(_ word: UInt32) -> (destination: Int, immediate: UInt16, shift: Int, keepsOtherBits: Bool)? {
        let opcode = word & 0xFF80_0000
        guard opcode == 0xD280_0000 || opcode == 0xF280_0000 else { return nil }
        return (Int(word & 0x1F), UInt16(truncatingIfNeeded: word >> 5), Int((word >> 21) & 0x3) * 16, opcode == 0xF280_0000)
    }

    /// `mov xd, xm`, which is `orr xd, xzr, xm`.
    @inlinable
    package static func moveRegister(_ word: UInt32) -> (destination: Int, source: Int)? {
        guard word & 0xFFE0_FFE0 == 0xAA00_03E0 else { return nil }
        return (Int(word & 0x1F), Int((word >> 16) & 0x1F))
    }

    /// `nop`.
    package static let noOperation: UInt32 = 0xD503_201F
}
