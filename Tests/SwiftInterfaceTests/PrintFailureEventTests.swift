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

    /// No library module may write to a process stream at all — that is what
    /// keeps diagnostics out of the generated interface (issue #102) and, since
    /// the raising `FileHandle` overload aborts the host on a closed or broken
    /// stream, what keeps a degradation from becoming a crash.
    ///
    /// Asserted as a **source scan** rather than by redirecting `STDOUT_FILENO`.
    /// The redirect version could not be made safe: `swift test` links every test
    /// target into one process and swift-testing's `.serialized` only serializes
    /// within a suite, so a parallel suite's output landed in this pipe (a false
    /// failure) and nested `dup`/`dup2` between suites could leave a pipe's write
    /// end held open, hanging the whole run. A scan also covers every module at
    /// once instead of the one path a test happens to drive — the same trade this
    /// PR already made for the NodeStore invariant.
    @Test func libraryModulesWriteToNoProcessStream() throws {
        // A `Handler` IS the sink — writing to a stream is the whole job of the
        // one a CLI host attaches. This is the layer where the choice is
        // legitimate, which is the point of routing everything through it.
        let sinkImplementations: Set<String> = ["SwiftIndexEventsHandlers.swift"]

        // Stream writes that predate this rule, in paths evolution 0005 did not
        // touch. Listed rather than ignored: the set may shrink, never grow —
        // a new offender in any other file fails this test. Paying these down is
        // its own change (they are debug tracing and error prints in the
        // descriptor-wrapper and layout-analysis layers, not the degradation
        // reporting this proposal restructured).
        let knownBaselineDebt: Set<String> = [
            "ContextDescriptorWrapper.swift",
            "TypeContextDescriptorWrapper.swift",
            "SubstitutionMap.swift",
            "SpareBitAnalyzer.swift",
            "PrimitiveTypeMapping.swift",
            "DumpableTests.swift",
        ]

        var offendingLines: [String] = []
        for fileURL in try Self.swiftSourceFiles() {
            if sinkImplementations.contains(fileURL.lastPathComponent) { continue }
            if knownBaselineDebt.contains(fileURL.lastPathComponent) { continue }

            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            for (lineNumber, line) in contents.components(separatedBy: .newlines).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//"), !code.hasPrefix("///") else { continue }
                // `func print()` DECLARES this library's own rendering API
                // (`TypeName.print()`, `Node.print(using:)`); it does not call
                // the stdlib's.
                guard !code.contains("func print(") else { continue }
                guard code.contains("FileHandle.standardError")
                    || code.contains("FileHandle.standardOutput")
                    || Self.containsBareCall(to: "fputs", in: code)
                    // Bare `print(` only. `node.print(using:)` and
                    // `printer.printRoot(...)` are this library's own rendering
                    // API, not the stdlib's stdout write.
                    || Self.containsBareCall(to: "print", in: code)
                else { continue }
                offendingLines.append("\(fileURL.lastPathComponent):\(lineNumber + 1): \(code)")
            }
        }

        #expect(
            offendingLines.isEmpty,
            """
            library code must report through `SwiftIndexEvents` (or os_log where no dispatcher is reachable), \
            never a process stream:
            \(offendingLines.joined(separator: "\n"))
            """
        )
    }

    /// Logging goes through `@Loggable` + `#log`, never a hand-rolled
    /// `os.Logger` / `os_log` / `OSLog` (AGENTS.md, "Logging").
    ///
    /// The macro is not a style preference here: it expands with the
    /// `#available(macOS 11, …)` fallback to `os_log` that this package needs,
    /// since it deploys to macOS 10.15 — below `os.Logger`. Hand-rolling either
    /// half loses that, and hand-rolling `os_log` to dodge it (which this batch
    /// did, briefly) loses the shared subsystem/category conventions RuntimeViewer
    /// filters on.
    @Test func libraryModulesLogThroughTheLoggableMacro() throws {
        // `OSLogEventHandler` takes its subsystem and category as *runtime*
        // parameters, which `@Loggable` cannot express — it fixes both at compile
        // time. A host-configurable sink is the one legitimate `Logger` here.
        let configurableSinks: Set<String> = ["SwiftIndexEventsHandlers.swift"]
        // Belongs to the commented-out `TypeIndexing` target, so it compiles
        // nowhere. Listed rather than fixed: changing dead code buys no
        // verification. If that target is ever revived, convert it first.
        let excludedFromBuild: Set<String> = ["SDKIndexer.swift"]

        var offendingLines: [String] = []
        for fileURL in try Self.swiftSourceFiles() {
            if configurableSinks.contains(fileURL.lastPathComponent) { continue }
            if excludedFromBuild.contains(fileURL.lastPathComponent) { continue }

            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            for (lineNumber, line) in contents.components(separatedBy: .newlines).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//"), !code.hasPrefix("///") else { continue }
                guard Self.containsBareCall(to: "os_log", in: code)
                    || Self.containsBareCall(to: "OSLog", in: code)
                    || Self.containsBareCall(to: "Logger", in: code)
                else { continue }
                offendingLines.append("\(fileURL.lastPathComponent):\(lineNumber + 1): \(code)")
            }
        }

        #expect(
            offendingLines.isEmpty,
            """
            log through `@Loggable` + `#log` (protocol-form `@Loggable` for generic types), \
            never a hand-rolled logger:
            \(offendingLines.joined(separator: "\n"))
            """
        )
    }

    /// Every `.swift` file under `Sources/`, minus the modules that are hosts
    /// rather than libraries: the CLI's stderr is its diagnostic channel and its
    /// stdout its product output, and testing support ships in neither.
    private static func swiftSourceFiles() throws -> [URL] {
        let sourcesDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SwiftInterfaceTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
            .appendingPathComponent("Sources")
        let hostModules: Set<String> = ["swift-section", "MachOTestingSupport"]

        let enumerator = try #require(FileManager.default.enumerator(at: sourcesDirectory, includingPropertiesForKeys: nil))
        var files: [URL] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let moduleName = fileURL.pathComponents
                .drop(while: { $0 != "Sources" })
                .dropFirst()
                .first
            if let moduleName, hostModules.contains(moduleName) { continue }
            files.append(fileURL)
        }
        return files
    }

    /// Is `name(` called as a function here, rather than as a member of
    /// something? `node.print(using:)` is this library's rendering API and must
    /// not be mistaken for the stdlib's `print`.
    private static func containsBareCall(to name: String, in code: String) -> Bool {
        var searchRange = code.startIndex..<code.endIndex
        while let found = code.range(of: name + "(", range: searchRange) {
            if found.lowerBound == code.startIndex { return true }
            let preceding = code[code.index(before: found.lowerBound)]
            if !preceding.isLetter, !preceding.isNumber, preceding != ".", preceding != "_" {
                return true
            }
            searchRange = found.upperBound..<code.endIndex
        }
        return false
    }

    /// The scanner must be able to see a violation, and must not invent one —
    /// its silence proves nothing otherwise.
    @Test func theStreamWriteScannerDiscriminates() throws {
        #expect(Self.containsBareCall(to: "print", in: "print(error)"))
        #expect(Self.containsBareCall(to: "print", in: "if failed { print(error) }"))
        #expect(Self.containsBareCall(to: "fputs", in: "fputs(message, stderr)"))

        // This library's own rendering API, not a stream write.
        #expect(!Self.containsBareCall(to: "print", in: "let text = node.print(using: .default)"))
        #expect(!Self.containsBareCall(to: "print", in: "try await printer.printRoot(node)"))
        #expect(!Self.containsBareCall(to: "print", in: "debugPrint(value)"))
        // A declaration of that API reads like a bare call and is filtered
        // separately — `public func print() -> SemanticString` is not a write.
        #expect("public func print() -> SemanticString {".contains("func print("))

        // The logging scan rides on the same predicate.
        #expect(Self.containsBareCall(to: "Logger", in: "let logger = Logger(subsystem: s, category: c)"))
        #expect(Self.containsBareCall(to: "os_log", in: "os_log(.error, log: someLog, \"boom\")"))
        // `@Loggable`-generated access is a member read, not a bare call.
        #expect(!Self.containsBareCall(to: "Logger", in: "Self.logger.error(\"boom\")"))
    }

    /// A failure with no *definition identity* must still be reported.
    ///
    /// `printCatchedThrowing` takes a required dispatcher but an optional
    /// context: the two block-level wrappers in `SwiftInterfaceBuilder` have no
    /// single definition to blame (their members already report individually),
    /// and `printType` renders a fragment — an enum case's payload, a property's
    /// type. Those report as `renderingDegraded` instead. When the dispatcher was
    /// optional and these callers passed nothing, the failure fell to a stderr
    /// write; on the diff path, where no sink existed at all, `case foo(Payload)`
    /// became `case foo` in silence.
    @Test func catchWithoutDefinitionIdentityReportsDegradation() async throws {
        struct UnrenderableNodeError: Error {}

        let collector = SwiftIndexEventCollector()
        let eventDispatcher = SwiftIndexEvents.Dispatcher()
        eventDispatcher.addHandler(collector)

        // The closure captures nothing: a capturing one would have to be
        // `sending` across `printCatchedThrowing`'s nonisolated boundary.
        _ = await printCatchedThrowing(dispatchingTo: eventDispatcher) {
            throw UnrenderableNodeError()
        }

        #expect(
            collector.degradationSources.contains(.typeNodeRendering),
            "a fragment that failed to render must report as a degradation; got \(collector.degradationSources)"
        )
    }

    /// The zero-handler floor's own contract.
    ///
    /// `Dispatcher.dispatch` reports to os_log when nothing is attached, and it
    /// decides *what* to report from `unhandledFailureDescription`. That
    /// partition is a whitelist rather than an inverted `default`, so a newly
    /// added failure case silently opts out of the floor unless a branch is added
    /// with it — which is the regression class the floor exists to prevent.
    /// Assert the partition directly; the os_log write itself is not observable
    /// in-process.
    @Test func everyFailureEventIsRecognizedByTheFloor() async throws {
        struct SomeError: Error {}
        let context = SwiftIndexEvents.PrintingContext(name: "Foo", kind: .type)

        #expect(SwiftIndexEvents.Payload.definitionPrintFailed(context: context, error: SomeError()).unhandledFailureDescription != nil)
        #expect(SwiftIndexEvents.Payload.renderingDegraded(context: .init(source: .subclassMap, subject: "Bar"), error: SomeError()).unhandledFailureDescription != nil)
        #expect(SwiftIndexEvents.Payload.phaseTransition(phase: .indexing, state: .failed(SomeError())).unhandledFailureDescription != nil)
        #expect(SwiftIndexEvents.Payload.typeProcessingFailed(typeName: "Baz", error: SomeError()).unhandledFailureDescription != nil)

        // Progress events stay off the floor: logging every tick would bury the
        // failures it exists to surface.
        #expect(SwiftIndexEvents.Payload.definitionPrintStarted(context: context).unhandledFailureDescription == nil)
        #expect(SwiftIndexEvents.Payload.phaseTransition(phase: .indexing, state: .completed).unhandledFailureDescription == nil)
    }
}
