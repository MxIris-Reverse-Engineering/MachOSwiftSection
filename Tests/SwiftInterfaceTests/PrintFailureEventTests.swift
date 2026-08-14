@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
@_spi(Support) @testable import SwiftPrinting
@_spi(Support) @testable import SwiftInterface
import Foundation
import Testing
import MachOKit
import Dependencies
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// A definition that cannot be printed must be **reported**, not printed away.
///
/// Issue #102 measured both halves of this on a real binary: a run that dropped
/// 8,375 definitions dispatched **zero** `definitionPrintFailed` events, and its
/// only signal was a bare `unexpected(at: 8)` written to **stdout** — the same
/// stream `swift-section interface` / `dump` write the generated Swift to, so
/// the diagnostic corrupted the output it was reporting on and, being fully
/// buffered in a pipe, surfaced far from its cause.
///
/// The per-definition catch that keeps one bad definition from costing its
/// whole block is the fix's first half (already landed); these tests pin the
/// other two thirds — the failure is observable through the event stream, and
/// nothing reaches stdout.
@Suite(.serialized)
final class PrintFailureEventTests: MachOFileTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SymbolTestsCore }

    /// Collects every dispatched event so a test can assert on the stream.
    private final class EventCollector: SwiftIndexEvents.Handler, @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [SwiftIndexEvents.Payload] = []

        func handle(event: SwiftIndexEvents.Payload) {
            lock.lock()
            defer { lock.unlock() }
            storage.append(event)
        }

        var events: [SwiftIndexEvents.Payload] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }

        var printFailureNames: [String] {
            events.compactMap { event in
                guard case .definitionPrintFailed(let context, _) = event else { return nil }
                return context.name
            }
        }

        var printStartedNames: [String] {
            events.compactMap { event in
                guard case .definitionPrintStarted(let context) = event else { return nil }
                return context.name
            }
        }
    }

    private func preparedIndexer() async throws -> SwiftDeclarationIndexer<MachOFile> {
        let indexer = SwiftDeclarationIndexer(in: machOFile)
        try await indexer.prepare()
        return indexer
    }

    private func findTypeDefinition(named name: String, in indexer: SwiftDeclarationIndexer<MachOFile>) -> TypeDefinition? {
        indexer.allTypeDefinitions.values.first { $0.typeName.currentName == name }
    }

    /// A real struct descriptor re-wrapped at an offset far past the fixture's
    /// end of file: every relative resolve its indexing performs is out of
    /// bounds, so printing it throws deterministically.
    private func makeUnprintableDefinition(
        borrowingNameFrom donorDefinition: TypeDefinition,
        in indexer: SwiftDeclarationIndexer<MachOFile>
    ) throws -> TypeDefinition {
        let realStructDefinition = try #require(findTypeDefinition(named: "GenericStructNonRequirement", in: indexer))
        guard case .struct(let realStructDescriptor) = realStructDefinition.typeContextDescriptorWrapper else {
            throw PrintFailureEventTestError.fixtureTypeIsNotAStruct
        }
        let unreadableDescriptor = StructDescriptor(layout: realStructDescriptor.layout, offset: 0x0FFF_FFF0)
        return TypeDefinition(
            typeContextDescriptorWrapper: .struct(unreadableDescriptor),
            typeName: donorDefinition.typeName,
            isSpecialized: false
        )
    }

    private enum PrintFailureEventTestError: Error {
        case fixtureTypeIsNotAStruct
    }

    // NOTE — the ordering half of this contract (a failure must never precede
    // its own `definitionPrintStarted`) has no test here, deliberately.
    // Reaching it needs a protocol whose wrapper materialization THROWS, and the
    // technique the sibling tests use — a real descriptor layout re-wrapped far
    // past the fixture's end of file — does not throw for a `ProtocolDescriptor`:
    // it SEGFAULTS the test process, where the same construction over a
    // `StructDescriptor` throws cleanly. That reader-robustness gap is a finding
    // of its own (a damaged or hostile binary can take the process down rather
    // than surface an error) and is tracked separately; a test that crashes the
    // runner is worse than no test. After the fix the ordering holds structurally
    // anyway: the dispatch precedes the only throwing call in the function.

    /// The started event and the caller-side failure event must name the SAME
    /// declaration, or a consumer cannot correlate them. `Protocol.name` is the
    /// descriptor's BARE name ("View") while every caller-side context — and
    /// `printTypeDefinition`'s own — uses the QUALIFIED name ("SwiftUI.View").
    @Test func protocolStartEventUsesTheQualifiedNameLikeEveryOtherContext() async throws {
        let indexer = try await preparedIndexer()
        let protocolDefinition = try #require(indexer.allProtocolDefinitions.values.first)

        let collector = EventCollector()
        nonisolated(unsafe) let unsafeDefinition = protocolDefinition
        nonisolated(unsafe) let unsafePrinter = SwiftDeclarationPrinter(
            eventHandlers: [collector],
            in: machOFile
        )

        _ = try await unsafePrinter.printProtocolDefinition(unsafeDefinition).string

        #expect(
            collector.printStartedNames.contains(protocolDefinition.protocolName.name),
            "the start event must carry the qualified name `\(protocolDefinition.protocolName.name)`; got \(collector.printStartedNames)"
        )
    }

    @Test func droppedNestedChildDispatchesAPrintFailureEvent() async throws {
        let indexer = try await preparedIndexer()
        let hostDefinition = try #require(findTypeDefinition(named: "Classes", in: indexer))
        let donorDefinition = try #require(findTypeDefinition(named: "FinalClassTest", in: indexer))
        let unprintableDefinition = try makeUnprintableDefinition(borrowingNameFrom: donorDefinition, in: indexer)
        hostDefinition.typeChildren.append(unprintableDefinition)

        let collector = EventCollector()
        nonisolated(unsafe) let unsafeHostDefinition = hostDefinition
        nonisolated(unsafe) let unsafePrinter = SwiftDeclarationPrinter(
            eventHandlers: [collector],
            in: machOFile
        )

        _ = try await unsafePrinter.printTypeDefinition(unsafeHostDefinition).string

        #expect(
            collector.printFailureNames.contains(donorDefinition.typeName.name),
            "a dropped nested child must dispatch `definitionPrintFailed`; got \(collector.printFailureNames)"
        )
    }

    /// The dropped child must not reach **stdout**. Printing is driven with the
    /// process's real `STDOUT_FILENO` redirected to a pipe, because that is the
    /// exact channel the CLI streams the generated interface through — a
    /// `print(error)` anywhere under this call lands in the interface itself.
    @Test func droppedNestedChildWritesNothingToStandardOutput() async throws {
        let indexer = try await preparedIndexer()
        let hostDefinition = try #require(findTypeDefinition(named: "Classes", in: indexer))
        let donorDefinition = try #require(findTypeDefinition(named: "FinalClassTest", in: indexer))
        let unprintableDefinition = try makeUnprintableDefinition(borrowingNameFrom: donorDefinition, in: indexer)
        hostDefinition.typeChildren.append(unprintableDefinition)

        nonisolated(unsafe) let unsafeHostDefinition = hostDefinition
        nonisolated(unsafe) let unsafePrinter = SwiftDeclarationPrinter(in: machOFile)

        let capturedStandardOutput = try await captureStandardOutput {
            _ = try await unsafePrinter.printTypeDefinition(unsafeHostDefinition).string
        }

        #expect(
            capturedStandardOutput.isEmpty,
            "printing must write nothing to stdout — the CLI streams the generated interface there; captured: \(capturedStandardOutput)"
        )
    }

    /// Redirects `STDOUT_FILENO` to a pipe for the duration of `body`, then
    /// restores it and returns whatever was written.
    private func captureStandardOutput(_ body: () async throws -> Void) async throws -> String {
        let savedStandardOutput = dup(STDOUT_FILENO)
        defer { close(savedStandardOutput) }

        let pipe = Pipe()
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)

        var readData = Data()
        // Drain concurrently: a blocked pipe would otherwise deadlock the
        // writer once the buffer fills.
        let drainTask = Task.detached { () -> Data in
            var accumulated = Data()
            while let chunk = try? pipe.fileHandleForReading.read(upToCount: 4096), !chunk.isEmpty {
                accumulated.append(chunk)
            }
            return accumulated
        }

        do {
            try await body()
        } catch {
            fflush(stdout)
            dup2(savedStandardOutput, STDOUT_FILENO)
            try? pipe.fileHandleForWriting.close()
            _ = await drainTask.value
            throw error
        }

        fflush(stdout)
        dup2(savedStandardOutput, STDOUT_FILENO)
        try? pipe.fileHandleForWriting.close()
        readData = await drainTask.value

        return String(decoding: readData, as: UTF8.self)
    }

    /// `printCatchedThrowing` reports through an event only when BOTH a
    /// dispatcher and a context are supplied. Three call sites supply neither —
    /// the two block-level wrappers in `SwiftInterfaceBuilder` (deliberately: the
    /// members inside already report individually, so a block-level failure has
    /// no definition identity to attribute) and `printType`, which the diff
    /// renderer's `printEnumCase` runs every payload through. With the historical
    /// `print(error)` removed, that configuration swallowed failures completely:
    /// no event, nothing on stderr, and — on the diff path — a `case foo(Payload)`
    /// quietly rendered as `case foo`.
    ///
    /// stderr, never stdout: stdout carries the generated Swift (issue #102).
    @Test func catchWithNoEventSinkStillReportsOnStandardError() async throws {
        struct UnrenderableNodeError: Error {}

        // Neither closure captures anything: a capturing one would have to be
        // `sending` across `printCatchedThrowing`'s nonisolated boundary.
        let capturedStandardError = try await StandardStreamCapture.standardError {
            _ = await printCatchedThrowing {
                throw UnrenderableNodeError()
            }
        }

        #expect(
            !capturedStandardError.isEmpty,
            "with no dispatcher and no context there is nowhere else to report; the failure must not vanish"
        )
    }
}
