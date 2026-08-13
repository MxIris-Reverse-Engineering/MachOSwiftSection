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
}
