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

    @Test("move aliases preserve registers and complete constants", arguments: [
        (UInt32(0xAA01_03E0), ThunkOperation.moveRegister(destination: .init(number: 0), source: .init(number: 1))), // mov x0, x1
        (UInt32(0x9100_03E0), .moveRegister(destination: .init(number: 0), source: .stackPointer)), // mov x0, sp
        (UInt32(0xD2A2_4680), .moveImmediate(destination: .init(number: 0), value: 0x1234_0000)), // mov x0, #0x12340000
        (UInt32(0x9280_0000), .moveImmediate(destination: .init(number: 0), value: -1)), // mov x0, #-1
    ])
    func moveAliasesPreserveTheirValues(encoding: UInt32, expectedOperation: ThunkOperation) throws {
        #expect(try decoded([encoding]) == [expectedOperation])
    }

    @Test("immediate arithmetic preserves comparisons and shifts", arguments: [
        (UInt32(0xF100_001F), ThunkOperation.compareImmediate(register: .init(number: 0), value: 0)), // cmp x0, #0
        (UInt32(0xF140_041F), .compareImmediate(register: .init(number: 0), value: 4096)), // cmp x0, #1, lsl #12
        (UInt32(0x9144_0020), .addImmediate(destination: .init(number: 0), source: .init(number: 1), addend: 0x10_0000)), // add x0, x1, #0x100, lsl #12
        (UInt32(0xD140_0420), .addImmediate(destination: .init(number: 0), source: .init(number: 1), addend: -4096)), // sub x0, x1, #1, lsl #12
    ])
    func immediateArithmeticPreservesItsValues(encoding: UInt32, expectedOperation: ThunkOperation) throws {
        #expect(try decoded([encoding]) == [expectedOperation])
    }

    @Test("memory access offsets remain distinct from write-back", arguments: [
        (UInt32(0xF940_0000), ThunkOperation.loadFromMemory(destination: .init(number: 0), base: .init(number: 0), displacement: 0)), // ldr x0, [x0]
        (UInt32(0xA941_7BFD), .loadPairFromMemory(first: .init(number: 29), second: .init(number: 30), base: .stackPointer, displacement: 16, adjustsBase: false)), // ldp x29, x30, [sp, #16]
        (UInt32(0xA9BF_7BFD), .storePairToMemory(first: .init(number: 29), second: .init(number: 30), base: .stackPointer, displacement: -16, adjustsBase: true)), // stp x29, x30, [sp, #-16]!
        (UInt32(0xA8C1_7BFD), .loadPairFromMemory(first: .init(number: 29), second: .init(number: 30), base: .stackPointer, displacement: 0, adjustsBase: true)), // ldp x29, x30, [sp], #16
    ])
    func memoryAccessesPreserveTheirOffsets(encoding: UInt32, expectedOperation: ThunkOperation) throws {
        #expect(try decoded([encoding]) == [expectedOperation])
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
            0xAA09_0100, // orr x0, x8, x9 -- not a move alias
        ])
        #expect(operations == [
            .unmodelled(writtenRegisters: [ThunkRegister(number: 0)]),
            .unmodelled(writtenRegisters: [ThunkRegister(number: 0)]),
            .unmodelled(writtenRegisters: [ThunkRegister(number: 0)]),
        ])
    }

    @Test("single-register write-back accesses remain unmodelled", arguments: [
        (UInt32(0xF81F_0FE0), Set([ThunkRegister.stackPointer])), // str x0, [sp, #-16]!
        (UInt32(0xF841_07E0), Set([ThunkRegister.stackPointer, .init(number: 0)])), // ldr x0, [sp], #16
    ])
    func singleRegisterWriteBackRemainsUnmodelled(encoding: UInt32, expectedRegisters: Set<ThunkRegister>) throws {
        let operations = try decoded([encoding])
        guard case .unmodelled(let writtenRegisters) = try #require(operations.first) else {
            Issue.record("A write-back access must not be treated as an ordinary load or store")
            return
        }
        #expect(Set(writtenRegisters) == expectedRegisters)
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
