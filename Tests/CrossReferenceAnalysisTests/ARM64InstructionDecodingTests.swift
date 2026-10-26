import Foundation
import Testing
import Capstone
import ARM64InstructionDecoding

@Suite
struct ARM64InstructionWordTests {
    private let address: UInt64 = 0x1_9810_09C0

    @Test func callAndBranchTargetsInBothDirections() {
        for target in [address + 0x8, address - 0x1_0000, address + 0x7FF_FFFC, address - 0x800_0000] {
            #expect(ARM64InstructionWord.callTarget(InstructionEncoding.branchWithLink(at: address, to: target), at: address) == target)
            #expect(ARM64InstructionWord.branchTarget(InstructionEncoding.branch(at: address, to: target), at: address) == target)
        }
        // Neither reader claims the other's instruction.
        #expect(ARM64InstructionWord.callTarget(InstructionEncoding.branch(at: address, to: address + 8), at: address) == nil)
        #expect(ARM64InstructionWord.branchTarget(InstructionEncoding.branchWithLink(at: address, to: address + 8), at: address) == nil)
    }

    @Test func pageAddressAcrossFourGigabytes() throws {
        let page: UInt64 = 0x1_E20F_A000
        let word = InstructionEncoding.adrp(17, at: address, page: page)
        let materialization = try #require(ARM64InstructionWord.addressMaterialization(word, at: address))
        #expect(materialization.destination == 17)
        #expect(materialization.address == page)
        let backward = InstructionEncoding.adrp(1, at: address, page: 0x1_2000_0000)
        #expect(ARM64InstructionWord.addressMaterialization(backward, at: address)?.address == 0x1_2000_0000)
    }

    @Test func immediateArithmeticAndLoads() throws {
        let add = try #require(ARM64InstructionWord.addImmediate(InstructionEncoding.add(17, 17, immediate: 0xD00)))
        #expect(add.destination == 17 && add.source == 17 && add.addend == 0xD00)
        let sub = try #require(ARM64InstructionWord.addImmediate(InstructionEncoding.sub(3, 4, immediate: 0x10)))
        #expect(sub.destination == 3 && sub.source == 4 && sub.addend == -0x10)

        let load = try #require(ARM64InstructionWord.load(InstructionEncoding.loadUnsignedOffset(16, base: 16, byteOffset: 0x7E0)))
        #expect(load.destination == 16 && load.base == 16 && load.displacement == 0x7E0 && !load.writesBack)
        let preIndexed = try #require(ARM64InstructionWord.load(InstructionEncoding.loadPreIndexed(9, base: 8, byteOffset: 0x30)))
        #expect(preIndexed.destination == 9 && preIndexed.base == 8 && preIndexed.displacement == 0x30 && preIndexed.writesBack)
        let negative = try #require(ARM64InstructionWord.load(InstructionEncoding.loadPreIndexed(9, base: 8, byteOffset: -0x20)))
        #expect(negative.displacement == -0x20)
    }

    @Test func registerBranchesAndConstants() throws {
        let tailCall = try #require(ARM64InstructionWord.registerBranch(InstructionEncoding.branchToRegisterAuthenticated(16, modifier: 17)))
        #expect(tailCall == .init(target: 16, modifier: 17, isCall: false, isAuthenticated: true))
        let call = try #require(ARM64InstructionWord.registerBranch(InstructionEncoding.callRegisterAuthenticated(9, modifier: 16)))
        #expect(call == .init(target: 9, modifier: 16, isCall: true, isAuthenticated: true))
        let plain = try #require(ARM64InstructionWord.registerBranch(InstructionEncoding.branchToRegister(16)))
        #expect(plain == .init(target: 16, modifier: nil, isCall: false, isAuthenticated: false))

        let blend = try #require(ARM64InstructionWord.moveWide(InstructionEncoding.moveKeep(16, immediate: 0x18B8, shift: 48)))
        #expect(blend.destination == 16 && blend.immediate == 0x18B8 && blend.shift == 48 && blend.keepsOtherBits)
        let alone = try #require(ARM64InstructionWord.moveWide(InstructionEncoding.moveZero(17, immediate: 0x489B)))
        #expect(alone.destination == 17 && alone.immediate == 0x489B && alone.shift == 0 && !alone.keepsOtherBits)
        let copy = try #require(ARM64InstructionWord.moveRegister(InstructionEncoding.moveRegister(19, 0)))
        #expect(copy.destination == 19 && copy.source == 0)

        let conditional = InstructionEncoding.compareBranchZero(0, at: address, to: address + 0x40)
        #expect(ARM64InstructionWord.conditionalBranchTarget(conditional, at: address) == address + 0x40)
    }

    /// Capstone disassembles every hand-built word as the instruction the
    /// readers took it for, so a wrong encoder cannot hide a wrong reader.
    @Test func capstoneAgreesWithTheEncoders() throws {
        let words: [UInt32] = [
            InstructionEncoding.adrp(17, at: address, page: 0x1_E20F_A000),
            InstructionEncoding.add(17, 17, immediate: 0xD00),
            InstructionEncoding.loadUnsignedOffset(16, base: 17, byteOffset: 0),
            InstructionEncoding.branchToRegisterAuthenticated(16, modifier: 17),
            InstructionEncoding.loadPreIndexed(9, base: 8, byteOffset: 0x30),
            InstructionEncoding.moveKeep(16, immediate: 0x18B8, shift: 48),
            InstructionEncoding.callRegisterAuthenticated(9, modifier: 16),
            InstructionEncoding.branchWithLink(at: address + 28, to: address - 0x1_0000),
        ]
        let instructions = try Disassembler<AArch64>().decode(InstructionEncoding.bytes(of: words), address: address)
        #expect(instructions.map(\.mnemonic) == ["adrp", "add", "ldr", "braa", "ldr", "movk", "blraa", "bl"])
        #expect(instructions[0].operands[1].immediateValue == 0x1_E20F_A000)
        #expect(instructions[7].operands[0].immediateValue == Int64(address - 0x1_0000))
    }
}

@Suite
struct ARM64TrampolineTests {
    private let address: UInt64 = 0x1_9810_09C0

    @Test func authenticatedSlotStub() {
        // What macOS 27 shares between all images of its cache, and an
        // arm64e image's own __auth_stubs entry.
        let words = [
            InstructionEncoding.adrp(17, at: address, page: 0x1_E20F_A000),
            InstructionEncoding.add(17, 17, immediate: 0xD00),
            InstructionEncoding.loadUnsignedOffset(16, base: 17, byteOffset: 0),
            InstructionEncoding.branchToRegisterAuthenticated(16, modifier: 17),
        ]
        #expect(ARM64Trampoline(words: words, at: address) == .slotLoad(slotAddress: 0x1_E20F_AD00))
    }

    @Test func standaloneSlotStub() {
        let words = [
            InstructionEncoding.adrp(16, at: address, page: 0x1_0000_8000),
            InstructionEncoding.loadUnsignedOffset(16, base: 16, byteOffset: 0x18),
            InstructionEncoding.branchToRegister(16),
            0xD420_0020,
        ]
        #expect(ARM64Trampoline(words: words, at: address) == .slotLoad(slotAddress: 0x1_0000_8018))
    }

    @Test func stubIsland() {
        let words = [
            InstructionEncoding.adrp(16, at: address, page: 0x1_8A4E_B000),
            InstructionEncoding.add(16, 16, immediate: 0x8D8),
            InstructionEncoding.branchToRegister(16),
            ARM64InstructionWord.noOperation,
        ]
        #expect(ARM64Trampoline(words: words, at: address) == .computed(target: 0x1_8A4E_B8D8))
    }

    @Test func sharedSelectorStub() {
        // The macOS 27.2 stub for `_makeKeyRegardlessOfVisibility`, which the
        // cache keeps within a `b`'s reach of the `objc_msgSend` copy.
        let stubAddress: UInt64 = 0x1_9001_E750
        let messageSend: UInt64 = 0x1_9000_0800
        let words = [
            InstructionEncoding.adrp(1, at: stubAddress, page: 0x1_F57F_7000),
            InstructionEncoding.add(1, 1, immediate: 0xF98),
            InstructionEncoding.branch(at: stubAddress + 8, to: messageSend),
            0xD420_0020,
        ]
        #expect(ARM64Trampoline(words: words, at: stubAddress) == .selectorStub(selectorAddress: 0x1_F57F_7F98, messageSendAddress: messageSend))
    }

    @Test func ordinaryCodeIsNoTrampoline() {
        // pacibsp / stp x20, x19, [sp, #-0x20]! / stp x29, x30, [sp, #0x10] / add x29, sp, #0x10
        #expect(ARM64Trampoline(words: [0xD503_237F, 0xA9BE_4FF4, 0xA901_7BFD, 0x9100_43FD], at: address) == nil)
        // A load from a register the arithmetic never set.
        let words = [
            InstructionEncoding.adrp(17, at: address, page: 0x1_E20F_A000),
            InstructionEncoding.loadUnsignedOffset(16, base: 8, byteOffset: 0),
            InstructionEncoding.branchToRegister(16),
            ARM64InstructionWord.noOperation,
        ]
        #expect(ARM64Trampoline(words: words, at: address) == nil)
    }
}
