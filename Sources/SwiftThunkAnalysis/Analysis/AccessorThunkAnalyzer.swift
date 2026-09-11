#if THUNK_ANALYSIS

import Foundation

/// Reads a decoded thunk and says what it computes.
///
/// Works purely on ``ThunkInstruction`` values, so it is exercised from
/// synthesized sequences with no binary and no disassembler in the way.
///
/// ## The shapes, as measured
///
/// All three thunks found in SwiftUI (macOS 26 shared cache) start the same
/// way — four immediates into `w0`–`w3`, then a call to
/// `__isPlatformVersionAtLeast` — and then differ in how they use the result:
///
/// 1. `cmp w0, #0` + `csel` between two **metadata** addresses materialized by
///    `adrp` / `add` (`SwiftUI.ResolvedMenuStyle.Body`).
/// 2. `cbz w0` splitting into two branches, each calling one metadata
///    **accessor** (`SwiftUI.OnModifierKeysChangedModifier.Body`).
/// 3. The same split, but one branch *builds* its type through a chain of
///    calls rather than looking one up
///    (`SwiftUI.DefinesSearchCompletionModifier.Body`).
///
/// The third is deliberately **not** reduced to a guess: a branch making more
/// than one call is reported as ``ThunkAnalysisLimitation/branchIsNotASingleLookup(condition:callCount:)``
/// and contributes no candidate. Naming the first call's result would produce
/// a real, fully-qualified, wrong type — the exact failure mode the
/// `.children` bug in `Node+OpaqueType.swift` had, and the one worth avoiding
/// twice.
public enum AccessorThunkAnalyzer {
    public static func analyze(instructions: [ThunkInstruction]) -> AccessorThunkProgram {
        guard let availabilityCallIndex = indexOfAvailabilityCheckCall(in: instructions) else {
            return AccessorThunkProgram(availabilityCheck: nil, candidates: [], limitations: [.noRecognizedShape])
        }
        let availabilityCheck = self.availabilityCheck(at: availabilityCallIndex, in: instructions)

        if let program = analyzeConditionalSelect(
            after: availabilityCallIndex,
            in: instructions,
            availabilityCheck: availabilityCheck
        ) {
            return program
        }
        if let program = analyzeBranchSplit(
            after: availabilityCallIndex,
            in: instructions,
            availabilityCheck: availabilityCheck
        ) {
            return program
        }
        return AccessorThunkProgram(
            availabilityCheck: availabilityCheck,
            candidates: [],
            limitations: [.selectionNotRecognized]
        )
    }

    // MARK: - The availability check

    /// The number of arguments `__isPlatformVersionAtLeast` takes, and so the
    /// number of consecutive immediate loads that identify the call.
    private static let availabilityArgumentCount = 4

    /// Finds the call preceded by exactly four immediates loaded into `w0`–`w3`.
    ///
    /// Shape-based rather than symbol-based because the function is
    /// compiler-rt's, statically linked, and carries no symbol in a stripped
    /// framework — there is nothing to match a name against. The shape is
    /// specific enough in practice: a Swift metadata accessor's own calling
    /// convention puts a `MetadataRequest` in `x0` and pointers elsewhere, so
    /// four consecutive small immediates in argument order do not occur by
    /// accident. `PlatformAvailabilityCheck.checkFunctionAddress` carries the
    /// callee so a caller can cross-check it across thunks.
    private static func indexOfAvailabilityCheckCall(in instructions: [ThunkInstruction]) -> Int? {
        for (index, instruction) in instructions.enumerated() {
            guard case .call = instruction.operation, index >= availabilityArgumentCount else { continue }
            let argumentLoads = instructions[(index - availabilityArgumentCount) ..< index]
            let loadsArgumentsInOrder = argumentLoads.enumerated().allSatisfy { position, loadInstruction in
                guard case .moveImmediate(let destination, _) = loadInstruction.operation else { return false }
                return destination.number == position
            }
            if loadsArgumentsInOrder { return index }
        }
        return nil
    }

    private static func availabilityCheck(
        at callIndex: Int,
        in instructions: [ThunkInstruction]
    ) -> PlatformAvailabilityCheck? {
        guard case .call(let checkFunctionAddress) = instructions[callIndex].operation else { return nil }
        var arguments: [UInt32] = []
        for instruction in instructions[(callIndex - availabilityArgumentCount) ..< callIndex] {
            guard case .moveImmediate(_, let value) = instruction.operation, value >= 0 else { return nil }
            arguments.append(UInt32(truncatingIfNeeded: value))
        }
        return PlatformAvailabilityCheck(
            platform: arguments[0],
            major: arguments[1],
            minor: arguments[2],
            patch: arguments[3],
            checkFunctionAddress: checkFunctionAddress
        )
    }

    // MARK: - Shape 1: cmp + csel between two metadata addresses

    private static func analyzeConditionalSelect(
        after availabilityCallIndex: Int,
        in instructions: [ThunkInstruction],
        availabilityCheck: PlatformAvailabilityCheck?
    ) -> AccessorThunkProgram? {
        var tracker = ThunkRegisterTracker()
        for instruction in instructions[0 ... availabilityCallIndex] {
            tracker.apply(instruction.operation)
        }

        for instruction in instructions[(availabilityCallIndex + 1)...] {
            guard case .conditionalSelect(_, let whenConditionHolds, let otherwise, let condition) = instruction.operation else {
                tracker.apply(instruction.operation)
                continue
            }
            guard let addressWhenConditionHolds = tracker.address(of: whenConditionHolds),
                  let addressOtherwise = tracker.address(of: otherwise)
            else { return nil }

            // The comparison is `cmp w0, #0` on the check's own result, so the
            // `eq` branch is the one where the check returned **false** — i.e.
            // the platform is *older* than the tested version.
            let conditionWhenHolds: ThunkCandidate.Condition
            switch condition {
            case .equal:
                conditionWhenHolds = .availabilityNotSatisfied
            case .notEqual:
                conditionWhenHolds = .availabilitySatisfied
            case .unsupported:
                return AccessorThunkProgram(
                    availabilityCheck: availabilityCheck,
                    candidates: [],
                    limitations: [.unsupportedConditionCode]
                )
            }
            // The satisfied branch comes first, so a caller that wants the one
            // answer today's OS gives can take `candidates.first` without
            // re-deriving the condition.
            let satisfiedAddress = conditionWhenHolds == .availabilitySatisfied ? addressWhenConditionHolds : addressOtherwise
            let notSatisfiedAddress = conditionWhenHolds == .availabilitySatisfied ? addressOtherwise : addressWhenConditionHolds

            return AccessorThunkProgram(
                availabilityCheck: availabilityCheck,
                candidates: [
                    ThunkCandidate(reference: .metadata(address: satisfiedAddress), condition: .availabilitySatisfied),
                    ThunkCandidate(reference: .metadata(address: notSatisfiedAddress), condition: .availabilityNotSatisfied),
                ],
                limitations: []
            )
        }
        return nil
    }

    // MARK: - Shape 2: cbz splitting into two single-lookup branches

    private static func analyzeBranchSplit(
        after availabilityCallIndex: Int,
        in instructions: [ThunkInstruction],
        availabilityCheck: PlatformAvailabilityCheck?
    ) -> AccessorThunkProgram? {
        var splitIndex: Int?
        var branchTarget: UInt64?
        var conditionWhenBranchTaken: ThunkCandidate.Condition?

        for index in (availabilityCallIndex + 1) ..< instructions.count {
            switch instructions[index].operation {
            case .branchIfZero(_, let target):
                // Branch taken when the check returned false.
                splitIndex = index
                branchTarget = target
                conditionWhenBranchTaken = .availabilityNotSatisfied
            case .branchIfNotZero(_, let target):
                splitIndex = index
                branchTarget = target
                conditionWhenBranchTaken = .availabilitySatisfied
            default:
                continue
            }
            break
        }
        guard let splitIndex, let branchTarget, let conditionWhenBranchTaken else { return nil }

        let conditionWhenFallingThrough: ThunkCandidate.Condition = conditionWhenBranchTaken == .availabilitySatisfied
            ? .availabilityNotSatisfied
            : .availabilitySatisfied

        let fallThroughRange = instructions[(splitIndex + 1)...].prefix { $0.address < branchTarget }
        let branchTakenRange = instructions[(splitIndex + 1)...].drop { $0.address < branchTarget }

        var candidates: [ThunkCandidate] = []
        var limitations: [ThunkAnalysisLimitation] = []
        for (branchInstructions, condition) in [
            (Array(fallThroughRange), conditionWhenFallingThrough),
            (Array(branchTakenRange), conditionWhenBranchTaken),
        ] {
            let callTargets = branchInstructions.compactMap { instruction -> UInt64? in
                guard case .call(let target) = instruction.operation else { return nil }
                return target
            }
            guard callTargets.count == 1 else {
                limitations.append(.branchIsNotASingleLookup(condition: condition, callCount: callTargets.count))
                continue
            }
            candidates.append(ThunkCandidate(reference: .metadataAccessor(address: callTargets[0]), condition: condition))
        }
        return AccessorThunkProgram(
            availabilityCheck: availabilityCheck,
            candidates: candidates,
            limitations: limitations
        )
    }
}

#endif
