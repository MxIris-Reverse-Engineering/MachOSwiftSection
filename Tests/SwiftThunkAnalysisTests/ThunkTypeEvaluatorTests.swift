#if THUNK_ANALYSIS

import Foundation
import Testing
@testable import SwiftThunkAnalysis

/// A tabled environment: call targets and pointer words the test declares.
private struct TabledEnvironment: ThunkEvaluationEnvironment {
    var callees: [UInt64: ThunkCallee] = [:]
    var pointers: [UInt64: UInt64] = [:]

    var slotSymbolNames: [UInt64: String] = [:]

    func callee(at address: UInt64) -> ThunkCallee { callees[address] ?? .unknown }
    func pointer(at address: UInt64) -> UInt64? { pointers[address] }
    func slotSymbolName(at address: UInt64) -> String? { slotSymbolNames[address] }
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

    private var environment: TabledEnvironment {
        TabledEnvironment(callees: [
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

#endif
