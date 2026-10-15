import Foundation
import Testing
import MachOKit
import MachOSwiftSection
import Semantic
import SwiftDeclarationRendering
@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
@_spi(Support) @testable import SwiftPrinting
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Printing the SymbolTestsCore fixture's definitions from several tasks at
/// once reads byte for byte as printing them one after another (evolution
/// proposal `concurrent-definition-printing`).
///
/// RuntimeViewer prints this way: its search corpus prints an image's
/// definitions from a bounded task group sharing one printer while its
/// display path prints the same definitions through another, both through
/// the in-process reader. A definition indexes itself on its first print,
/// so every test starts from an indexer whose definitions nobody has printed
/// yet and compares against a second indexer printed serially.
///
/// Under the thread sanitizer (`swift test -c release --sanitize=thread
/// --filter ConcurrentDefinitionPrintingTests`) this suite is the race
/// detector the proposal was verified with. Release, because a debug
/// sanitizer build traps before any test runs: MachOKit's `FileHandle.read`
/// loads the fixture's magic with an aligned load from a buffer the
/// sanitizer's stack layout leaves misaligned. Without the sanitizer, a
/// race still shows up when it corrupts an output or the heap — before
/// the fix it crashed this suite on a released `attributes` array.
@Suite
final class ConcurrentDefinitionPrintingTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    private enum PrintOutcome: Equatable, Sendable {
        case printed(FrozenSemanticString)
        case threw(String)

        var text: String {
            switch self {
            case .printed(let printed):
                return printed.string
            case .threw(let errorDescription):
                return "<threw: \(errorDescription)>"
            }
        }
    }

    /// One declaration's print. Built per indexer: the definitions of two
    /// indexers over one image line up position by position.
    private struct PrintJob: Sendable {
        let label: String
        let print: @Sendable (SwiftDeclarationPrinter<MachOImage>) async throws -> SemanticString

        func outcome(using printer: SwiftDeclarationPrinter<MachOImage>) async -> PrintOutcome {
            do {
                return .printed(try await print(printer).frozen())
            } catch {
                return .threw(String(describing: error))
            }
        }
    }

    private struct PrintWork: Sendable {
        let jobIndex: Int
        let printer: SwiftDeclarationPrinter<MachOImage>
    }

    /// RuntimeViewer's corpus width.
    private static let taskGroupWidth = max(2, ProcessInfo.processInfo.activeProcessorCount / 2)

    /// How many tasks print one definition at the same moment.
    private static let simultaneousPrintCount = 4

    /// The corpus mode RuntimeViewer prints in: every optional comment
    /// marked rather than dropped, so every rendering path runs.
    private func makePrinter() -> SwiftDeclarationPrinter<MachOImage> {
        var configuration = SwiftDeclarationPrintConfiguration()
        configuration.marksOptionalContent = true
        return SwiftDeclarationPrinter(configuration: configuration, in: machOImage)
    }

    private func makePreparedIndexer() async throws -> SwiftDeclarationIndexer<MachOImage> {
        let indexer = SwiftDeclarationIndexer(in: machOImage)
        try await indexer.prepare()
        return indexer
    }

    /// Every type (nested ones included — RuntimeViewer prints those on their
    /// own too), protocol and extension the indexer found, in its order.
    private static func printJobs(of indexer: SwiftDeclarationIndexer<MachOImage>) -> [PrintJob] {
        var printJobs: [PrintJob] = []
        for (typeName, typeDefinition) in indexer.allTypeDefinitions {
            printJobs.append(PrintJob(label: "type \(typeName.name)") { printer in
                try await printer.printTypeDefinition(typeDefinition)
            })
        }
        for (protocolName, protocolDefinition) in indexer.allProtocolDefinitions {
            printJobs.append(PrintJob(label: "protocol \(protocolName.name)") { printer in
                try await printer.printProtocolDefinition(protocolDefinition)
            })
        }
        let extensionGroups = [indexer.typeExtensionDefinitions, indexer.protocolExtensionDefinitions, indexer.typeAliasExtensionDefinitions, indexer.conformanceExtensionDefinitions]
        for extensionGroup in extensionGroups {
            for (extensionName, extensionDefinitions) in extensionGroup {
                for (extensionIndex, extensionDefinition) in extensionDefinitions.enumerated() {
                    printJobs.append(PrintJob(label: "extension \(extensionName.name) #\(extensionIndex)") { printer in
                        try await printer.printExtensionDefinition(extensionDefinition)
                    })
                }
            }
        }
        return printJobs
    }

    /// What every concurrent print must equal: each job of a fresh indexer
    /// printed one after another by one printer.
    private func serialOutcomes() async throws -> (labels: [String], outcomes: [PrintOutcome]) {
        let indexer = try await makePreparedIndexer()
        let printJobs = Self.printJobs(of: indexer)
        let printer = makePrinter()
        var outcomes: [PrintOutcome] = []
        for printJob in printJobs {
            outcomes.append(await printJob.outcome(using: printer))
        }
        return (printJobs.map(\.label), outcomes)
    }

    /// Runs `work` in a task group at most `width` tasks wide and returns the
    /// outcomes in `work`'s order.
    private static func outcomes(of work: [PrintWork], jobs printJobs: [PrintJob], width: Int) async -> [PrintOutcome] {
        await withTaskGroup(of: (workIndex: Int, outcome: PrintOutcome).self) { group in
            var outcomes = [PrintOutcome?](repeating: nil, count: work.count)
            var nextWorkIndex = 0
            var runningTaskCount = 0
            while nextWorkIndex < work.count || runningTaskCount > 0 {
                while runningTaskCount < width, nextWorkIndex < work.count {
                    let workIndex = nextWorkIndex
                    let printWork = work[workIndex]
                    let printJob = printJobs[printWork.jobIndex]
                    group.addTask {
                        (workIndex, await printJob.outcome(using: printWork.printer))
                    }
                    nextWorkIndex += 1
                    runningTaskCount += 1
                }
                if let finished = await group.next() {
                    outcomes[finished.workIndex] = finished.outcome
                    runningTaskCount -= 1
                }
            }
            return outcomes.map { outcome in
                guard let outcome else { preconditionFailure("every added task reports back before the group ends") }
                return outcome
            }
        }
    }

    /// The jobs whose concurrent outcome differs from the serial one, each
    /// described by its first differing line.
    private static func mismatches(of work: [PrintWork], outcomes: [PrintOutcome], jobs printJobs: [PrintJob], reference: [PrintOutcome]) -> [String] {
        var mismatches: [String] = []
        for (printWork, outcome) in zip(work, outcomes) where outcome != reference[printWork.jobIndex] {
            let expectedLines = reference[printWork.jobIndex].text.split(separator: "\n", omittingEmptySubsequences: false)
            let actualLines = outcome.text.split(separator: "\n", omittingEmptySubsequences: false)
            let commonLineCount = min(expectedLines.count, actualLines.count)
            let firstDifferingLine = (0 ..< commonLineCount).first { expectedLines[$0] != actualLines[$0] } ?? commonLineCount
            let expectedLine = expectedLines.indices.contains(firstDifferingLine) ? String(expectedLines[firstDifferingLine]) : "<end>"
            let actualLine = actualLines.indices.contains(firstDifferingLine) ? String(actualLines[firstDifferingLine]) : "<end>"
            mismatches.append("\(printJobs[printWork.jobIndex].label), line \(firstDifferingLine + 1):\n  serial:     \(expectedLine)\n  concurrent: \(actualLine)")
        }
        return mismatches
    }

    @Test func definitionsSpreadOverTasksPrintAsTheyDoSerially() async throws {
        let reference = try await serialOutcomes()
        let indexer = try await makePreparedIndexer()
        let printJobs = Self.printJobs(of: indexer)
        try #require(printJobs.map(\.label) == reference.labels)

        // Both printers print every definition, their two prints queued next
        // to each other so that they overlap: the corpus and the display path.
        let corpusPrinter = makePrinter()
        let displayPrinter = makePrinter()
        let work = printJobs.indices.flatMap { jobIndex in
            [PrintWork(jobIndex: jobIndex, printer: corpusPrinter), PrintWork(jobIndex: jobIndex, printer: displayPrinter)]
        }
        let outcomes = await Self.outcomes(of: work, jobs: printJobs, width: Self.taskGroupWidth)

        let mismatches = Self.mismatches(of: work, outcomes: outcomes, jobs: printJobs, reference: reference.outcomes)
        #expect(printJobs.count > 100)
        #expect(mismatches.isEmpty, "\(mismatches.prefix(5).joined(separator: "\n"))")
    }

    @Test func oneDefinitionPrintedByManyTasksAtOncePrintsAsItDoesSerially() async throws {
        let reference = try await serialOutcomes()
        let indexer = try await makePreparedIndexer()
        let printJobs = Self.printJobs(of: indexer)
        try #require(printJobs.map(\.label) == reference.labels)

        let printers = [makePrinter(), makePrinter()]
        var mismatches: [String] = []
        for jobIndex in printJobs.indices {
            let work = (0 ..< Self.simultaneousPrintCount).map { printIndex in
                PrintWork(jobIndex: jobIndex, printer: printers[printIndex % printers.count])
            }
            let outcomes = await Self.outcomes(of: work, jobs: printJobs, width: work.count)
            mismatches += Self.mismatches(of: work, outcomes: outcomes, jobs: printJobs, reference: reference.outcomes)
        }
        #expect(mismatches.isEmpty, "\(mismatches.prefix(5).joined(separator: "\n"))")
    }

    @Test func aTypeAndItsNestedTypesPrintedAtOncePrintAsTheyDoSerially() async throws {
        let reference = try await serialOutcomes()
        let indexer = try await makePreparedIndexer()
        let printJobs = Self.printJobs(of: indexer)
        try #require(printJobs.map(\.label) == reference.labels)

        // A type's print prints its nested types too, so each subtree printed
        // at once has every definition in it reached from several tasks.
        var jobIndexByTypeDefinition: [ObjectIdentifier: Int] = [:]
        for (jobIndex, typeDefinition) in indexer.allTypeDefinitions.values.enumerated() {
            jobIndexByTypeDefinition[ObjectIdentifier(typeDefinition)] = jobIndex
        }
        let printer = makePrinter()
        var printedSubtreeCount = 0
        var mismatches: [String] = []
        for rootTypeDefinition in indexer.rootTypeDefinitions.values where !rootTypeDefinition.typeChildren.isEmpty {
            var subtree: [TypeDefinition] = []
            var pending = [rootTypeDefinition]
            while let typeDefinition = pending.popLast() {
                subtree.append(typeDefinition)
                pending += typeDefinition.typeChildren
            }
            let work = try subtree.map { typeDefinition in
                PrintWork(jobIndex: try #require(jobIndexByTypeDefinition[ObjectIdentifier(typeDefinition)]), printer: printer)
            }
            let outcomes = await Self.outcomes(of: work, jobs: printJobs, width: work.count)
            mismatches += Self.mismatches(of: work, outcomes: outcomes, jobs: printJobs, reference: reference.outcomes)
            printedSubtreeCount += 1
        }
        #expect(printedSubtreeCount > 5)
        #expect(mismatches.isEmpty, "\(mismatches.prefix(5).joined(separator: "\n"))")
    }
}
