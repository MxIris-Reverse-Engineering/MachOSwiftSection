import Foundation
import Testing
@testable import SwiftThunkAnalysis

/// A tabled environment: call targets, pointer words, bound slots and
/// decodable functions the test declares.
private struct TabledEnvironment: ThunkEvaluationEnvironment {
    var callees: [UInt64: ThunkCallee] = [:]
    var pointers: [UInt64: UInt64] = [:]
    var slotSymbolNames: [UInt64: String] = [:]
    var boundCalleesBySlot: [UInt64: ThunkCallee] = [:]
    var functionsByAddress: [UInt64: [ThunkInstruction]] = [:]

    func callee(at address: UInt64) -> ThunkCallee { callees[address] ?? .unknown }
    func pointer(at address: UInt64) -> UInt64? { pointers[address] }
    func slotSymbolName(at address: UInt64) -> String? { slotSymbolNames[address] }
    func callee(boundInSlotAt slotAddress: UInt64) -> ThunkCallee { boundCalleesBySlot[slotAddress] ?? .unknown }
    func instructions(ofFunctionAt address: UInt64) -> [ThunkInstruction]? { functionsByAddress[address] }
}

/// The symbolic evaluator's contract, from synthesized sequences that
/// transcribe the type-construction thunks measured in SwiftUI (macOS 26).
///
/// Synthesized so the *reading rules* are pinned independently of what one
/// OS build happens to contain: how arguments come out of the buffer, how an
/// accessor's arguments are gathered from registers or the stack, what a
/// tail call means, and that an unknown callee poisons only what depends on
/// it.
@Suite
struct ThunkTypeEvaluatorTests {
    private static let availabilityCheckAddress: UInt64 = 0x1000_0000
    private static let tagTraitAccessor: UInt64 = 0x2000_0000        // one type parameter + one witness table
    private static let modifiedContentAccessor: UInt64 = 0x2000_0100 // two type parameters + two witness tables
    private static let witnessTableLookup: UInt64 = 0x2000_0200
    private static let fourArgumentAccessor: UInt64 = 0x2000_0300
    private static let stateAccessor: UInt64 = 0x2000_0400
    private static let mutexAccessor: UInt64 = 0x2000_0500
    private static let mangledNameInstantiation: UInt64 = 0x2000_0600
    private static let specializedMutexAccessor: UInt64 = 0x2000_0700
    private static let specializedMutexAccessorSymbol = "_$s15Synchronization5MutexVyShySSGGMa"

    // The merged-accessor shape (iOS 26.5 simulator SwiftUICore,
    // `PlatformAccessibilitySettingsDefinition.cache`): a GOT slot binding
    // to `Mutex`'s accessor in libswiftSynchronization, a merged body the
    // thunk calls with the slot's value in `x3`, the lazy cache variable
    // and the argument's metadata.
    private static let gotPage: UInt64 = 0xD13000
    private static let mutexAccessorSlot: UInt64 = 0xD13000 + 0xBF8
    private static let mergedBody: UInt64 = 0x18DC4
    private static let cacheVariable: UInt64 = 0xDF0D68
    private static let storageMetadata: UInt64 = 0xD57DE8

    private var environment: TabledEnvironment {
        TabledEnvironment(callees: [
            Self.specializedMutexAccessor: .concreteTypeAccessor(symbolName: Self.specializedMutexAccessorSymbol),
            Self.availabilityCheckAddress: .availabilityCheck,
            Self.tagTraitAccessor: .metadataAccessor(address: Self.tagTraitAccessor, argumentSlots: [.type, .witnessTable]),
            // `ModifiedContent<Content, Modifier>` itself has no requirements (its
            // `View` conformance is conditional), so its accessor takes the two
            // type arguments only — as SwiftUI's thunk passes them, in `x1` / `x2`.
            Self.modifiedContentAccessor: .metadataAccessor(address: Self.modifiedContentAccessor, argumentSlots: [.type, .type]),
            Self.witnessTableLookup: .witnessTableLookup,
            Self.fourArgumentAccessor: .metadataAccessor(address: Self.fourArgumentAccessor, argumentSlots: [.type, .type, .type, .type]),
            Self.stateAccessor: .metadataAccessor(address: Self.stateAccessor, argumentSlots: [.type]),
            Self.mutexAccessor: .metadataAccessor(address: Self.mutexAccessor, argumentSlots: [.type]),
            Self.mangledNameInstantiation: .mangledNameInstantiation,
        ])
    }

    private func register(_ number: Int) -> ThunkRegister { ThunkRegister(number: number) }

    /// `_$sypSgMaTm` as SwiftUICore carries it, transcribed: probe the cache
    /// `x1` points at, return the cached word if set, else call the accessor
    /// in `x3` with `(x0, x2)` and store the result.
    private var mergedBodyInstructions: [ThunkInstruction] {
        let coldPath: UInt64 = Self.mergedBody + 5 * 4
        let epilogue: UInt64 = Self.mergedBody + 14 * 4
        return sequence([
            .moveRegister(destination: register(8), source: register(0)),
            .loadFromMemory(destination: register(0), base: register(1), displacement: 0),
            .branchIfZero(register: register(0), target: coldPath),
            .moveImmediate(destination: register(1), value: 0),
            .returnFromFunction,
            // cold path
            .storePairToMemory(first: register(20), second: register(19), base: .stackPointer, displacement: -0x20, adjustsBase: true),
            .storePairToMemory(first: register(29), second: register(30), base: .stackPointer, displacement: 0x10, adjustsBase: false),
            .addImmediate(destination: register(29), source: .stackPointer, addend: 0x10),
            .moveRegister(destination: register(19), source: register(1)),
            .moveRegister(destination: register(0), source: register(8)),
            .moveRegister(destination: register(1), source: register(2)),
            .indirectCall(register: register(3)),
            .branchIfNotZero(register: register(1), target: epilogue),
            .unmodelled, // stlr x0, [x19]
            // epilogue
            .loadPairFromMemory(first: register(29), second: register(30), base: .stackPointer, displacement: 0x10, adjustsBase: false),
            .loadPairFromMemory(first: register(20), second: register(19), base: .stackPointer, displacement: 0x20, adjustsBase: true),
            .returnFromFunction,
        ], startingAt: Self.mergedBody)
    }

    /// The thunk that calls it, after the capability check.
    private var mergedAccessorThunk: [ThunkInstruction] {
        sequence([
            .storePairToMemory(first: register(29), second: register(30), base: .stackPointer, displacement: -0x10, adjustsBase: true),
            .moveRegister(destination: register(29), source: .stackPointer),
            .materializePageAddress(destination: register(1), pageBaseAddress: Self.cacheVariable & ~0xFFF),
            .addImmediate(destination: register(1), source: register(1), addend: Int64(Self.cacheVariable & 0xFFF)),
            .materializePageAddress(destination: register(2), pageBaseAddress: Self.storageMetadata & ~0xFFF),
            .addImmediate(destination: register(2), source: register(2), addend: Int64(Self.storageMetadata & 0xFFF)),
            .materializePageAddress(destination: register(3), pageBaseAddress: Self.gotPage),
            .loadFromMemory(destination: register(3), base: register(3), displacement: Int64(Self.mutexAccessorSlot - Self.gotPage)),
            .moveImmediate(destination: register(0), value: 0),
            .call(target: Self.mergedBody),
            .loadPairFromMemory(first: register(29), second: register(30), base: .stackPointer, displacement: 0x10, adjustsBase: true),
            .returnFromFunction,
        ])
    }

    private var mergedAccessorEnvironment: TabledEnvironment {
        var environment = environment
        environment.boundCalleesBySlot[Self.mutexAccessorSlot] = .metadataAccessor(address: Self.mutexAccessorSlot, argumentSlots: [.type])
        environment.functionsByAddress[Self.mergedBody] = mergedBodyInstructions
        return environment
    }

    /// One run over `instructions`, falling through every undecidable conditional.
    private func evaluated(_ instructions: [ThunkInstruction]) -> ThunkTypeExpression? {
        var evaluator = ThunkTypeEvaluator(environment: environment, instructions: instructions)
        return evaluator.run(policy: .assumeConditionFalse).result
    }

    private func sequence(_ operations: [ThunkOperation], startingAt startAddress: UInt64 = 0x1000) -> [ThunkInstruction] {
        operations.enumerated().map { index, operation in
            ThunkInstruction(address: startAddress + UInt64(index * 4), operation: operation, mnemonic: "test")
        }
    }

    // MARK: - The measured shape: `DefinesSearchCompletionModifier.Body`

    /// The satisfied branch of the thunk the first landing refused: two
    /// accessor calls, the second a tail call, arguments read out of the
    /// buffer before the version check.
    @Test func readsAnAccessorChainWithArgumentsFromTheBuffer() throws {
        // Addresses are sequential from 0x1000; the split's target is the
        // not-satisfied branch's first instruction, instruction 16.
        let notSatisfiedStart: UInt64 = 0x1000 + 16 * 4
        let instructions = sequence([
            .loadPairFromMemory(first: register(20), second: register(21), base: register(0), displacement: 0, adjustsBase: false),
            .loadFromMemory(destination: register(19), base: register(0), displacement: 24),
            .moveImmediate(destination: register(0), value: 1),
            .moveImmediate(destination: register(1), value: 26),
            .moveImmediate(destination: register(2), value: 0),
            .moveImmediate(destination: register(3), value: 0),
            .call(target: Self.availabilityCheckAddress),
            .branchIfZero(register: register(0), target: notSatisfiedStart),
            // satisfied branch (instructions 8–15): accessor, then a tail call
            .moveImmediate(destination: register(0), value: 255),
            .moveRegister(destination: register(1), source: register(21)),
            .moveRegister(destination: register(2), source: register(19)),
            .call(target: Self.tagTraitAccessor),
            .moveRegister(destination: register(2), source: register(0)),
            .moveImmediate(destination: register(0), value: 0),
            .moveRegister(destination: register(1), source: register(20)),
            .branch(target: Self.modifiedContentAccessor),
            // not-satisfied branch (instructions 16–20): one accessor, returned
            .moveImmediate(destination: register(0), value: 255),
            .moveRegister(destination: register(1), source: register(21)),
            .moveRegister(destination: register(2), source: register(19)),
            .call(target: Self.tagTraitAccessor),
            .returnFromFunction,
        ])

        let program = AccessorThunkAnalyzer.analyze(instructions: instructions, environment: environment)
        #expect(program.limitations.isEmpty, "\(program.limitations)")
        let satisfied = try #require(program.candidates.first { $0.condition == .availabilitySatisfied })
        #expect(satisfied.reference == .constructed(.bound(
            accessorAddress: Self.modifiedContentAccessor,
            typeArguments: [.argument(index: 0), .bound(accessorAddress: Self.tagTraitAccessor, typeArguments: [.argument(index: 1)])]
        )))
        let notSatisfied = try #require(program.candidates.first { $0.condition == .availabilityNotSatisfied })
        #expect(notSatisfied.reference == .constructed(.bound(accessorAddress: Self.tagTraitAccessor, typeArguments: [.argument(index: 1)])))
    }

    // MARK: - Argument passing

    /// More than three key arguments travel in a stack buffer `x1` points at,
    /// built with `str` / `stp` relative to a moved stack pointer.
    @Test func gathersMoreThanThreeArgumentsFromTheStackBuffer() {
        let result = evaluated(sequence([
            .addImmediate(destination: .stackPointer, source: .stackPointer, addend: -48),
            .loadPairFromMemory(first: register(20), second: register(21), base: register(0), displacement: 0, adjustsBase: false),
            .loadPairFromMemory(first: register(22), second: register(23), base: register(0), displacement: 16, adjustsBase: false),
            .storeToMemory(source: register(20), base: .stackPointer, displacement: 8),
            .storePairToMemory(first: register(21), second: register(22), base: .stackPointer, displacement: 16, adjustsBase: false),
            .storeToMemory(source: register(23), base: .stackPointer, displacement: 32),
            .addImmediate(destination: register(1), source: .stackPointer, addend: 8),
            .moveImmediate(destination: register(0), value: 0),
            .call(target: Self.fourArgumentAccessor),
            .addImmediate(destination: .stackPointer, source: .stackPointer, addend: 48),
            .returnFromFunction,
        ]))
        #expect(result == .bound(
            accessorAddress: Self.fourArgumentAccessor,
            typeArguments: [.argument(index: 0), .argument(index: 1), .argument(index: 2), .argument(index: 3)]
        ))
    }

    /// A witness table is gathered by the runtime and skipped by the name.
    @Test func skipsWitnessTableArguments() {
        let result = evaluated(sequence([
            .loadFromMemory(destination: register(20), base: register(0), displacement: 0),
            .materializePageAddress(destination: register(16), pageBaseAddress: 0x3000_0000),
            .loadFromMemory(destination: register(16), base: register(16), displacement: 0x10),
            .moveRegister(destination: register(0), source: register(16)),
            .moveRegister(destination: register(1), source: register(20)),
            .call(target: Self.witnessTableLookup),
            .moveRegister(destination: register(2), source: register(0)),
            .moveImmediate(destination: register(0), value: 0),
            .moveRegister(destination: register(1), source: register(20)),
            .call(target: Self.tagTraitAccessor),
            .returnFromFunction,
        ]))
        #expect(result == .bound(accessorAddress: Self.tagTraitAccessor, typeArguments: [.argument(index: 0)]))
    }

    // MARK: - Refusals

    /// A callee the environment cannot name poisons what depends on it — and
    /// nothing else: the analysis answers `nil`, never an intermediate.
    @Test func anUnknownCalleeYieldsNoType() {
        let result = evaluated(sequence([
            .loadFromMemory(destination: register(20), base: register(0), displacement: 0),
            .moveImmediate(destination: register(0), value: 255),
            .moveRegister(destination: register(1), source: register(20)),
            .call(target: 0xDEAD_0000),
            .moveRegister(destination: register(1), source: register(0)),
            .moveImmediate(destination: register(0), value: 0),
            .call(target: Self.mutexAccessor),
            .returnFromFunction,
        ]))
        #expect(result == nil)
    }

    /// Every `bl`, and every `b` that leaves the function, is a call site;
    /// a `b` inside the function is a jump. How the run left is recorded
    /// next to them, because only after `ret` is `x0` the last call's
    /// result — the shape analyzer's single-lookup fallback needs both facts.
    @Test func recordsEveryCallSiteAndHowTheFunctionLeft() {
        var tailCallingRun = ThunkTypeEvaluator(environment: environment, instructions: sequence([
            .loadFromMemory(destination: register(20), base: register(0), displacement: 0),
            .moveImmediate(destination: register(0), value: 255),
            .moveRegister(destination: register(1), source: register(20)),
            .call(target: Self.stateAccessor),
            .branch(target: 0x1000 + 5 * 4),
            .unmodelled,
            .moveRegister(destination: register(1), source: register(0)),
            .moveImmediate(destination: register(0), value: 0),
            .branch(target: 0xDEAD_0000),
        ]))
        let tailCalling = tailCallingRun.run(policy: .assumeConditionFalse)
        #expect(tailCalling.result == nil)
        #expect(tailCalling.leftThroughReturn == false)
        #expect(tailCalling.callSites == [
            ThunkTypeEvaluator.CallSite(instructionIndex: 3, target: Self.stateAccessor),
            ThunkTypeEvaluator.CallSite(instructionIndex: 8, target: 0xDEAD_0000),
        ])

        var returningRun = ThunkTypeEvaluator(environment: environment, instructions: sequence([
            .loadFromMemory(destination: register(1), base: register(0), displacement: 0),
            .moveImmediate(destination: register(0), value: 0),
            .call(target: Self.mutexAccessor),
            .returnFromFunction,
        ]))
        let returning = returningRun.run(policy: .assumeConditionFalse)
        #expect(returning.result == .bound(accessorAddress: Self.mutexAccessor, typeArguments: [.argument(index: 0)]))
        #expect(returning.leftThroughReturn == true)
        #expect(returning.callSites == [ThunkTypeEvaluator.CallSite(instructionIndex: 2, target: Self.mutexAccessor)])
    }

    /// A lazily specialized accessor takes no arguments; its symbol is the
    /// whole answer (`Mutex<Set<String>>`), carried as the symbol name.
    @Test func aConcreteTypeAccessorIsNamedByItsSymbol() {
        let result = evaluated(sequence([
            .moveImmediate(destination: register(0), value: 0),
            .call(target: Self.specializedMutexAccessor),
            .returnFromFunction,
        ]))
        #expect(result == .namedByAccessorSymbol(symbolName: Self.specializedMutexAccessorSymbol))
    }

    // MARK: - Following a call into a function the environment cannot name

    /// The merged-accessor shape end to end: the bind slot's value travels
    /// in `x3` into a body the environment can only decode, the body's
    /// cache probe is decided by which arm yields a type, and the `blr`
    /// applies the bound accessor to the metadata the caller put in `x2`.
    @Test func followsACallIntoAMergedAccessorBody() throws {
        let program = AccessorThunkAnalyzer.analyze(instructions: mergedAccessorThunk, environment: mergedAccessorEnvironment)
        #expect(program.limitations.isEmpty, "\(program.limitations)")
        let candidate = try #require(program.candidates.first)
        #expect(candidate.condition == .unconditional)
        #expect(candidate.reference == .constructed(.bound(
            accessorAddress: Self.mutexAccessorSlot,
            typeArguments: [.constantMetadata(address: Self.storageMetadata)]
        )))
    }

    /// After a followed call returns, the caller's callee-saved registers
    /// and stack are its own again and the caller-saved ones are gone; the
    /// callee's calls are listed under the instruction that entered it, a
    /// register call with no target.
    @Test func aFollowedCallReturnsLikeAnyOther() {
        var evaluator = ThunkTypeEvaluator(environment: mergedAccessorEnvironment, instructions: mergedAccessorThunk)
        let outcome = evaluator.run(policy: .assumeConditionFalse)
        #expect(outcome.result == .bound(accessorAddress: Self.mutexAccessorSlot, typeArguments: [.constantMetadata(address: Self.storageMetadata)]))
        #expect(outcome.leftThroughReturn == true)
        #expect(outcome.callSites == [
            ThunkTypeEvaluator.CallSite(instructionIndex: 9, target: Self.mergedBody),
            ThunkTypeEvaluator.CallSite(instructionIndex: 9, target: nil),
        ])
        #expect(evaluator.value(of: register(3)) == nil, "x3 is caller-saved")
        #expect(evaluator.value(of: register(8)) == nil, "the callee's own x8 must not leak back")
    }

    /// A call through a register holding nothing the analysis knows is an
    /// unknown call: the result is unknown, never the register's stale value.
    @Test func anIndirectCallThroughAnUnknownRegisterYieldsNoType() {
        let result = evaluated(sequence([
            .loadFromMemory(destination: register(1), base: register(0), displacement: 0),
            .moveImmediate(destination: register(0), value: 0),
            .indirectCall(register: register(3)),
            .returnFromFunction,
        ]))
        #expect(result == nil)
    }

    /// A register holding an address the environment knows a callee at is
    /// called like a `bl` to that address (a cache's rebased GOT slot).
    @Test func anIndirectCallThroughAKnownAddressIsApplied() {
        var environment = environment
        environment.pointers[Self.mutexAccessorSlot] = Self.mutexAccessor
        var evaluator = ThunkTypeEvaluator(environment: environment, instructions: sequence([
            .loadFromMemory(destination: register(1), base: register(0), displacement: 0),
            .materializePageAddress(destination: register(3), pageBaseAddress: Self.gotPage),
            .loadFromMemory(destination: register(3), base: register(3), displacement: Int64(Self.mutexAccessorSlot - Self.gotPage)),
            .moveImmediate(destination: register(0), value: 0),
            .indirectCall(register: register(3)),
            .returnFromFunction,
        ]))
        let outcome = evaluator.run(policy: .assumeConditionFalse)
        #expect(outcome.result == .bound(accessorAddress: Self.mutexAccessor, typeArguments: [.argument(index: 0)]))
    }

    /// A register jump to a known function is a tail call; to nothing known
    /// it leaves with no result — `x0` at that point is the jumped-to
    /// function's argument, not an answer.
    @Test func anIndirectBranchIsATailCallWhenTheRegisterIsKnown() {
        var environment = environment
        environment.boundCalleesBySlot[Self.mutexAccessorSlot] = .metadataAccessor(address: Self.mutexAccessorSlot, argumentSlots: [.type])
        let tailCall = sequence([
            .loadFromMemory(destination: register(1), base: register(0), displacement: 0),
            .materializePageAddress(destination: register(16), pageBaseAddress: Self.gotPage),
            .loadFromMemory(destination: register(16), base: register(16), displacement: Int64(Self.mutexAccessorSlot - Self.gotPage)),
            .moveImmediate(destination: register(0), value: 0),
            .indirectBranch(register: register(16)),
        ])
        var known = ThunkTypeEvaluator(environment: environment, instructions: tailCall)
        let knownOutcome = known.run(policy: .assumeConditionFalse)
        #expect(knownOutcome.result == .bound(accessorAddress: Self.mutexAccessorSlot, typeArguments: [.argument(index: 0)]))
        #expect(knownOutcome.leftThroughReturn == false)

        var unknown = ThunkTypeEvaluator(environment: environment, instructions: sequence([
            .loadFromMemory(destination: register(0), base: register(0), displacement: 0),
            .indirectBranch(register: register(16)),
        ]))
        #expect(unknown.run(policy: .assumeConditionFalse).result == nil)
    }

    /// The availability check is never followed, whatever the environment
    /// could decode at its address: its result must stay unknown so the
    /// conditional after it is the policy's.
    @Test func doesNotFollowTheAvailabilityCheck() throws {
        var environment = mergedAccessorEnvironment
        // If followed, this body would answer `x0 = 0` and decide the split.
        environment.functionsByAddress[Self.availabilityCheckAddress] = sequence([
            .moveImmediate(destination: register(0), value: 0),
            .returnFromFunction,
        ], startingAt: Self.availabilityCheckAddress)
        let notSatisfiedStart: UInt64 = 0x1000 + 9 * 4
        let instructions = sequence([
            .loadFromMemory(destination: register(20), base: register(0), displacement: 0),
            .moveImmediate(destination: register(0), value: 1),
            .moveImmediate(destination: register(1), value: 26),
            .moveImmediate(destination: register(2), value: 0),
            .moveImmediate(destination: register(3), value: 0),
            .call(target: Self.availabilityCheckAddress),
            .branchIfZero(register: register(0), target: notSatisfiedStart),
            .moveImmediate(destination: register(0), value: 255),
            .moveRegister(destination: register(1), source: register(20)),
            // shared by both arms only by accident of layout: the split's
            // target is the accessor call below
            .call(target: Self.stateAccessor),
            .returnFromFunction,
        ])
        let program = AccessorThunkAnalyzer.analyze(instructions: instructions, environment: environment)
        #expect(program.availabilityCheck != nil)
        #expect(program.candidates.count == 2, "\(program.candidates)")
    }

    /// A function already being followed is not entered again, and the
    /// depth is capped: a self-calling body ends with an unknown result
    /// instead of recursing.
    @Test func doesNotFollowARecursiveOrTooDeepCall() {
        var environment = environment
        let selfCalling: UInt64 = 0x9000
        environment.functionsByAddress[selfCalling] = sequence([
            .call(target: selfCalling),
            .returnFromFunction,
        ], startingAt: selfCalling)
        var recursive = ThunkTypeEvaluator(environment: environment, instructions: sequence([
            .loadFromMemory(destination: register(1), base: register(0), displacement: 0),
            .call(target: selfCalling),
            .returnFromFunction,
        ]))
        let recursiveOutcome = recursive.run(policy: .assumeConditionFalse)
        #expect(recursiveOutcome.result == nil)
        #expect(recursiveOutcome.leftThroughReturn == true)
        // The entry call, and the one inner call that was refused.
        #expect(recursiveOutcome.callSites.count == 2)

        // A chain deeper than the cap: 4 nested wrappers around an accessor.
        let chain: [UInt64] = [0xA000, 0xA100, 0xA200, 0xA300]
        for (index, address) in chain.enumerated() {
            let next: ThunkOperation = index + 1 < chain.count ? .call(target: chain[index + 1]) : .call(target: Self.mutexAccessor)
            environment.functionsByAddress[address] = sequence([next, .returnFromFunction], startingAt: address)
        }
        var tooDeep = ThunkTypeEvaluator(environment: environment, instructions: sequence([
            .loadFromMemory(destination: register(1), base: register(0), displacement: 0),
            .moveImmediate(destination: register(0), value: 0),
            .call(target: chain[0]),
            .returnFromFunction,
        ]))
        #expect(tooDeep.run(policy: .assumeConditionFalse).result == nil)
        var deepEnough = ThunkTypeEvaluator(environment: environment, instructions: sequence([
            .loadFromMemory(destination: register(1), base: register(0), displacement: 0),
            .moveImmediate(destination: register(0), value: 0),
            .call(target: chain[1]),
            .returnFromFunction,
        ]))
        #expect(deepEnough.run(policy: .assumeConditionFalse).result == .bound(accessorAddress: Self.mutexAccessor, typeArguments: [.argument(index: 0)]))
    }

    /// A tail `b` to a function the environment can decode is followed the
    /// same way, and how *it* left is how the thunk left.
    @Test func followsATailCallIntoADecodableFunction() {
        var environment = environment
        let wrapper: UInt64 = 0xB000
        environment.functionsByAddress[wrapper] = sequence([
            .moveImmediate(destination: register(0), value: 0),
            .call(target: Self.mutexAccessor),
            .returnFromFunction,
        ], startingAt: wrapper)
        var evaluator = ThunkTypeEvaluator(environment: environment, instructions: sequence([
            .loadFromMemory(destination: register(1), base: register(0), displacement: 0),
            .branch(target: wrapper),
        ]))
        let outcome = evaluator.run(policy: .assumeConditionFalse)
        #expect(outcome.result == .bound(accessorAddress: Self.mutexAccessor, typeArguments: [.argument(index: 0)]))
        #expect(outcome.leftThroughReturn == true)
        #expect(outcome.callSites.map(\.target) == [wrapper, Self.mutexAccessor])
    }

    /// A type argument that could not be named makes the bound type
    /// unnameable rather than partially named.
    @Test func anUnnameableTypeArgumentYieldsNoType() {
        let result = evaluated(sequence([
            .moveImmediate(destination: register(0), value: 0),
            .call(target: Self.mutexAccessor), // x1 never set
            .returnFromFunction,
        ]))
        #expect(result == nil)
    }

    // MARK: - The field-record shape: cached or constructed

    /// `Drag.LazyItem<A>.state`'s thunk: a cache probe whose warm path returns
    /// the cached (unknown) value and whose cold path builds
    /// `Mutex<LazyItem<A>.State>`. Read through the analyzer, which evaluates
    /// the cold path once the warm one answers nothing.
    @Test func readsTheColdPathOfACacheProbe() throws {
        let coldStart: UInt64 = 0x1000 + 5 * 4
        var instructions = sequence([
            .materializePageAddress(destination: register(8), pageBaseAddress: 0x4000_0000),
            .loadFromMemory(destination: register(8), base: register(8), displacement: 0x10),
            .branchIfZero(register: register(8), target: coldStart),
            .moveRegister(destination: register(0), source: register(8)),
            .returnFromFunction,
        ])
        instructions += sequence([
            .loadPairFromMemory(first: register(1), second: register(2), base: register(0), displacement: 0, adjustsBase: false),
            .moveImmediate(destination: register(0), value: 255),
            .call(target: Self.stateAccessor),
            .moveRegister(destination: register(1), source: register(0)),
            .moveImmediate(destination: register(0), value: 0),
            .call(target: Self.mutexAccessor),
            .returnFromFunction,
        ], startingAt: coldStart)

        let program = AccessorThunkAnalyzer.analyze(instructions: instructions, environment: environment)
        #expect(program.availabilityCheck == nil)
        #expect(program.limitations.isEmpty, "\(program.limitations)")
        let candidate = try #require(program.candidates.first)
        #expect(candidate.condition == .unconditional)
        #expect(candidate.reference == .constructed(.bound(
            accessorAddress: Self.mutexAccessor,
            typeArguments: [.bound(accessorAddress: Self.stateAccessor, typeArguments: [.argument(index: 0)])]
        )))
    }

    /// A thunk that returns a constant metadata address (the
    /// `_swift_runtimeSupportsNoncopyableTypes` probe shape) yields that
    /// metadata.
    @Test func readsAConstantMetadataReturn() throws {
        let program = AccessorThunkAnalyzer.analyze(instructions: sequence([
            .materializePageAddress(destination: register(8), pageBaseAddress: 0x4000_0000),
            .loadFromMemory(destination: register(8), base: register(8), displacement: 0x20),
            .branchIfZero(register: register(8), target: 0x1000 + 6 * 4),
            .materializePageAddress(destination: register(8), pageBaseAddress: 0x5000_0000),
            .addImmediate(destination: register(0), source: register(8), addend: 0x10),
            .returnFromFunction,
            .moveImmediate(destination: register(0), value: 0),
            .returnFromFunction,
        ]), environment: environment)
        let candidate = try #require(program.candidates.first)
        // A constant address is reported as the `.metadata` reference the
        // first landing introduced, so the two readings stay one to a caller.
        #expect(candidate.reference == .metadata(address: 0x5000_0010))
    }

    /// `__swift_instantiateConcreteTypeFromMangledNameV2`: the type is
    /// whatever the mangled name the thunk points at spells.
    @Test func readsAMangledNameInstantiation() throws {
        let program = AccessorThunkAnalyzer.analyze(instructions: sequence([
            .materializePageAddress(destination: register(0), pageBaseAddress: 0x6000_0000),
            .addImmediate(destination: register(0), source: register(0), addend: 0x100),
            .materializePageAddress(destination: register(1), pageBaseAddress: 0x7000_0000),
            .addImmediate(destination: register(1), source: register(1), addend: 0x200),
            .call(target: Self.mangledNameInstantiation),
            .returnFromFunction,
        ]), environment: environment)
        let candidate = try #require(program.candidates.first)
        #expect(candidate.reference == .constructed(.instantiatedFromMangledName(argumentAddresses: [0x6000_0100, 0x7000_0200])))
    }
}
