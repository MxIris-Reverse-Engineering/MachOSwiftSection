import Foundation
import Testing
@testable import SwiftThunkAnalysis

/// What the decoder makes of instructions outside the modelled vocabulary,
/// from real encodings (`clang -c` of the mnemonics in the comments).
///
/// Two things must hold for every future compiler: a conditional branch
/// the analysis cannot read keeps its target and is not stepped over, and
/// an instruction it cannot read still says which registers it wrote.
@Suite
struct CapstoneThunkDecoderTests {
    private func decoded(_ words: [UInt32], at startAddress: UInt64 = 0x1000) throws -> [ThunkOperation] {
        var data = Data()
        for word in words {
            withUnsafeBytes(of: word.littleEndian) { data.append(contentsOf: $0) }
        }
        return try CapstoneThunkDecoder.decode(machineCode: data, startAddress: startAddress).map(\.operation)
    }

    @Test func aConditionalBranchKeepsItsTarget() throws {
        let operations = try decoded([
            0x5400_0041, // b.ne #8
            0x3600_0040, // tbz w0, #0, #8
            0xB7FF_FFC1, // tbnz x1, #63, #-8
        ])
        #expect(operations == [
            .conditionalBranchNotModelled(target: 0x1008),
            .conditionalBranchNotModelled(target: 0x100C),
            .conditionalBranchNotModelled(target: 0x1000),
        ])
    }

    /// Signing, authenticating or stripping a pointer in a register leaves
    /// the register holding the same pointer for the analysis.
    @Test func pointerAuthenticationKeepsTheRegister() throws {
        let operations = try decoded([
            0xDAC1_0230, // pacia x16, x17
            0xDAC1_1A30, // autda x16, x17
            0xDAC1_43F0, // xpaci x16
            0xDAC1_23F0, // paciza x16
        ])
        #expect(operations == Array(repeating: .signOrAuthenticatePointer(register: ThunkRegister(number: 16)), count: 4))
    }

    @Test func aTrapIsATrap() throws {
        #expect(try decoded([0xD43E_8E20]) == [.trap]) // brk #0xf471
    }

    @Test func anUnmodelledInstructionNamesTheRegistersItWrites() throws {
        let operations = try decoded([
            0xF869_6900, // ldr x0, [x8, x9]
            0x8B09_0D00, // add x0, x8, x9, lsl #3
        ])
        #expect(operations == [
            .unmodelled(writtenRegisters: [ThunkRegister(number: 0)]),
            .unmodelled(writtenRegisters: [ThunkRegister(number: 0)]),
        ])
    }

    /// A `b.<cond>` over a `ret` extends the function past that `ret`, as a
    /// `cbz` does: the arm after it is still this function.
    @Test func aConditionalBranchExtendsTheFunctionBoundary() throws {
        var data = Data()
        for word: UInt32 in [
            0x5400_0061, // b.ne #12
            0xD65F_03C0, // ret
            0xD503_201F, // nop
            0xD65F_03C0, // ret
            0xD503_201F, // nop  — past the function
        ] {
            withUnsafeBytes(of: word.littleEndian) { data.append(contentsOf: $0) }
        }
        let instructions = try CapstoneThunkDecoder.decodeFunction(machineCode: data, startAddress: 0x2000)
        #expect(instructions.count == 4)
        #expect(instructions.last?.operation == .returnFromFunction)
    }
}
