import Foundation
import Testing
@testable import SwiftThunkAnalysis

/// The shape recognizer's contract, driven from synthesized instruction
/// sequences.
///
/// Synthesized rather than read out of a framework on purpose: the real thunks
/// move with every OS build, and what needs pinning is how a *shape* is read,
/// not what SwiftUI happened to contain on one machine. The sequences below
/// are transcriptions of the three shapes measured on the macOS 26 shared
/// cache — see the evolution proposal's research section for the disassembly
/// they came from.
@Suite
struct AccessorThunkAnalyzerTests {
    // MARK: - Builders

    private func instruction(_ operation: ThunkOperation, at address: UInt64, mnemonic: String = "test") -> ThunkInstruction {
        ThunkInstruction(address: address, operation: operation, mnemonic: mnemonic)
    }

    private func register(_ number: Int) -> ThunkRegister { ThunkRegister(number: number) }

    /// The prologue every measured thunk shares: four immediates into `w0`–`w3`
    /// followed by the call to `__isPlatformVersionAtLeast`.
    private func availabilityCheckInstructions(
        platform: Int64 = 1,
        major: Int64 = 26,
        minor: Int64 = 0,
        patch: Int64 = 0,
        checkFunctionAddress: UInt64 = 0x1B67570E4,
        startingAt startAddress: UInt64
    ) -> [ThunkInstruction] {
        [
            instruction(.moveImmediate(destination: register(0), value: platform), at: startAddress),
            instruction(.moveImmediate(destination: register(1), value: major), at: startAddress + 4),
            instruction(.moveImmediate(destination: register(2), value: minor), at: startAddress + 8),
            instruction(.moveImmediate(destination: register(3), value: patch), at: startAddress + 12),
            instruction(.call(target: checkFunctionAddress), at: startAddress + 16),
        ]
    }

    // MARK: - Shape 1: cmp + csel

    /// The one accessor the `csel` shape tail-calls with its selection.
    private static let modifiedContentAccessor: UInt64 = 0x1B6DD4A68

    /// Knows that accessor and nothing else.
    private struct ConditionalSelectEnvironment: ThunkEvaluationEnvironment {
        func callee(at address: UInt64) -> ThunkCallee {
            address == modifiedContentAccessor ? .metadataAccessor(address: address, argumentSlots: [.type, .type]) : .unknown
        }

        func pointer(at address: UInt64) -> UInt64? { nil }
        func slotSymbolName(at address: UInt64) -> String? { nil }
    }

    /// `SwiftUI.ResolvedMenuStyle.Body`'s shape: two metadata addresses
    /// materialized by `adrp` / `add`, selected with `csel … eq` after
    /// `cmp w0, #0`, and handed — with the thunk's first argument — to
    /// `ModifiedContent`'s accessor in a tail call. The first landing read
    /// the two `csel` operands as the whole answer and so dropped the
    /// `ModifiedContent<…>` around them; the tail call is the answer.
    private func conditionalSelectThunk(condition: ThunkCondition = .equal) -> [ThunkInstruction] {
        var instructions = [instruction(.loadFromMemory(destination: register(19), base: register(0), displacement: 0), at: 0x0FFC)]
        instructions += availabilityCheckInstructions(startingAt: 0x1000)
        instructions += [
            instruction(.materializePageAddress(destination: register(8), pageBaseAddress: 0x1F22C5000), at: 0x1014),
            instruction(.addImmediate(destination: register(8), source: register(8), addend: 0x810), at: 0x1018),
            instruction(.materializePageAddress(destination: register(9), pageBaseAddress: 0x1F22C5000), at: 0x101C),
            instruction(.addImmediate(destination: register(9), source: register(9), addend: 0x888), at: 0x1020),
            instruction(.compareImmediate(register: register(0), value: 0), at: 0x1024),
            instruction(
                .conditionalSelect(
                    destination: register(2),
                    whenConditionHolds: register(9),
                    otherwise: register(8),
                    condition: condition
                ),
                at: 0x1028
            ),
            instruction(.moveRegister(destination: register(1), source: register(19)), at: 0x102C),
            instruction(.moveImmediate(destination: register(0), value: 0), at: 0x1030),
            instruction(.branch(target: Self.modifiedContentAccessor), at: 0x1034),
        ]
        return instructions
    }

    private func modifiedContent(around selected: UInt64) -> ThunkCandidate.Reference {
        .constructed(.bound(
            accessorAddress: Self.modifiedContentAccessor,
            typeArguments: [.argument(index: 0), .constantMetadata(address: selected)]
        ))
    }

    private func analyzeConditionalSelectThunk(condition: ThunkCondition = .equal) -> AccessorThunkProgram {
        AccessorThunkAnalyzer.analyze(instructions: conditionalSelectThunk(condition: condition), environment: ConditionalSelectEnvironment())
    }

    @Test func readsTheVersionTheThunkChecks() throws {
        let program = analyzeConditionalSelectThunk()
        let check = try #require(program.availabilityCheck)
        #expect(check.platform == 1)
        #expect(check.major == 26)
        #expect(check.minor == 0)
        #expect(check.patch == 0)
        #expect(check.checkFunctionAddress == 0x1B67570E4)
    }

    /// The `eq` branch is the one where the check returned **false**: the
    /// comparison is against zero on the check's own result. Getting this
    /// backwards would attribute each type to the wrong OS version — an error
    /// no amount of reading the output would reveal, since both answers are
    /// real types.
    @Test func attributesTheEqualBranchToTheOlderPlatform() throws {
        let program = analyzeConditionalSelectThunk()
        #expect(program.limitations.isEmpty)
        #expect(program.candidates.count == 2)

        let satisfied = try #require(program.candidates.first { $0.condition == .availabilitySatisfied })
        let notSatisfied = try #require(program.candidates.first { $0.condition == .availabilityNotSatisfied })
        // `csel x2, x9, x8, eq` — x9 when equal (check returned false), x8 otherwise.
        #expect(satisfied.reference == modifiedContent(around: 0x1F22C5810))
        #expect(notSatisfied.reference == modifiedContent(around: 0x1F22C5888))
    }

    /// With `ne` the roles swap; the analysis must follow the condition code
    /// rather than the operand order.
    @Test func swapsTheBranchesForNotEqual() throws {
        let program = analyzeConditionalSelectThunk(condition: .notEqual)
        let satisfied = try #require(program.candidates.first { $0.condition == .availabilitySatisfied })
        #expect(satisfied.reference == modifiedContent(around: 0x1F22C5888))
    }

    /// A condition the decoder does not model must produce no candidates at
    /// all — a coin flip between two real types is worse than a placeholder.
    @Test func refusesToGuessAnUnmodelledCondition() throws {
        let program = analyzeConditionalSelectThunk(condition: .unsupported)
        #expect(program.candidates.isEmpty)
        #expect(program.limitations == [.unsupportedConditionCode])
    }

    /// The satisfied branch is first, so a caller wanting "what this OS does"
    /// can take `candidates.first`.
    @Test func ordersTheSatisfiedBranchFirst() throws {
        let program = analyzeConditionalSelectThunk()
        #expect(program.candidates.first?.condition == .availabilitySatisfied)
    }

    /// The tail call's callee is what names the type; a `csel` whose
    /// selection flows into a callee the environment cannot name yields
    /// nothing — the first landing's reading, which reported the two
    /// selected metadata records themselves, printed `ResolvedMenuStyle.Body`
    /// without the `ModifiedContent<…>` the thunk actually returns.
    @Test func doesNotReportTheSelectionWhenTheTailCallIsUnknown() throws {
        let program = AccessorThunkAnalyzer.analyze(instructions: conditionalSelectThunk())
        #expect(program.candidates.isEmpty)
        #expect(program.limitations == [.selectionNotRecognized])
    }

    // MARK: - Shape 2: cbz splitting into two single-lookup branches

    /// `SwiftUI.OnModifierKeysChangedModifier.Body`'s shape: `cbz w0` past the
    /// satisfied branch, each branch calling one metadata accessor.
    private func branchSplitThunk(unsatisfiedBranchCallCount: Int = 1) -> [ThunkInstruction] {
        var instructions = availabilityCheckInstructions(major: 26, minor: 4, startingAt: 0x2000)
        let unsatisfiedBranchAddress: UInt64 = 0x2028
        instructions += [
            instruction(.branchIfZero(register: register(0), target: unsatisfiedBranchAddress), at: 0x2014),
            // Satisfied branch.
            instruction(.moveImmediate(destination: register(0), value: 255), at: 0x2018),
            instruction(.call(target: 0x1B6D2F858), at: 0x201C),
            instruction(.branch(target: 0x2030), at: 0x2020),
            instruction(.unmodelled, at: 0x2024),
            // Unsatisfied branch.
            instruction(.moveImmediate(destination: register(0), value: 255), at: unsatisfiedBranchAddress),
        ]
        var nextAddress = unsatisfiedBranchAddress + 4
        for callIndex in 0 ..< unsatisfiedBranchCallCount {
            instructions.append(instruction(.call(target: 0x1B6D2F838 + UInt64(callIndex * 0x20)), at: nextAddress))
            nextAddress += 4
        }
        instructions.append(instruction(.returnFromFunction, at: nextAddress))
        return instructions
    }

    @Test func readsBothBranchesOfASplitThunk() throws {
        let program = AccessorThunkAnalyzer.analyze(instructions: branchSplitThunk())
        #expect(program.limitations.isEmpty)
        #expect(program.availabilityCheck?.minor == 4)

        let satisfied = try #require(program.candidates.first { $0.condition == .availabilitySatisfied })
        let notSatisfied = try #require(program.candidates.first { $0.condition == .availabilityNotSatisfied })
        // `cbz` jumps when the check returned false, so the fall-through is the
        // satisfied branch.
        #expect(satisfied.reference == .metadataAccessor(address: 0x1B6D2F858))
        #expect(notSatisfied.reference == .metadataAccessor(address: 0x1B6D2F838))
    }

    /// `SwiftUI.DefinesSearchCompletionModifier.Body`'s shape: one branch
    /// *builds* its type through a chain of calls instead of looking one up.
    ///
    /// That branch must contribute no candidate. Taking its first call would
    /// name an intermediate — a real, fully-qualified, wrong type, which is the
    /// failure mode that made the opaque-argument bug invisible for so long.
    /// The other branch still resolves, so half an answer is not thrown away.
    @Test func refusesABranchThatBuildsRatherThanLooksUp() throws {
        let program = AccessorThunkAnalyzer.analyze(instructions: branchSplitThunk(unsatisfiedBranchCallCount: 4))

        #expect(program.candidates.count == 1)
        #expect(program.candidates.first?.condition == .availabilitySatisfied)
        #expect(program.limitations == [.branchIsNotASingleLookup(condition: .availabilityNotSatisfied, callCount: 4)])
    }

    // MARK: - Shapes outside the vocabulary

    @Test func reportsNoRecognizedShapeWithoutAVersionCheck() throws {
        let instructions = [
            instruction(.materializePageAddress(destination: register(8), pageBaseAddress: 0x1F22C5000), at: 0x3000),
            instruction(.addImmediate(destination: register(8), source: register(8), addend: 0x10), at: 0x3004),
            instruction(.returnFromFunction, at: 0x3008),
        ]
        let program = AccessorThunkAnalyzer.analyze(instructions: instructions)
        #expect(program.availabilityCheck == nil)
        #expect(program.candidates.isEmpty)
        #expect(program.limitations == [.noRecognizedShape])
    }

    /// A version check whose selection is not one of the two recognized shapes
    /// keeps the check — it is a real fact about the declaration — and reports
    /// the rest as unread.
    @Test func keepsTheVersionCheckWhenTheSelectionIsUnreadable() throws {
        var instructions = availabilityCheckInstructions(startingAt: 0x4000)
        instructions += [
            instruction(.unmodelled, at: 0x4014),
            instruction(.returnFromFunction, at: 0x4018),
        ]
        let program = AccessorThunkAnalyzer.analyze(instructions: instructions)
        #expect(program.availabilityCheck?.major == 26)
        #expect(program.candidates.isEmpty)
        #expect(program.limitations == [.selectionNotRecognized])
    }

    /// A four-immediates-then-call shape only counts when the immediates land
    /// in argument order; a Swift metadata accessor's own prologue must not be
    /// mistaken for one.
    @Test func doesNotTakeArbitraryImmediatesForAVersionCheck() throws {
        let instructions = [
            instruction(.moveImmediate(destination: register(8), value: 1), at: 0x5000),
            instruction(.moveImmediate(destination: register(9), value: 26), at: 0x5004),
            instruction(.moveImmediate(destination: register(10), value: 0), at: 0x5008),
            instruction(.moveImmediate(destination: register(11), value: 0), at: 0x500C),
            instruction(.call(target: 0x1B67570E4), at: 0x5010),
            instruction(.returnFromFunction, at: 0x5014),
        ]
        let program = AccessorThunkAnalyzer.analyze(instructions: instructions)
        #expect(program.availabilityCheck == nil)
        #expect(program.limitations == [.noRecognizedShape])
    }

    // MARK: - Register tracking

    /// A call clobbers the caller-saved registers, so an address materialized
    /// before one must not be read back after it.
    @Test func forgetsCallerSavedRegistersAcrossACall() throws {
        var tracker = ThunkRegisterTracker()
        tracker.apply(.materializePageAddress(destination: register(8), pageBaseAddress: 0x1000))
        tracker.apply(.materializePageAddress(destination: register(19), pageBaseAddress: 0x2000))
        #expect(tracker.address(of: register(8)) == 0x1000)

        tracker.apply(.call(target: 0x3000))
        #expect(tracker.address(of: register(8)) == nil, "x8 is caller-saved")
        #expect(tracker.address(of: register(19)) == 0x2000, "x19 is callee-saved")
    }

    /// `add` completes an address when the base is one and computes an integer
    /// when it is not — conflating them would let a counter be read as a
    /// candidate address.
    @Test func keepsAddressesAndIntegersApart() throws {
        var tracker = ThunkRegisterTracker()
        tracker.apply(.materializePageAddress(destination: register(8), pageBaseAddress: 0x1F22C5000))
        tracker.apply(.addImmediate(destination: register(8), source: register(8), addend: 0x810))
        #expect(tracker.address(of: register(8)) == 0x1F22C5810)

        tracker.apply(.moveImmediate(destination: register(9), value: 16))
        tracker.apply(.addImmediate(destination: register(9), source: register(9), addend: 8))
        #expect(tracker.address(of: register(9)) == nil)
        #expect(tracker.immediate(of: register(9)) == 24)
    }

    /// A load's value lives in the binary, not the instruction, so the
    /// destination becomes unknown rather than keeping a stale address.
    @Test func forgetsARegisterLoadedFromMemory() throws {
        var tracker = ThunkRegisterTracker()
        tracker.apply(.materializePageAddress(destination: register(16), pageBaseAddress: 0x1F22C5000))
        tracker.apply(.loadFromMemory(destination: register(16), base: register(16), displacement: 0x3D0))
        #expect(tracker.address(of: register(16)) == nil)
    }
}
