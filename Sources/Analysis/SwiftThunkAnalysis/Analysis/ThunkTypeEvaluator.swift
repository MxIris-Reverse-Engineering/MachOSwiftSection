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
/// ## Following a call the environment cannot name
///
/// A call whose target is neither an accessor nor a runtime entry point is
/// not the end of the road when the environment can hand over the callee's
/// instructions: the evaluator runs *them*, with the registers as they are
/// at the call, and takes what the callee leaves in `x0` as the call's
/// result. This is what reads a compiler-merged accessor (`…MaTm`): the
/// compiler folds every "check the cache, else call the accessor with this
/// argument" body into one function whose parameters are the cache slot,
/// the argument and the accessor itself — the type is entirely in the
/// caller's registers, and the merged body's own symbol names one of the
/// bodies folded into it, never the callee. The rules that keep this
/// honest: the callee is run with the caller's policy first and, when that
/// run decides a conditional and answers nothing, once more the other way
/// (the cache probe's warm path returns the unreadable cached word, its
/// cold path builds the type — the same rule the shape analyzer applies to
/// an unconditional thunk); the availability check is never followed, so
/// its result stays unknown and the arms stay the analyzer's to explore; a
/// function already being followed is not entered again; and the depth is
/// capped. After the callee returns, `x1`–`x17` are forgotten and the
/// caller's own stack model is kept, as AAPCS64 promises.
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
        /// A function, loaded from a GOT slot that *binds* to it by name — a
        /// standalone file's pointer to another image's accessor, which the
        /// file itself holds no address for. Calling through the register
        /// (`blr`) applies the callee like a direct call.
        case functionReference(ThunkCallee)
    }

    /// How a conditional the evaluator cannot decide is resolved.
    public enum BranchPolicy: Sendable, Hashable {
        /// Fall through a `cbz` / `cbnz`; take a `csel`'s `otherwise` operand.
        case assumeConditionFalse
        /// Take the branch; take a `csel`'s `whenConditionHolds` operand.
        case assumeConditionTrue

        fileprivate var opposite: BranchPolicy {
            self == .assumeConditionFalse ? .assumeConditionTrue : .assumeConditionFalse
        }
    }

    /// One call a run made: which instruction made it and where it went.
    public struct CallSite: Sendable, Hashable {
        public let instructionIndex: Int
        /// The static target of a `bl` / `b`; `nil` for a call through a
        /// register, which has none — and which the shape analyzer's
        /// single-lookup fallback therefore never names.
        public let target: UInt64?

        public init(instructionIndex: Int, target: UInt64?) {
            self.instructionIndex = instructionIndex
            self.target = target
        }
    }

    /// One run's result.
    public struct Outcome: Sendable, Hashable {
        /// The type in `x0` when the function left; `nil` when it is unknown
        /// or the run never left the function.
        public let result: ThunkTypeExpression?
        /// The first conditional the policy had to decide, if any — the
        /// instruction the shape analyzer reads the branch condition off.
        public let decidedInstructionIndex: Int?
        /// Every call the run made, in order: each `bl` and `blr`, and each
        /// `b` or `br` that left the function (a tail call, whether or not
        /// the environment could name its target). An in-function jump is
        /// not a call. A call made inside a followed callee is listed under
        /// the instruction that entered the callee. The instruction index
        /// lets the shape analyzer separate an arm's calls from the
        /// availability check's own.
        public let callSites: [CallSite]
        /// `true` when the run left through `ret`. `false` for a tail call,
        /// a register jump, and a run that never left — the cases where the
        /// value in `x0` is *not* what the last call returned.
        public let leftThroughReturn: Bool
        public let limitations: [ThunkAnalysisLimitation]

        public init(
            result: ThunkTypeExpression?,
            decidedInstructionIndex: Int?,
            callSites: [CallSite] = [],
            leftThroughReturn: Bool = false,
            limitations: [ThunkAnalysisLimitation]
        ) {
            self.result = result
            self.decidedInstructionIndex = decidedInstructionIndex
            self.callSites = callSites
            self.leftThroughReturn = leftThroughReturn
            self.limitations = limitations
        }
    }

    /// The runtime-capability flags a thunk tests, by GOT symbol name.
    static let runtimeCapabilityFlagNames: Set<String> = [
        "_swift_runtimeSupportsNoncopyableTypes",
        "swift_runtimeSupportsNoncopyableTypes",
    ]

    /// A run never steps more than this many instructions, so a loop the
    /// policy cannot escape ends instead of hanging.
    private static let maximumStepCount = 1024

    /// How many functions deep a call is followed. A merged accessor is one
    /// level; two is a merged accessor reached through a local wrapper.
    private static let maximumFollowDepth = 3

    private let environment: any ThunkEvaluationEnvironment
    private let instructions: [ThunkInstruction]
    private let indicesByAddress: [UInt64: Int]
    /// Call targets never followed into, whatever the environment says:
    /// the availability check, whose result must stay unknown.
    private let callTargetsLeftOpaque: Set<UInt64>
    /// The entry addresses of the functions being followed, outermost
    /// first; empty for the thunk itself.
    private let followedFunctions: [UInt64]
    private var valuesByRegister: [ThunkRegister: Value] = [:]
    private var valuesByStackOffset: [Int64: Value] = [:]
    private var lastComparison: (register: ThunkRegister, value: Int64)?
    private var callSites: [CallSite] = []
    private var limitations: [ThunkAnalysisLimitation] = []
    /// What `x0` held when the last run left the function, when it left
    /// with a meaningful `x0`: after `ret`, or after a tail call whose
    /// callee was applied. A tail call to an unknown callee leaves nothing.
    private var valueOnLeaving: Value?

    /// `callTargetsLeftOpaque` names call targets the evaluator must not
    /// follow into even when the environment could decode them.
    public init(
        environment: any ThunkEvaluationEnvironment,
        instructions: [ThunkInstruction],
        callTargetsLeftOpaque: Set<UInt64> = []
    ) {
        self.init(environment: environment, instructions: instructions, callTargetsLeftOpaque: callTargetsLeftOpaque, followedFunctions: [])
        valuesByRegister[ThunkRegister(number: 0)] = .argumentBuffer
        valuesByRegister[.stackPointer] = .stackAddress(0)
    }

    private init(
        environment: any ThunkEvaluationEnvironment,
        instructions: [ThunkInstruction],
        callTargetsLeftOpaque: Set<UInt64>,
        followedFunctions: [UInt64]
    ) {
        self.environment = environment
        self.instructions = instructions
        self.callTargetsLeftOpaque = callTargetsLeftOpaque
        self.followedFunctions = followedFunctions
        var indicesByAddress: [UInt64: Int] = [:]
        for (index, instruction) in instructions.enumerated() where indicesByAddress[instruction.address] == nil {
            indicesByAddress[instruction.address] = index
        }
        self.indicesByAddress = indicesByAddress
    }

    public func value(of register: ThunkRegister) -> Value? {
        valuesByRegister[register]
    }

    /// Runs from `startIndex` until the function leaves.
    public mutating func run(from startIndex: Int = 0, policy: BranchPolicy) -> Outcome {
        var index = startIndex
        var decidedInstructionIndex: Int?
        var steps = 0
        callSites = []
        limitations = []
        valueOnLeaving = nil
        while index < instructions.count, steps < Self.maximumStepCount {
            steps += 1
            let instruction = instructions[index]
            index += 1
            let instructionIndex = index - 1
            switch step(instruction, at: instructionIndex, policy: policy) {
            case .continue:
                continue
            case .jump(let target):
                guard let targetIndex = indicesByAddress[target] else {
                    return Outcome(result: nil, decidedInstructionIndex: decidedInstructionIndex, callSites: callSites, limitations: limitations)
                }
                index = targetIndex
            case .decided(let jumpTarget):
                if decidedInstructionIndex == nil { decidedInstructionIndex = instructionIndex }
                if let jumpTarget {
                    guard let targetIndex = indicesByAddress[jumpTarget] else {
                        return Outcome(result: nil, decidedInstructionIndex: decidedInstructionIndex, callSites: callSites, limitations: limitations)
                    }
                    index = targetIndex
                }
            case .unsupportedCondition:
                limitations.append(.unsupportedConditionCode)
            case .left(let value, let throughReturn):
                valueOnLeaving = value
                return Outcome(
                    result: Self.typeExpression(of: value),
                    decidedInstructionIndex: decidedInstructionIndex,
                    callSites: callSites,
                    leftThroughReturn: throughReturn,
                    limitations: limitations
                )
            }
        }
        return Outcome(result: nil, decidedInstructionIndex: decidedInstructionIndex, callSites: callSites, limitations: limitations)
    }

    private enum Step {
        case `continue`
        case jump(UInt64)
        /// A conditional the policy decided; the target when it jumped.
        case decided(jumpTarget: UInt64?)
        case unsupportedCondition
        /// The function left, with this in `x0` when that is meaningful;
        /// `throughReturn` only for `ret`.
        case left(Value?, throughReturn: Bool)
    }

    private mutating func step(_ instruction: ThunkInstruction, at instructionIndex: Int, policy: BranchPolicy) -> Step {
        switch instruction.operation {
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
            callSites.append(CallSite(instructionIndex: instructionIndex, target: target))
            call(environment.callee(at: target), staticTarget: target, at: instructionIndex, policy: policy)
        case .indirectCall(let register):
            callSites.append(CallSite(instructionIndex: instructionIndex, target: nil))
            let (callee, staticTarget) = calleeHeld(by: register)
            call(callee, staticTarget: staticTarget, at: instructionIndex, policy: policy)
        case .branch(let target):
            // A branch to a known function is a tail call: the function's
            // result is that call's. A branch inside the function is a jump.
            // Anything else is a tail call to a function the environment
            // cannot name — followed when it can be decoded, and otherwise
            // leaving with an unknown result: the value in `x0` now is that
            // callee's first argument, not the answer.
            let callee = environment.callee(at: target)
            if case .unknown = callee, indicesByAddress[target] != nil {
                return .jump(target)
            }
            callSites.append(CallSite(instructionIndex: instructionIndex, target: target))
            return tailCall(callee, staticTarget: target, at: instructionIndex, policy: policy)
        case .indirectBranch(let register):
            callSites.append(CallSite(instructionIndex: instructionIndex, target: nil))
            let (callee, staticTarget) = calleeHeld(by: register)
            return tailCall(callee, staticTarget: staticTarget, at: instructionIndex, policy: policy)
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
        case .returnFromFunction:
            return .left(valuesByRegister[ThunkRegister(number: 0)], throughReturn: true)
        case .conditionalBranchNotModelled(let target):
            // Falling through onto a trap is not a path a running program
            // takes (the arm64e epilogue's pointer-authentication check:
            // `tbz x16, #62, Lreturn; brk`), so the branch is taken. Any
            // other case tests something unknown in a way the policy cannot
            // stand in for; the run ends here with no answer.
            if instructionIndex + 1 < instructions.count, case .trap = instructions[instructionIndex + 1].operation {
                return .jump(target)
            }
            limitations.append(.conditionalBranchNotModelled(mnemonic: instruction.mnemonic))
            return .left(nil, throughReturn: false)
        case .trap:
            // The program would have crashed here; nothing it computed after
            // this point exists.
            return .left(nil, throughReturn: false)
        case .signOrAuthenticatePointer:
            // The same pointer, signed or checked; the register keeps its value.
            break
        case .unmodelled(let writtenRegisters):
            for register in writtenRegisters {
                if register.isStackPointer { forgetStack() } else { forget(register) }
            }
        }
        return .continue
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
        case .runtimeCapabilityFlag, .address, .type, .witnessTable, .argumentBuffer, .stackAddress, .functionReference: false
        case nil: nil
        }
    }

    private func isEqual(_ value: Value?, to immediate: Int64) -> Bool? {
        switch value {
        case .immediate(let known): known == immediate
        case .runtimeCapabilityFlag, .address, .type, .witnessTable, .argumentBuffer, .stackAddress, .functionReference: immediate == 0 ? false : nil
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
            if let pointer = environment.pointer(at: slotAddress) {
                return .address(pointer)
            }
            // No pointer in the file: a bind, which holds only a name until
            // dyld fills the slot in. What that name is, as a callee.
            let boundCallee = environment.callee(boundInSlotAt: slotAddress)
            if case .unknown = boundCallee { return nil }
            return .functionReference(boundCallee)
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

    /// What a register holds as a call target: a function reference from a
    /// bind, or an address the environment may know a function at. The
    /// address, when there is one, is what a follow needs.
    private func calleeHeld(by register: ThunkRegister) -> (callee: ThunkCallee, staticTarget: UInt64?) {
        switch valuesByRegister[register] {
        case .functionReference(let callee): (callee, nil)
        case .address(let address): (environment.callee(at: address), address)
        default: (.unknown, nil)
        }
    }

    /// A call that returns here: applies a known callee, follows an unknown
    /// one into its body when it can be decoded, and otherwise forgets the
    /// result.
    private mutating func call(_ callee: ThunkCallee, staticTarget: UInt64?, at instructionIndex: Int, policy: BranchPolicy) {
        if case .unknown = callee, let staticTarget, let followed = follow(functionAt: staticTarget, calledFrom: instructionIndex, policy: policy) {
            forgetCallerSavedRegisters()
            assign(followed.valueOnLeaving, to: ThunkRegister(number: 0))
            return
        }
        apply(callee: callee)
    }

    /// A call that does not return here: the function's result is the
    /// callee's.
    private mutating func tailCall(_ callee: ThunkCallee, staticTarget: UInt64?, at instructionIndex: Int, policy: BranchPolicy) -> Step {
        if case .unknown = callee {
            guard let staticTarget, let followed = follow(functionAt: staticTarget, calledFrom: instructionIndex, policy: policy) else {
                return .left(nil, throughReturn: false)
            }
            return .left(followed.valueOnLeaving, throughReturn: followed.leftThroughReturn)
        }
        apply(callee: callee)
        return .left(valuesByRegister[ThunkRegister(number: 0)], throughReturn: false)
    }

    private struct FollowedCall {
        let valueOnLeaving: Value?
        let leftThroughReturn: Bool
    }

    /// Runs the function at `target` with the registers as they are now and
    /// reports what it left in `x0`; `nil` when it is not one to follow —
    /// left opaque on purpose, already being followed, too deep, or not
    /// decodable. The callee's calls are recorded under `instructionIndex`.
    private mutating func follow(functionAt target: UInt64, calledFrom instructionIndex: Int, policy: BranchPolicy) -> FollowedCall? {
        guard !callTargetsLeftOpaque.contains(target),
              followedFunctions.count < Self.maximumFollowDepth,
              !followedFunctions.contains(target),
              let calleeInstructions = environment.instructions(ofFunctionAt: target),
              !calleeInstructions.isEmpty
        else { return nil }
        var callee = followedEvaluator(instructions: calleeInstructions, entry: target)
        var outcome = callee.run(policy: policy)
        // A callee that had to decide a conditional and answered nothing
        // took the arm that returns something unnameable (a cache probe's
        // warm path); the other arm is the one that builds the type.
        if outcome.result == nil, outcome.decidedInstructionIndex != nil {
            var otherWay = followedEvaluator(instructions: calleeInstructions, entry: target)
            let otherOutcome = otherWay.run(policy: policy.opposite)
            if otherOutcome.result != nil {
                callee = otherWay
                outcome = otherOutcome
            }
        }
        callSites += outcome.callSites.map { CallSite(instructionIndex: instructionIndex, target: $0.target) }
        limitations += outcome.limitations
        return FollowedCall(valueOnLeaving: callee.valueOnLeaving, leftThroughReturn: outcome.leftThroughReturn)
    }

    private func followedEvaluator(instructions: [ThunkInstruction], entry: UInt64) -> ThunkTypeEvaluator {
        var followed = ThunkTypeEvaluator(
            environment: environment,
            instructions: instructions,
            callTargetsLeftOpaque: callTargetsLeftOpaque,
            followedFunctions: followedFunctions + [entry]
        )
        followed.valuesByRegister = valuesByRegister
        followed.valuesByStackOffset = valuesByStackOffset
        return followed
    }

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
        case .concreteTypeAccessor(let symbolName):
            result = .type(.namedByAccessorSymbol(symbolName: symbolName))
        case .availabilityCheck, .unknown:
            result = nil
        }
        forgetCallerSavedRegisters()
        assign(result, to: ThunkRegister(number: 0))
    }

    /// AAPCS64: x0–x17 are caller-saved; the result lands in x0 afterwards.
    private mutating func forgetCallerSavedRegisters() {
        for registerNumber in 0 ... 17 {
            forget(ThunkRegister(number: registerNumber))
        }
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
