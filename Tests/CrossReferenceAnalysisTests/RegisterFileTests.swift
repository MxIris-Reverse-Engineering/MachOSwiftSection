import Foundation
import Testing
import Capstone
@testable import CrossReferenceAnalysis

/// What `RegisterFile.forgetRegistersWritten(by:)` forgets for the
/// instructions the scanner does not model: every general-purpose register
/// the instruction writes — a write-back base, an atomic's old value, a
/// pair's second register, a vector element moved out — and, for a plain
/// load or store, nothing else.
@Suite
struct RegisterFileTests {
    /// An instruction and the general-purpose registers it writes, spelled
    /// from the architecture's encoding tables. The encodings are the
    /// assembler's.
    struct Instruction: CustomTestStringConvertible, Sendable {
        let word: UInt32
        let assembly: String
        let written: Set<Int>

        var testDescription: String { assembly }
    }

    static let writingInstructions: [Instruction] = [
        // Single registers that write back their base.
        .init(word: 0xF841_0509, assembly: "ldr x9, [x8], #16", written: [8, 9]),
        .init(word: 0xB840_4D09, assembly: "ldr w9, [x8, #4]!", written: [8, 9]),
        .init(word: 0xF801_0509, assembly: "str x9, [x8], #16", written: [8]),
        .init(word: 0x3800_1D09, assembly: "strb w9, [x8, #1]!", written: [8]),
        .init(word: 0x3CC1_0500, assembly: "ldr q0, [x8], #16", written: [8]),
        .init(word: 0xFC1F_8D00, assembly: "str d0, [x8, #-8]!", written: [8]),
        .init(word: 0xB880_4509, assembly: "ldrsw x9, [x8], #4", written: [8, 9]),
        .init(word: 0xF820_1D09, assembly: "ldraa x9, [x8, #8]!", written: [8, 9]),
        // Atomics return the old value, whatever their ordering.
        .init(word: 0xF821_0002, assembly: "ldadd x1, x2, [x0]", written: [2]),
        .init(word: 0xF821_8002, assembly: "swp x1, x2, [x0]", written: [2]),
        .init(word: 0xF8E1_0002, assembly: "ldaddal x1, x2, [x0]", written: [2]),
        .init(word: 0xF8BF_C002, assembly: "ldapr x2, [x0]", written: [2]),
        // Pairs that write back their base.
        .init(word: 0xA8C1_0500, assembly: "ldp x0, x1, [x8], #16", written: [0, 1, 8]),
        .init(word: 0xA9BF_0500, assembly: "stp x0, x1, [x8, #-16]!", written: [8]),
        .init(word: 0xACC1_0500, assembly: "ldp q0, q1, [x8], #32", written: [8]),
        .init(word: 0x6D81_0500, assembly: "stp d0, d1, [x8, #16]!", written: [8]),
        .init(word: 0x68C1_0500, assembly: "ldpsw x0, x1, [x8], #8", written: [0, 1, 8]),
        // Exclusives, ordered accesses, compare and swap.
        .init(word: 0xC87F_0500, assembly: "ldxp x0, x1, [x8]", written: [0, 1]),
        .init(word: 0xC822_0500, assembly: "stxp w2, x0, x1, [x8]", written: [2]),
        .init(word: 0x4822_7D04, assembly: "casp x2, x3, x4, x5, [x8]", written: [2, 3]),
        .init(word: 0xC8A2_7D04, assembly: "cas x2, x4, [x8]", written: [2]),
        .init(word: 0xC85F_FD00, assembly: "ldaxr x0, [x8]", written: [0]),
        .init(word: 0xC802_FD00, assembly: "stlxr w2, x0, [x8]", written: [2]),
        .init(word: 0xC8DF_FD00, assembly: "ldar x0, [x8]", written: [0]),
        // Structure loads and stores that write back their base.
        .init(word: 0x4CDF_7100, assembly: "ld1 {v0.16b}, [x8], #16", written: [8]),
        .init(word: 0x4C89_A100, assembly: "st1 {v0.16b, v1.16b}, [x8], x9", written: [8]),
        .init(word: 0x0DDF_9100, assembly: "ld1 {v0.s}[1], [x8], #4", written: [8]),
        .init(word: 0x4DDF_C900, assembly: "ld1r {v0.4s}, [x8], #4", written: [8]),
        // Literal, load-acquire unscaled, and the memory copy and set
        // instructions, which move all three of their registers.
        .init(word: 0x5800_0000, assembly: "ldr x0, #0", written: [0]),
        .init(word: 0xD940_8100, assembly: "ldapur x0, [x8, #8]", written: [0]),
        .init(word: 0xD9C0_0900, assembly: "ldapr x0, [x8], #8", written: [0, 8]),
        .init(word: 0x1901_0440, assembly: "cpyfp [x0]!, [x1]!, x2!", written: [0, 1, 2]),
        .init(word: 0x19C2_0420, assembly: "setp [x0]!, x1!, x2", written: [0, 1]),
        // Moves out of a vector or floating-point register.
        .init(word: 0x0E0C_3C20, assembly: "umov w0, v1.s[1]", written: [0]),
        .init(word: 0x4E08_3C20, assembly: "mov x0, v1.d[0]", written: [0]),
        .init(word: 0x4E01_2C20, assembly: "smov x0, v1.b[0]", written: [0]),
        .init(word: 0x9E66_0020, assembly: "fmov x0, d1", written: [0]),
        .init(word: 0x9E58_F420, assembly: "fcvtzs x0, d1, #3", written: [0]),
        .init(word: 0x1E38_0020, assembly: "fcvtzs w0, s1", written: [0]),
        // System register reads.
        .init(word: 0xD53B_D060, assembly: "mrs x0, tpidrro_el0", written: [0]),
        .init(word: 0xD528_7500, assembly: "sysl x0, #0, c7, c5, #0", written: [0]),
        // SVE and SME instructions that yield a general register.
        .init(word: 0x04E0_E3E0, assembly: "cntd x0", written: [0]),
        .init(word: 0x0421_5040, assembly: "addvl x0, x1, #2", written: [0]),
        .init(word: 0x04BF_5020, assembly: "rdvl x0, #1", written: [0]),
        .init(word: 0x04BF_5820, assembly: "rdsvl x0, #1", written: [0]),
        // A system call returns in `x0` and `x1`.
        .init(word: 0xD400_1001, assembly: "svc #0x80", written: [0, 1]),
        // Everything else that computes into a register.
        .init(word: 0xDAC1_43F0, assembly: "xpaci x16", written: [16]),
        .init(word: 0x1100_0508, assembly: "add w8, w8, #1", written: [8]),
    ]

    /// Plain loads and stores, the bulk of the code: only a load's
    /// destination is forgotten, never the base or a stored register.
    static let plainAccesses: [Instruction] = [
        .init(word: 0xF940_0509, assembly: "ldr x9, [x8, #8]", written: [9]),
        .init(word: 0xB940_0509, assembly: "ldr w9, [x8, #4]", written: [9]),
        .init(word: 0xF86A_6909, assembly: "ldr x9, [x8, x10]", written: [9]),
        .init(word: 0x386A_6909, assembly: "ldrb w9, [x8, x10]", written: [9]),
        .init(word: 0xF900_0509, assembly: "str x9, [x8, #8]", written: []),
        .init(word: 0x3D80_0500, assembly: "str q0, [x8, #16]", written: []),
        .init(word: 0xA941_0500, assembly: "ldp x0, x1, [x8, #16]", written: [0, 1]),
        .init(word: 0xA901_0500, assembly: "stp x0, x1, [x8, #16]", written: []),
        .init(word: 0x4C40_7100, assembly: "ld1 {v0.16b}, [x8]", written: []),
        .init(word: 0xC8DF_FD00, assembly: "ldar x0, [x8]", written: [0]),
    ]

    /// The registers the file no longer knows after `word`, when it knew
    /// every one of them before.
    private func forgottenRegisters(by word: UInt32) -> Set<Int> {
        let registers = RegisterFile()
        for register in 0 ..< 31 {
            registers.setAddress(0x1_0000 &+ UInt64(register) &* 8, of: register)
        }
        registers.forgetRegistersWritten(by: word)
        return Set((0 ..< 31).filter { registers.builtAddress(of: $0) == nil })
    }

    @Test(arguments: writingInstructions)
    func forgetsEveryRegisterAnInstructionWrites(_ instruction: Instruction) {
        let forgotten = forgottenRegisters(by: instruction.word)
        #expect(instruction.written.isSubset(of: forgotten), "keeps \(instruction.written.subtracting(forgotten).sorted())")
    }

    @Test(arguments: plainAccesses)
    func aPlainAccessForgetsOnlyWhatItLoads(_ instruction: Instruction) {
        #expect(forgottenRegisters(by: instruction.word) == instruction.written)
    }

    /// Signing or authenticating a pointer in place leaves the register
    /// meaning what it meant; stripping one is not followed.
    @Test func pointerAuthenticationKeepsTheRegister() {
        #expect(forgottenRegisters(by: 0xDAC1_0230).isEmpty) // pacia x16, x17
        #expect(forgottenRegisters(by: 0xDAC1_1A30).isEmpty) // autda x16, x17
    }

    /// Registers Capstone lists as written that the architecture does not
    /// write: it counts the base of a compare and swap among them, which
    /// `cas` and `casp` only read.
    private static let capstoneOverstatements: [UInt32: Set<Int>] = [
        0x4822_7D04: [8], // casp x2, x3, x4, x5, [x8]
        0xC8A2_7D04: [8], // cas x2, x4, [x8]
    ]

    /// Capstone, a decoder written independently of the tables above,
    /// names no general-purpose register they leave out.
    @Test func capstoneNamesNoOtherWrittenRegister() throws {
        let disassembler = try Disassembler<AArch64>()
        for instruction in Self.writingInstructions + Self.plainAccesses {
            let decoded = disassembler.decode(InstructionEncoding.bytes(of: [instruction.word]), address: 0x1_0000)
            let decodedInstruction = try #require(decoded.first, "Capstone cannot decode \(instruction.assembly)")
            let written = Set((decodedInstruction.registersWritten + decodedInstruction.implicitRegistersWritten).compactMap(Self.generalPurposeRegisterNumber))
                .subtracting(Self.capstoneOverstatements[instruction.word] ?? [])
            #expect(written.isSubset(of: instruction.written), "\(instruction.assembly): Capstone also writes \(written.subtracting(instruction.written).sorted())")
        }
    }

    /// `x0`–`x30` by number, the 32-bit names folded onto them; `nil` for
    /// the zero register, the stack pointer and everything that is not a
    /// general-purpose register.
    private static func generalPurposeRegisterNumber(_ register: AArch64Reg) -> Int? {
        switch register {
        case .fp: return 29
        case .lr: return 30
        default: break
        }
        let rawValue = Int(register.rawValue)
        if rawValue >= Int(AArch64Reg.w0.rawValue), rawValue <= Int(AArch64Reg.w30.rawValue) {
            return rawValue - Int(AArch64Reg.w0.rawValue)
        }
        if rawValue >= Int(AArch64Reg.x0.rawValue), rawValue <= Int(AArch64Reg.x28.rawValue) {
            return rawValue - Int(AArch64Reg.x0.rawValue)
        }
        return nil
    }
}
