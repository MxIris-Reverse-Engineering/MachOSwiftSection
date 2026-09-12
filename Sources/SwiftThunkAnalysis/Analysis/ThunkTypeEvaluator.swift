import Foundation

/// Runs a thunk's instructions symbolically and reports the type left in
/// `x0` when the function leaves.
///
/// Symbolic, not simulated: registers and stack slots hold
/// ``ThunkTypeExpression`` terms, addresses and small integers — never bytes
/// — and a call to a known runtime entry point produces a term rather than
/// running anything. The thunks measured (SwiftUI, macOS 26; the fixture's
/// noncopyable fields) are built from three such calls only: a nominal
/// type's metadata accessor, `swift_getWitnessTable`, and
/// `__swift_instantiateConcreteTypeFromMangledNameV2`. Every call the
/// environment does not recognize makes the value that depends on it
/// unknown, and an unknown result is reported as `nil`, never as a guess.
///
/// Control flow is followed, not flattened: a `b` inside the function jumps,
/// a `b` to a known callee is a tail call, and a conditional branch is
/// *decided* when its register is known — a runtime-capability flag such as
/// `_swift_runtimeSupportsNoncopyableTypes` counts as set, an address as
/// non-zero — and otherwise resolved by the caller's ``BranchPolicy``, which
/// is how the shape analyzer explores both arms of a version check.
///
/// The stack is modelled as slots keyed by their offset from the stack
/// pointer *at entry*: `sub sp, sp, #48` moves the pointer, and every later
/// `[sp, #k]` is resolved through the moved value, so a buffer the thunk
/// builds with `str` / `stp` and hands to an accessor via `add x1, sp, #k`
/// reads back consistently. A write-back access (`[sp, #-32]!`) is only ever
/// a prologue save and makes the pointer unknown rather than being modelled.
public struct ThunkTypeEvaluator {
    /// What a register or stack slot is known to hold.
    public enum Value: Sendable, Hashable {
        case type(ThunkTypeExpression)
        case witnessTable
        case immediate(Int64)
        case address(UInt64)
        /// `x0` at entry: the argument buffer the runtime hands the thunk.
        case argumentBuffer
        /// A stack address, as an offset from the stack pointer at entry.
        case stackAddress(Int64)
        /// A runtime-capability flag (`_swift_runtimeSupportsNoncopyableTypes`)
        /// loaded from its GOT slot. Any runtime this analysis targets has
        /// the capability, so the flag reads as set.
        case runtimeCapabilityFlag(String)
    }

    /// How a conditional the evaluator cannot decide is resolved.
    public enum BranchPolicy: Sendable, Hashable {
        /// Fall through a `cbz` / `cbnz`; take a `csel`'s `otherwise` operand.
        case assumeConditionFalse
        /// Take the branch; take a `csel`'s `whenConditionHolds` operand.
        case assumeConditionTrue
    }

    /// One run's result.
    public struct Outcome: Sendable, Hashable {
        /// The type in `x0` when the function left; `nil` when it is unknown
        /// or the run never left the function.
        public let result: ThunkTypeExpression?
        /// The first conditional the policy had to decide, if any — the
        /// instruction the shape analyzer reads the branch condition off.
        public let decidedInstructionIndex: Int?
        public let limitations: [ThunkAnalysisLimitation]
    }

    /// The runtime-capability flags a thunk tests, by GOT symbol name.
    static let runtimeCapabilityFlagNames: Set<String> = [
        "_swift_runtimeSupportsNoncopyableTypes",
        "swift_runtimeSupportsNoncopyableTypes",
    ]

    /// A run never steps more than this many instructions, so a loop the
    /// policy cannot escape ends instead of hanging.
    private static let maximumStepCount = 1024

    private let environment: any ThunkEvaluationEnvironment
    private let instructions: [ThunkInstruction]
    private let indicesByAddress: [UInt64: Int]
    private var valuesByRegister: [ThunkRegister: Value] = [:]
    private var valuesByStackOffset: [Int64: Value] = [:]
    private var lastComparison: (register: ThunkRegister, value: Int64)?

    public init(environment: any ThunkEvaluationEnvironment, instructions: [ThunkInstruction]) {
        self.environment = environment
        self.instructions = instructions
        var indicesByAddress: [UInt64: Int] = [:]
        for (index, instruction) in instructions.enumerated() where indicesByAddress[instruction.address] == nil {
            indicesByAddress[instruction.address] = index
        }
        self.indicesByAddress = indicesByAddress
        valuesByRegister[ThunkRegister(number: 0)] = .argumentBuffer
        valuesByRegister[.stackPointer] = .stackAddress(0)
    }

    public func value(of register: ThunkRegister) -> Value? {
        valuesByRegister[register]
    }

    /// Runs from `startIndex` until the function leaves.
    public mutating func run(from startIndex: Int = 0, policy: BranchPolicy) -> Outcome {
        var index = startIndex
        var decidedInstructionIndex: Int?
        var limitations: [ThunkAnalysisLimitation] = []
        var steps = 0
        while index < instructions.count, steps < Self.maximumStepCount {
            steps += 1
            let instruction = instructions[index]
            index += 1
            switch step(instruction.operation, policy: policy) {
            case .continue:
                continue
            case .jump(let target):
                guard let targetIndex = indicesByAddress[target] else {
                    return Outcome(result: nil, decidedInstructionIndex: decidedInstructionIndex, limitations: limitations)
                }
                index = targetIndex
            case .decided(let jumpTarget):
                if decidedInstructionIndex == nil { decidedInstructionIndex = index - 1 }
                if let jumpTarget {
                    guard let targetIndex = indicesByAddress[jumpTarget] else {
                        return Outcome(result: nil, decidedInstructionIndex: decidedInstructionIndex, limitations: limitations)
                    }
                    index = targetIndex
                }
            case .unsupportedCondition:
                limitations.append(.unsupportedConditionCode)
            case .left(let result):
                return Outcome(result: result, decidedInstructionIndex: decidedInstructionIndex, limitations: limitations)
            }
        }
        return Outcome(result: nil, decidedInstructionIndex: decidedInstructionIndex, limitations: limitations)
    }

    private enum Step {
        case `continue`
        case jump(UInt64)
        /// A conditional the policy decided; the target when it jumped.
        case decided(jumpTarget: UInt64?)
        case unsupportedCondition
        case left(ThunkTypeExpression?)
    }

    private mutating func step(_ operation: ThunkOperation, policy: BranchPolicy) -> Step {
        switch operation {
        case .materializePageAddress(let destination, let pageBaseAddress):
            assign(.address(pageBaseAddress), to: destination)
        case .addImmediate(let destination, let source, let addend):
            switch valuesByRegister[source] {
            case .address(let base):
                assign(.address(base &+ UInt64(bitPattern: addend)), to: destination)
            case .immediate(let base):
                assign(.immediate(base &+ addend), to: destination)
            case .stackAddress(let base):
                assign(.stackAddress(base &+ addend), to: destination)
            default:
                forget(destination)
            }
        case .moveImmediate(let destination, let value):
            assign(.immediate(value), to: destination)
        case .moveRegister(let destination, let source):
            assign(valuesByRegister[source], to: destination)
        case .loadFromMemory(let destination, let base, let displacement):
            assign(loaded(from: base, displacement: displacement), to: destination)
        case .loadPairFromMemory(let first, let second, let base, let displacement, let adjustsBase):
            if adjustsBase {
                forgetStack()
                forget(first)
                forget(second)
            } else {
                assign(loaded(from: base, displacement: displacement), to: first)
                assign(loaded(from: base, displacement: displacement + 8), to: second)
            }
        case .storeToMemory(let source, let base, let displacement):
            store(valuesByRegister[source], to: base, displacement: displacement)
        case .storePairToMemory(let first, let second, let base, let displacement, let adjustsBase):
            if adjustsBase {
                forgetStack()
            } else {
                store(valuesByRegister[first], to: base, displacement: displacement)
                store(valuesByRegister[second], to: base, displacement: displacement + 8)
            }
        case .call(let target):
            apply(callee: environment.callee(at: target))
        case .branch(let target):
            // A branch to a known function is a tail call: the function's
            // result is that call's. A branch inside the function is a jump.
            // Anything else — a callee the environment cannot name — leaves
            // with an unknown result: the value in `x0` now is that callee's
            // first argument, not the answer.
            let callee = environment.callee(at: target)
            if case .unknown = callee {
                return indicesByAddress[target] != nil ? .jump(target) : .left(nil)
            }
            apply(callee: callee)
            return .left(resultType)
        case .branchIfZero(let register, let target):
            guard let isZero = isZero(valuesByRegister[register]) else {
                return .decided(jumpTarget: policy == .assumeConditionTrue ? target : nil)
            }
            return isZero ? .jump(target) : .continue
        case .branchIfNotZero(let register, let target):
            guard let isZero = isZero(valuesByRegister[register]) else {
                return .decided(jumpTarget: policy == .assumeConditionTrue ? target : nil)
            }
            return isZero ? .continue : .jump(target)
        case .compareImmediate(let register, let value):
            lastComparison = (register: register, value: value)
        case .conditionalSelect(let destination, let whenConditionHolds, let otherwise, let condition):
            let holds: Bool?
            switch condition {
            case .equal, .notEqual:
                if let lastComparison, let isEqual = isEqual(valuesByRegister[lastComparison.register], to: lastComparison.value) {
                    holds = condition == .equal ? isEqual : !isEqual
                } else {
                    holds = nil
                }
            case .unsupported:
                forget(destination)
                return .unsupportedCondition
            }
            if let holds {
                assign(valuesByRegister[holds ? whenConditionHolds : otherwise], to: destination)
                return .continue
            }
            assign(valuesByRegister[policy == .assumeConditionTrue ? whenConditionHolds : otherwise], to: destination)
            return .decided(jumpTarget: nil)
        case .indirectBranch, .returnFromFunction:
            return .left(resultType)
        case .unmodelled:
            break
        }
        return .continue
    }

    private var resultType: ThunkTypeExpression? {
        Self.typeExpression(of: valuesByRegister[ThunkRegister(number: 0)])
    }

    /// The type a value stands for. A materialized address counts: a thunk
    /// that returns or passes an `adrp` / `add` address is handing over a
    /// metadata record (the `csel` shape returns one directly).
    private static func typeExpression(of value: Value?) -> ThunkTypeExpression? {
        switch value {
        case .type(let expression): expression
        case .address(let address): .constantMetadata(address: address)
        default: nil
        }
    }

    // MARK: - Deciding conditions

    /// Whether a value is zero, or `nil` when that is not known.
    private func isZero(_ value: Value?) -> Bool? {
        switch value {
        case .immediate(let immediate): immediate == 0
        case .runtimeCapabilityFlag, .address, .type, .witnessTable, .argumentBuffer, .stackAddress: false
        case nil: nil
        }
    }

    private func isEqual(_ value: Value?, to immediate: Int64) -> Bool? {
        switch value {
        case .immediate(let known): known == immediate
        case .runtimeCapabilityFlag, .address, .type, .witnessTable, .argumentBuffer, .stackAddress: immediate == 0 ? false : nil
        case nil: nil
        }
    }

    // MARK: - Memory

    private func loaded(from base: ThunkRegister, displacement: Int64) -> Value? {
        switch valuesByRegister[base] {
        case .argumentBuffer:
            guard displacement >= 0, displacement % 8 == 0 else { return nil }
            return .type(.argument(index: Int(displacement / 8)))
        case .stackAddress(let offset):
            return valuesByStackOffset[offset &+ displacement]
        case .address(let address):
            let slotAddress = address &+ UInt64(bitPattern: displacement)
            if let symbolName = environment.slotSymbolName(at: slotAddress), Self.runtimeCapabilityFlagNames.contains(symbolName) {
                return .runtimeCapabilityFlag(symbolName)
            }
            return environment.pointer(at: slotAddress).map { .address($0) }
        default:
            return nil
        }
    }

    private mutating func store(_ value: Value?, to base: ThunkRegister, displacement: Int64) {
        guard case .stackAddress(let offset) = valuesByRegister[base] else { return }
        valuesByStackOffset[offset &+ displacement] = value
    }

    private mutating func forgetStack() {
        valuesByStackOffset.removeAll()
        forget(.stackPointer)
    }

    // MARK: - Calls

    private mutating func apply(callee: ThunkCallee) {
        let result: Value?
        switch callee {
        case .metadataAccessor(let address, let argumentSlots):
            result = boundType(accessorAddress: address, argumentSlots: argumentSlots).map { .type($0) }
        case .witnessTableLookup:
            result = .witnessTable
        case .mangledNameInstantiation:
            let argumentAddresses = [ThunkRegister(number: 0), ThunkRegister(number: 1)].compactMap { register -> UInt64? in
                guard case .address(let address) = valuesByRegister[register] else { return nil }
                return address
            }
            result = argumentAddresses.isEmpty ? nil : .type(.instantiatedFromMangledName(argumentAddresses: argumentAddresses))
        case .metadataStateCheck:
            result = valuesByRegister[ThunkRegister(number: 1)]
        case .availabilityCheck, .unknown:
            result = nil
        }
        // AAPCS64: x0–x17 are caller-saved. x0 carries the result.
        for registerNumber in 0 ... 17 {
            forget(ThunkRegister(number: registerNumber))
        }
        assign(result, to: ThunkRegister(number: 0))
        lastComparison = nil
    }

    /// The accessor's key arguments as the calling convention places them:
    /// `x1`–`x3` for up to three, else a buffer `x1` points at.
    private func accessorArgumentValues(count: Int) -> [Value?] {
        guard count > 0 else { return [] }
        if count <= 3 {
            return (1 ... count).map { valuesByRegister[ThunkRegister(number: $0)] }
        }
        guard case .stackAddress(let bufferOffset) = valuesByRegister[ThunkRegister(number: 1)] else {
            return Array(repeating: nil, count: count)
        }
        return (0 ..< count).map { valuesByStackOffset[bufferOffset &+ Int64($0 * 8)] }
    }

    private func boundType(accessorAddress: UInt64, argumentSlots: [ThunkArgumentSlot]) -> ThunkTypeExpression? {
        var typeArguments: [ThunkTypeExpression] = []
        for (slot, value) in zip(argumentSlots, accessorArgumentValues(count: argumentSlots.count)) {
            guard slot == .type else { continue }
            // A type argument the analysis cannot name makes the whole result
            // unnameable; a witness-table slot's value is irrelevant to a name.
            guard let expression = Self.typeExpression(of: value) else { return nil }
            typeArguments.append(expression)
        }
        return .bound(accessorAddress: accessorAddress, typeArguments: typeArguments)
    }

    // MARK: - Registers

    private mutating func assign(_ value: Value?, to register: ThunkRegister) {
        guard !register.isZeroRegister else { return }
        if let value {
            valuesByRegister[register] = value
        } else {
            valuesByRegister.removeValue(forKey: register)
        }
    }

    private mutating func forget(_ register: ThunkRegister) {
        valuesByRegister.removeValue(forKey: register)
    }
}
