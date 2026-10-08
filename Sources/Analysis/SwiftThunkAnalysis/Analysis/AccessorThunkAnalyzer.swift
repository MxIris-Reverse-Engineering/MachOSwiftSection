import Foundation

/// Reads a decoded thunk and says what it computes.
///
/// Works purely on ``ThunkInstruction`` values plus a
/// ``ThunkEvaluationEnvironment``, so it is exercised from synthesized
/// sequences with no binary and no disassembler in the way.
///
/// ## The shapes, as measured
///
/// The three thunks found in SwiftUI (macOS 26 shared cache) all start the
/// same way — four immediates into `w0`–`w3`, then a call to
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
/// A kind-9 *field record*'s thunk has no version check at all (the fixture's
/// noncopyable fields, `SwiftUI.Drag.LazyItem<A>.state`): it tests a
/// runtime-capability flag, or probes a cache and builds the type on a miss.
///
/// All of them are read the same way, by ``ThunkTypeEvaluator``: the thunk
/// is run symbolically twice, once assuming every conditional it cannot
/// decide is false and once assuming it is true. With a version check the
/// two runs are the two arms of `if #available`, and the instruction the
/// policy decided says which run is which; without one, the first run that
/// leaves with a type is the answer (a capability flag is decided by the
/// evaluator itself — the runtime has the capability — and a cache probe's
/// warm arm returns something unnameable, so the cold arm wins).
///
/// What the evaluator cannot name it does not guess at. A branch of a
/// version check that evaluates to nothing falls back to the *single-lookup*
/// reading — the run made exactly one call after the branch and returned
/// straight after it, so that call's callee is the answer — and otherwise
/// is reported as
/// ``ThunkAnalysisLimitation/branchIsNotASingleLookup(condition:callCount:)``
/// with no candidate. The rule is stated over the **whole path the arm
/// runs**, join point and shared tail included, and a tail call counts as a
/// call: the first version sliced the arm at the join point, so a thunk
/// whose two arms each look one type up and then jointly hand it to
/// `ModifiedContent`'s accessor with a tail `b` read as two single lookups
/// and printed `_TaskModifier2` for a `Body` that is really
/// `ModifiedContent<_ViewModifier_Content<…>, _TaskModifier2>` (measured on
/// iOS 26.5 simulator SwiftUI, where the tail call goes through a GOT bind
/// the evaluator could not name). Naming an intermediate call's result
/// produces a real, fully-qualified, wrong type — the exact failure mode the
/// `.children` bug in `Node+OpaqueType.swift` had, and the one worth avoiding
/// twice.
public enum AccessorThunkAnalyzer {
    public static func analyze(
        instructions: [ThunkInstruction],
        environment: any ThunkEvaluationEnvironment = EmptyThunkEvaluationEnvironment()
    ) -> AccessorThunkProgram {
        let availabilityCallIndex = indexOfAvailabilityCheckCall(in: instructions)
        let availabilityCheck = availabilityCallIndex.flatMap { self.availabilityCheck(at: $0, in: instructions) }

        // The availability check is the one call the evaluator must not
        // follow into: its result has to stay unknown for the conditional
        // after it to be the policy's to decide, both ways.
        var callTargetsLeftOpaque: Set<UInt64> = []
        if let availabilityCallIndex, case .call(let checkFunctionAddress) = instructions[availabilityCallIndex].operation {
            callTargetsLeftOpaque.insert(checkFunctionAddress)
        }
        var conditionFalseRun = ThunkTypeEvaluator(environment: environment, instructions: instructions, callTargetsLeftOpaque: callTargetsLeftOpaque)
        let conditionFalse = conditionFalseRun.run(policy: .assumeConditionFalse)
        var conditionTrueRun = ThunkTypeEvaluator(environment: environment, instructions: instructions, callTargetsLeftOpaque: callTargetsLeftOpaque)
        let conditionTrue = conditionTrueRun.run(policy: .assumeConditionTrue)

        guard let availabilityCallIndex else {
            return unconditionalProgram(conditionFalse: conditionFalse, conditionTrue: conditionTrue)
        }
        return availabilityProgram(
            availabilityCheck: availabilityCheck,
            availabilityCallIndex: availabilityCallIndex,
            conditionFalse: conditionFalse,
            conditionTrue: conditionTrue,
            in: instructions
        )
    }

    // MARK: - No version check

    private static func unconditionalProgram(
        conditionFalse: ThunkTypeEvaluator.Outcome,
        conditionTrue: ThunkTypeEvaluator.Outcome
    ) -> AccessorThunkProgram {
        for outcome in [conditionFalse, conditionTrue] {
            guard let expression = outcome.result else { continue }
            return AccessorThunkProgram(
                availabilityCheck: nil,
                candidates: [ThunkCandidate(reference: reference(for: expression), condition: .unconditional)],
                limitations: outcome.limitations
            )
        }
        return AccessorThunkProgram(
            availabilityCheck: nil,
            candidates: [],
            limitations: [.noRecognizedShape] + conditionFalse.limitations
        )
    }

    // MARK: - A version check

    private static func availabilityProgram(
        availabilityCheck: PlatformAvailabilityCheck?,
        availabilityCallIndex: Int,
        conditionFalse: ThunkTypeEvaluator.Outcome,
        conditionTrue: ThunkTypeEvaluator.Outcome,
        in instructions: [ThunkInstruction]
    ) -> AccessorThunkProgram {
        var limitations: [ThunkAnalysisLimitation] = []
        for limitation in conditionFalse.limitations + conditionTrue.limitations where !limitations.contains(limitation) {
            limitations.append(limitation)
        }
        guard limitations.isEmpty else {
            return AccessorThunkProgram(availabilityCheck: availabilityCheck, candidates: [], limitations: limitations)
        }
        // The check's result lands in `x0`, unknown to the evaluator, so the
        // first conditional it had to decide is the one that reads it.
        guard let decidedIndex = conditionFalse.decidedInstructionIndex ?? conditionTrue.decidedInstructionIndex,
              decidedIndex > availabilityCallIndex
        else {
            return AccessorThunkProgram(availabilityCheck: availabilityCheck, candidates: [], limitations: [.selectionNotRecognized])
        }

        // Which run is the satisfied arm. The comparison is against zero on
        // the check's own result, so "condition true" means the check
        // returned **false** for `cbz` and `csel … eq`, and **true** for
        // `cbnz` and `csel … ne`. Getting this backwards would attribute
        // each type to the wrong OS version — an error no amount of reading
        // the output would reveal, since both answers are real types.
        let conditionTrueIsSatisfied: Bool
        let isBranchSplit: Bool
        switch instructions[decidedIndex].operation {
        case .branchIfZero: (conditionTrueIsSatisfied, isBranchSplit) = (false, true)
        case .branchIfNotZero: (conditionTrueIsSatisfied, isBranchSplit) = (true, true)
        case .conditionalSelect(_, _, _, .equal): (conditionTrueIsSatisfied, isBranchSplit) = (false, false)
        case .conditionalSelect(_, _, _, .notEqual): (conditionTrueIsSatisfied, isBranchSplit) = (true, false)
        default:
            return AccessorThunkProgram(availabilityCheck: availabilityCheck, candidates: [], limitations: [.selectionNotRecognized])
        }
        let satisfiedOutcome = conditionTrueIsSatisfied ? conditionTrue : conditionFalse
        let notSatisfiedOutcome = conditionTrueIsSatisfied ? conditionFalse : conditionTrue

        var candidates: [ThunkCandidate] = []
        var fallbackLimitations: [ThunkAnalysisLimitation] = []
        // The satisfied branch comes first, so a caller that wants the one
        // answer today's OS gives can take `candidates.first` without
        // re-deriving the condition.
        for (outcome, condition) in [
            (satisfiedOutcome, ThunkCandidate.Condition.availabilitySatisfied),
            (notSatisfiedOutcome, ThunkCandidate.Condition.availabilityNotSatisfied),
        ] {
            if let expression = outcome.result {
                candidates.append(ThunkCandidate(reference: reference(for: expression), condition: condition))
                continue
            }
            // The single-lookup reading of that arm: the run made exactly one
            // call after the branch — join point and shared tail included, a
            // tail call counting as a call — to a static target, and left
            // through `ret` right after, so the callee's identity is the
            // type (an accessor the environment does not know is still an
            // accessor). A `csel` has no arms to read this way, and a call
            // through a register has no target to name.
            guard isBranchSplit else {
                fallbackLimitations.append(.selectionNotRecognized)
                continue
            }
            let armCallSites = outcome.callSites.filter { $0.instructionIndex > decidedIndex }
            guard armCallSites.count == 1, let target = armCallSites[0].target, outcome.leftThroughReturn else {
                fallbackLimitations.append(.branchIsNotASingleLookup(condition: condition, callCount: armCallSites.count))
                continue
            }
            candidates.append(ThunkCandidate(reference: .metadataAccessor(address: target), condition: condition))
        }
        var uniqueLimitations: [ThunkAnalysisLimitation] = []
        for limitation in fallbackLimitations where !uniqueLimitations.contains(limitation) {
            uniqueLimitations.append(limitation)
        }
        return AccessorThunkProgram(availabilityCheck: availabilityCheck, candidates: candidates, limitations: uniqueLimitations)
    }

    /// A constant metadata address is reported as the `.metadata` reference
    /// the first landing introduced; everything the evaluator built is
    /// `.constructed`.
    private static func reference(for expression: ThunkTypeExpression) -> ThunkCandidate.Reference {
        if case .constantMetadata(let address) = expression { return .metadata(address: address) }
        return .constructed(expression)
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
}
