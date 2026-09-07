import Foundation
import OSLog
import SwiftDeclaration

/// A default event handler implementation that uses `OSLog` for logging.
@available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
public struct OSLogEventHandler: SwiftIndexEvents.Handler {
    private let logger: Logger

    public init(subsystem: String = "com.MxIris.MachOSwiftSection.SwiftInterface", category: String = "SwiftInterfaceBuilder") {
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    public func handle(event: SwiftIndexEvents.Payload) {
        switch event {
        case .phaseTransition(let phase, let state):
            logPhaseTransition(phase: phase, state: state)

        case .extractionStarted(let section):
            logger.debug("Extracting \(sectionName(section)) from Mach-O binary")

        case .extractionCompleted(let result):
            logger.info("Successfully extracted \(result.count) \(sectionName(result.section))")

        case .extractionFailed(let section, let error):
            logger.error("Failed to extract \(sectionName(section)) from Mach-O binary: \(String(describing: error))")

        case .typeIndexingStarted(let totalTypes):
            logger.debug("Starting type indexing for \(totalTypes) types")

        case .typeIndexingCompleted(let result):
            logger.info("Type indexing completed: \(result.successful) successful, \(result.failed) failed, \(result.cImportedSkipped) C-imported types skipped, \(result.nestedTypes) nested types, \(result.extensionTypes) extension types")

        case .typeProcessed(let context):
            logger.trace("Processed type: \(context.typeName) (kind: \(String(describing: context.kind)))")

        case .typeProcessingFailed(let typeName, let error):
            logger.error("Failed to process type '\(typeName ?? "<unknown>")': \(String(describing: error))")

        case .typeProcessingSkippedCImported:
            logger.trace("Skipped C-imported type")

        case .typeNestingResolved(let context):
            if let parentTypeName = context.parentTypeName {
                logger.trace("Resolved nesting: \(context.childTypeName) is nested in \(parentTypeName)")
            } else {
                logger.trace("Resolved nesting: \(context.childTypeName) has no parent type")
            }

        case .protocolIndexingStarted(let totalProtocols):
            logger.debug("Starting protocol indexing for \(totalProtocols) protocols")

        case .protocolIndexingCompleted(let result):
            logger.info("Protocol indexing completed: \(result.successful) successful, \(result.failed) failed")

        case .conformanceIndexingStarted(let input):
            logger.debug("Starting conformance indexing for \(input.totalConformances) conformances")
            logger.debug("Starting associated type indexing for \(input.totalAssociatedTypes) associated types")

        case .conformanceIndexingCompleted(let result):
            logger.debug("Protocol conformances indexed: \(result.conformedTypes) types with conformances, \(result.failedConformances) failed")
            logger.debug("Associated types indexed: \(result.associatedTypeCount) types with associated types, \(result.failedAssociatedTypes) failed")
            logger.info("Conformance indexing completed: \(result.extensionCount) conformance extensions created, \(result.failedExtensions) failed")

        case .extensionIndexingStarted:
            logger.debug("Starting extension indexing")

        case .extensionIndexingCompleted(let result):
            logger.info("Extension indexing completed: \(result.typeExtensions) type extensions, \(result.protocolExtensions) protocol extensions, \(result.typeAliasExtensions) type alias extensions, \(result.failed) failed")

        case .moduleCollectionStarted:
            logger.debug("Starting module collection")

        case .moduleCollectionCompleted(let result):
            logger.info("Module collection completed: found \(result.moduleCount) modules to import: \(result.modules.joined(separator: ", "))")

        case .phaseOperationStarted(let phase, let operation):
            logger.debug("Starting \(operationName(operation)) in \(phaseName(phase)) phase")

        case .phaseOperationCompleted(let phase, let operation):
            logger.debug("\(operationName(operation)) in \(phaseName(phase)) phase completed")

        case .phaseOperationFailed(let phase, let operation, let error):
            logger.error("\(operationName(operation)) in \(phaseName(phase)) phase failed: \(String(describing: error))")

        case .conformanceFound(let context):
            logger.trace("Found conformance: \(context.typeName) conforms to \(context.protocolName)")

        case .conformanceProcessingFailed(let context, let error):
            logger.error("Error processing protocol conformance for \(context.typeName) : \(context.protocolName) - \(String(describing: error))")

        case .associatedTypeFound(let context):
            logger.trace("Found associated type for \(context.typeName) in protocol \(context.protocolName)")

        case .associatedTypeProcessingFailed(let context, let error):
            logger.error("Error processing associated type for \(context.typeName) in \(context.protocolName) - \(String(describing: error))")

        case .conformanceExtensionCreated(let context):
            logger.trace("Created conformance extension: \(context.typeName) : \(context.protocolName)")

        case .conformanceExtensionCreationFailed(let context, let error):
            logger.error("Failed to create extension definition for type '\(context.typeName)' conforming to protocol '\(context.protocolName)' - \(String(describing: error))")

        case .extensionTargetNotFound(let targetName):
            logger.trace("No type info found for extension target: \(targetName)")

        case .extensionCreated(let context):
            logger.trace("Created extension for \(context.targetName) with \(context.memberCount) members")

        case .extensionCreationFailed(let targetName, let error):
            logger.error("Failed to create extension definition for \(targetName) - \(String(describing: error))")

        case .protocolProcessed(let context):
            logger.trace("Indexed protocol: \(context.protocolName) with \(context.requirementCount) requirements")

        case .protocolProcessingFailed(let protocolName, let error):
            logger.error("Failed to create ProtocolDefinition for protocol \(protocolName) - \(String(describing: error))")

        case .moduleFound(let context):
            logger.trace("Found module: \(context.moduleName)")

        case .symbolScanStarted(let context):
            logger.debug("Scanning \(context.totalSymbols) symbols for module references")
            logger.debug("Filtering out internal modules: \(context.filterModules.joined(separator: ", "))")

        case .nameExtractionWarning(let target):
            logger.warning("Failed to extract type name or protocol name from \(target.description).")

        case .definitionPrintStarted(let context):
            logger.trace("Printing \(context.kind.description): \(context.name)")

        case .definitionPrintCompleted(let context):
            logger.trace("Printed \(context.kind.description): \(context.name)")

        case .definitionPrintFailed(let context, let error):
            logger.error("Failed to print \(context.kind.description) '\(context.name)': \(String(describing: error))")

        case .renderingDegraded(let context, let error):
            let subject = context.subject.map { " for \($0)" } ?? ""
            logger.error("Degraded \(context.source.description)\(subject): \(String(describing: error))")

        case .symbolIndexProgress(let currentCount, let totalCount):
            logger.trace("Symbol index progress: \(currentCount)/\(totalCount)")
        }
    }

    private func operationName(_ operation: SwiftIndexEvents.PhaseOperation) -> String {
        switch operation {
        case .typeIndexing: return "Type indexing"
        case .protocolIndexing: return "Protocol indexing"
        case .conformanceIndexing: return "Conformance indexing"
        case .extensionIndexing: return "Extension indexing"
        }
    }

    private func logPhaseTransition(phase: SwiftIndexEvents.Phase, state: SwiftIndexEvents.State) {
        let phaseNameStr = phaseName(phase)
        switch state {
        case .started:
            logger.info("Starting \(phaseNameStr) phase")
        case .completed:
            logger.info("\(phaseNameStr) phase completed successfully")
        case .failed(let error):
            logger.error("\(phaseNameStr) phase failed: \(String(describing: error))")
        }
    }

    private func phaseName(_ phase: SwiftIndexEvents.Phase) -> String {
        switch phase {
        case .preparation: return "preparation"
        case .extraction: return "extraction"
        case .indexing: return "indexing"
        case .moduleCollection: return "module collection"
        case .build: return "build"
        }
    }

    private func sectionName(_ section: SwiftIndexEvents.Section) -> String {
        switch section {
        case .swiftTypes: return "Swift types"
        case .swiftProtocols: return "Swift protocols"
        case .protocolConformances: return "protocol conformances"
        case .associatedTypes: return "associated types"
        case .symbolIndex: return "symbol index"
        }
    }
}

/// A simple event handler that reports summary information to the console.
///
/// This is the handler a CLI host attaches: it puts diagnostics on **stderr**,
/// where an operator's terminal, `2>` redirect and CI log all pick them up —
/// the reason `SwiftIndexEvents.Dispatcher`'s own floor (os_log) is only a
/// floor. Issue #102 reported the CI case directly.
public struct ConsoleEventHandler: SwiftIndexEvents.Handler {
    /// An input label (`old` / `new`, a version label, a file name) printed
    /// after the timestamp on every line. Set it when several inputs report
    /// at once — `diff` and `evolution` index their inputs concurrently
    /// (evolution proposal `large-stack-executor-and-cross-version-parallelism`),
    /// so an unlabeled line cannot be attributed to an input.
    public let label: String?

    public init(label: String? = nil) {
        self.label = label
    }

    public func handle(event: SwiftIndexEvents.Payload) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        if let line = line(for: event, timestamp: timestamp) {
            report(line)
        }
    }

    /// The line `handle(event:)` writes for `event`, or `nil` for an event the
    /// console does not report. `[timestamp] [label] [LEVEL] message`; the
    /// label bracket is absent when there is no label.
    package func line(for event: SwiftIndexEvents.Payload, timestamp: String) -> String? {
        let prefix = "[\(timestamp)]" + (label.map { " [\($0)]" } ?? "")

        switch event {
        case .extractionCompleted(let result):
            return "\(prefix) [INFO] Extracted \(result.count) \(sectionName(result.section))"

        case .typeIndexingCompleted(let result):
            return "\(prefix) [INFO] Types: \(result.successful) successful, \(result.failed) failed, \(result.cImportedSkipped) C-imported skipped, \(result.nestedTypes) nested, \(result.extensionTypes) in extensions"

        case .protocolIndexingCompleted(let result):
            return "\(prefix) [INFO] Protocols: \(result.successful) successful, \(result.failed) failed"

        case .conformanceIndexingCompleted(let result):
            return "\(prefix) [INFO] Conformances: \(result.extensionCount) extensions, \(result.failedConformances + result.failedAssociatedTypes + result.failedExtensions) failed"

        case .extensionIndexingCompleted(let result):
            return "\(prefix) [INFO] Extensions: \(result.typeExtensions) type, \(result.protocolExtensions) protocol, \(result.typeAliasExtensions) typealias, \(result.failed) failed"

        case .moduleCollectionCompleted(let result):
            return "\(prefix) [INFO] Found \(result.moduleCount) modules to import"

        case .phaseTransition(let phase, let state):
            let phaseName = phaseName(phase)
            switch state {
            case .completed:
                return "\(prefix) [SUCCESS] \(phaseName.capitalized) completed"
            case .failed(let error):
                return "\(prefix) [ERROR] \(phaseName.capitalized) failed: \(String(describing: error))"
            case .started:
                return nil // Ignore started events for console output
            }

        case .definitionPrintFailed(let context, let error):
            return "\(prefix) [ERROR] Failed to print \(context.kind.description) '\(context.name)': \(String(describing: error))"

        case .renderingDegraded(let context, let error):
            let subject = context.subject.map { " for \($0)" } ?? ""
            return "\(prefix) [ERROR] Degraded \(context.source)\(subject): \(String(describing: error))"

        default:
            return nil // Ignore other detailed events
        }
    }

    /// The single write site, on stderr.
    ///
    /// stdout carries the generated Swift / JSON (`InterfaceCommand`,
    /// `DumpCommand`, `SnapshotCommand`), so a diagnostic printed there lands
    /// inside the product output and corrupts any piped or redirected run —
    /// issue #102 measured exactly that, a bare `unexpected(at: 8)` embedded in
    /// a multi-megabyte interface.
    ///
    /// `fputs`, not `FileHandle.standardError.write(_:)`: that overload is the
    /// Objective-C bridge and raises `NSFileHandleOperationException` when the
    /// stream is closed or broken. Swift cannot catch an ObjC exception, so it
    /// aborts the host process — turning a degradation report into a crash.
    private func report(_ message: String) {
        fputs(message + "\n", stderr)
    }

    private func phaseName(_ phase: SwiftIndexEvents.Phase) -> String {
        switch phase {
        case .preparation: return "preparation"
        case .extraction: return "extraction"
        case .indexing: return "indexing"
        case .moduleCollection: return "module collection"
        case .build: return "build"
        }
    }

    private func sectionName(_ section: SwiftIndexEvents.Section) -> String {
        switch section {
        case .swiftTypes: return "Swift types"
        case .swiftProtocols: return "Swift protocols"
        case .protocolConformances: return "protocol conformances"
        case .associatedTypes: return "associated types"
        case .symbolIndex: return "symbol index"
        }
    }
}
