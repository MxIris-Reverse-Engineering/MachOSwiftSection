import Foundation
import Capstone

/// Decodes a thunk's machine code into ``ThunkInstruction`` values.
///
/// The **only** file in the module that knows Capstone exists. Everything
/// above it works on the engine-independent vocabulary in
/// `ThunkInstruction.swift`, so the shape recognizer can be driven from
/// synthesized sequences and a future decoder (another engine, or x86_64)
/// replaces this file alone.
///
/// A disassembler is used rather than hand-decoding the instruction words,
/// even though the set of shapes is small. Two reasons, both measured during
/// the proposal's research: the thunks already come in more than one shape and
/// drift with the compiler, so hand-decoding means a new bit-field reader per
/// shape; and the arithmetic that a hand decoder gets wrong is exactly the
/// PC-relative kind — `adrp`'s page base is relative to the instruction's own
/// address, and computing it from a *file offset* silently produces a
/// plausible-looking address in the wrong place.
public enum CapstoneThunkDecoder {
    /// How many instructions to decode before giving up on recognizing the
    /// thunk.
    ///
    /// Every shape seen so far resolves within a dozen instructions — the
    /// availability-conditional one is the longest at roughly fourteen. The
    /// bound exists so a mis-located offset lands in unrelated code and stops,
    /// rather than disassembling an entire `__TEXT` segment.
    public static let defaultMaximumInstructionCount = 48

    /// The cap for a whole thunk read by ``AccessorThunkReader``: a
    /// type-construction thunk (`SwiftUI.DefinesSearchCompletionModifier.Body`)
    /// runs to about ninety instructions, both branches included.
    public static let constructionMaximumInstructionCount = 160

    /// Decodes one function: from `startAddress` to wherever control leaves it
    /// for good.
    ///
    /// The thunks carry no symbol and no size — they sit in a stripped
    /// `__TEXT` where the next function begins immediately — so the end has to
    /// be *derived*. The rule is the standard linear-sweep one: a `ret`, or a
    /// `b` whose target lies outside the bytes decoded so far (a tail call),
    /// ends the function **provided** no conditional branch already seen
    /// points past it. That proviso is what keeps the two halves of an
    /// `if #available` together: the satisfied branch ends in a `b` over the
    /// unsatisfied one, and stopping there would silently drop one of the two
    /// candidates — which is the whole answer this module exists to produce.
    public static func decodeFunction(
        machineCode: Data,
        startAddress: UInt64,
        maximumInstructionCount: Int = defaultMaximumInstructionCount,
        isKnownFunction: (UInt64) -> Bool = { _ in false }
    ) throws -> [ThunkInstruction] {
        let decodedInstructions = try decode(
            machineCode: machineCode,
            startAddress: startAddress,
            maximumInstructionCount: maximumInstructionCount
        )
        let decodedUpperBound = startAddress + UInt64(machineCode.count)
        var furthestInFunctionTarget = startAddress
        var functionInstructions: [ThunkInstruction] = []

        func isInFunction(_ target: UInt64) -> Bool {
            target > startAddress && target < decodedUpperBound
        }

        for instruction in decodedInstructions {
            functionInstructions.append(instruction)
            switch instruction.operation {
            case .branchIfZero(_, let target), .branchIfNotZero(_, let target):
                if isInFunction(target) {
                    furthestInFunctionTarget = max(furthestInFunctionTarget, target)
                }
            case .branch(let target):
                // A forward `b` to a function the caller can name is a tail
                // call, not a jump — the function it names may sit right
                // after this one inside the decoded window (the fixture's
                // thunk tail-calls the image's own
                // `__swift_instantiateConcreteTypeFromMangledNameV2` copy,
                // which follows it), and reading it as a jump would extend
                // this function into that one.
                if isInFunction(target), !isKnownFunction(target) {
                    furthestInFunctionTarget = max(furthestInFunctionTarget, target)
                } else if instruction.address >= furthestInFunctionTarget {
                    return functionInstructions
                }
            case .indirectBranch:
                // A register jump never returns here either (a shared-cache
                // stub's `braa x16, x17`, a tail call through a pointer).
                if instruction.address >= furthestInFunctionTarget {
                    return functionInstructions
                }
            case .returnFromFunction:
                if instruction.address >= furthestInFunctionTarget {
                    return functionInstructions
                }
            default:
                break
            }
        }
        return functionInstructions
    }

    /// Decodes up to `maximumInstructionCount` instructions starting at
    /// `startAddress`, with no notion of where the function ends.
    ///
    /// `startAddress` must be the address the code will be *interpreted* at
    /// (the virtual address), not the offset it was read from: Capstone
    /// resolves `adrp` and `bl` operands against it, and every absolute
    /// address the analysis derives comes from those operands.
    public static func decode(
        machineCode: Data,
        startAddress: UInt64,
        maximumInstructionCount: Int = defaultMaximumInstructionCount
    ) throws -> [ThunkInstruction] {
        let capstone = try Capstone(arch: .arm64, mode: [Mode.endian.little])
        try capstone.set(option: .detail(value: true))
        let decodedInstructions: [Arm64Instruction] = try capstone.disassemble(
            code: machineCode,
            address: startAddress,
            count: maximumInstructionCount
        )
        return decodedInstructions.map(thunkInstruction(from:))
    }

    private static func thunkInstruction(from instruction: Arm64Instruction) -> ThunkInstruction {
        ThunkInstruction(
            address: instruction.address,
            operation: operation(from: instruction),
            mnemonic: instruction.mnemonic
        )
    }

    private static func operation(from instruction: Arm64Instruction) -> ThunkOperation {
        let operands = instruction.operands
        switch instruction.instruction {
        case .adrp:
            guard let destination = register(at: 0, of: operands),
                  let pageBaseAddress = immediateValue(at: 1, of: operands)
            else { return .unmodelled }
            return .materializePageAddress(destination: destination, pageBaseAddress: UInt64(bitPattern: pageBaseAddress))
        case .adr:
            // `adr` materializes a full address on its own, which the tracker
            // models as a page address with nothing added to it.
            guard let destination = register(at: 0, of: operands),
                  let address = immediateValue(at: 1, of: operands)
            else { return .unmodelled }
            return .materializePageAddress(destination: destination, pageBaseAddress: UInt64(bitPattern: address))
        case .add:
            guard let destination = register(at: 0, of: operands),
                  let source = register(at: 1, of: operands),
                  let addend = immediateValue(at: 2, of: operands)
            else { return .unmodelled }
            return .addImmediate(destination: destination, source: source, addend: addend)
        case .sub:
            // `sub sp, sp, #48` opens a frame; modelled as adding the negated
            // immediate so a stack model sees one kind of base adjustment.
            guard let destination = register(at: 0, of: operands),
                  let source = register(at: 1, of: operands),
                  let subtrahend = immediateValue(at: 2, of: operands)
            else { return .unmodelled }
            return .addImmediate(destination: destination, source: source, addend: -subtrahend)
        case .mov, .movz, .orr:
            // Capstone spells a register-to-register move `mov` and an
            // immediate load `mov` too; `movz` and the `orr xN, xzr, #imm`
            // form are the un-aliased spellings of the same two things.
            guard let destination = register(at: 0, of: operands) else { return .unmodelled }
            if let value = immediateValue(at: 1, of: operands) {
                return .moveImmediate(destination: destination, value: value)
            }
            if let source = register(at: 1, of: operands) {
                if source.isZeroRegister, let value = immediateValue(at: 2, of: operands) {
                    return .moveImmediate(destination: destination, value: value)
                }
                return .moveRegister(destination: destination, source: source)
            }
            return .unmodelled
        case .ldr, .ldur:
            guard let destination = register(at: 0, of: operands),
                  let memory = memoryOperand(at: 1, of: operands),
                  instruction.writeBack != true
            else { return .unmodelled }
            return .loadFromMemory(
                destination: destination,
                base: memory.base,
                displacement: memory.displacement
            )
        case .ldp:
            guard let first = register(at: 0, of: operands),
                  let second = register(at: 1, of: operands),
                  let memory = memoryOperand(at: 2, of: operands)
            else { return .unmodelled }
            return .loadPairFromMemory(
                first: first,
                second: second,
                base: memory.base,
                displacement: memory.displacement,
                adjustsBase: instruction.writeBack == true
            )
        case .str, .stur:
            guard let source = register(at: 0, of: operands),
                  let memory = memoryOperand(at: 1, of: operands),
                  instruction.writeBack != true
            else { return .unmodelled }
            return .storeToMemory(source: source, base: memory.base, displacement: memory.displacement)
        case .stp:
            guard let first = register(at: 0, of: operands),
                  let second = register(at: 1, of: operands),
                  let memory = memoryOperand(at: 2, of: operands)
            else { return .unmodelled }
            return .storePairToMemory(
                first: first,
                second: second,
                base: memory.base,
                displacement: memory.displacement,
                adjustsBase: instruction.writeBack == true
            )
        case .bl:
            guard let target = immediateValue(at: 0, of: operands) else { return .unmodelled }
            return .call(target: UInt64(bitPattern: target))
        case .b:
            guard let target = immediateValue(at: 0, of: operands) else { return .unmodelled }
            // A conditional `b.<cond>` carries the same operand shape; the
            // condition code is what tells them apart. Only the unconditional
            // form is modelled as a branch — a conditional one is a shape the
            // recognizer has not been taught, and `unmodelled` is how it says so.
            guard instruction.conditionCode == nil else { return .unmodelled }
            return .branch(target: UInt64(bitPattern: target))
        case .cbz:
            guard let register = register(at: 0, of: operands),
                  let target = immediateValue(at: 1, of: operands)
            else { return .unmodelled }
            return .branchIfZero(register: register, target: UInt64(bitPattern: target))
        case .cbnz:
            guard let register = register(at: 0, of: operands),
                  let target = immediateValue(at: 1, of: operands)
            else { return .unmodelled }
            return .branchIfNotZero(register: register, target: UInt64(bitPattern: target))
        case .cmp:
            guard let register = register(at: 0, of: operands),
                  let value = immediateValue(at: 1, of: operands)
            else { return .unmodelled }
            return .compareImmediate(register: register, value: value)
        case .csel:
            guard let destination = register(at: 0, of: operands),
                  let whenConditionHolds = register(at: 1, of: operands),
                  let otherwise = register(at: 2, of: operands)
            else { return .unmodelled }
            return .conditionalSelect(
                destination: destination,
                whenConditionHolds: whenConditionHolds,
                otherwise: otherwise,
                condition: condition(from: instruction.conditionCode)
            )
        case .ret, .retaa, .retab:
            // `retaa` / `retab` are `ret` with pointer authentication of the
            // return address; reading them as ordinary instructions let the
            // decoder walk straight past a function's end into the next one.
            return .returnFromFunction
        case .br, .braa, .brab:
            guard let register = register(at: 0, of: operands) else { return .unmodelled }
            return .indirectBranch(register: register)
        default:
            return .unmodelled
        }
    }

    private static func condition(from conditionCode: Arm64Cc?) -> ThunkCondition {
        switch conditionCode {
        case .eq: .equal
        case .ne: .notEqual
        default: .unsupported
        }
    }

    private static func register(at index: Int, of operands: [Arm64Instruction.Operand]) -> ThunkRegister? {
        guard index < operands.count, let register = operands[index].register else { return nil }
        return thunkRegister(from: register)
    }

    private static func immediateValue(at index: Int, of operands: [Arm64Instruction.Operand]) -> Int64? {
        guard index < operands.count else { return nil }
        return operands[index].immediateValue
    }

    private static func memoryOperand(
        at index: Int,
        of operands: [Arm64Instruction.Operand]
    ) -> (base: ThunkRegister, displacement: Int64)? {
        guard index < operands.count, let memory = operands[index].memory else { return nil }
        // An indexed load reads a register this analysis does not track, so it
        // is not a plain displacement and must not be reported as one.
        guard memory.index == nil, let base = thunkRegister(from: memory.base) else { return nil }
        return (base: base, displacement: Int64(memory.displacement))
    }

    /// Folds Capstone's separate 32-bit and 64-bit register spellings onto one
    /// register number; see ``ThunkRegister``.
    private static func thunkRegister(from register: Arm64Reg) -> ThunkRegister? {
        switch register {
        case .fp:
            return ThunkRegister(number: 29)
        case .lr:
            return ThunkRegister(number: 30)
        case .xzr, .wzr:
            return .zeroRegister
        case .sp, .wsp:
            return .stackPointer
        default:
            break
        }
        let rawValue = Int(register.rawValue)
        let firstWordRegister = Int(Arm64Reg.w0.rawValue)
        let firstDoubleWordRegister = Int(Arm64Reg.x0.rawValue)
        // `w0`–`w30` and `x0`–`x28` are two contiguous runs; `x29` / `x30` are
        // spelled `fp` / `lr` and handled above.
        if rawValue >= firstWordRegister, rawValue <= Int(Arm64Reg.w30.rawValue) {
            return ThunkRegister(number: rawValue - firstWordRegister)
        }
        if rawValue >= firstDoubleWordRegister, rawValue <= Int(Arm64Reg.x28.rawValue) {
            return ThunkRegister(number: rawValue - firstDoubleWordRegister)
        }
        return nil
    }
}
