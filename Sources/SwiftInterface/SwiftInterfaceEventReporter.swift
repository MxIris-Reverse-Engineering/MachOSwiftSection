import Foundation

/// An event handler that transforms raw events into UI-friendly reports
/// and delivers them via an `AsyncStream`.
public final class SwiftInterfaceEventReporter: SwiftInterfaceEvents.Handler, Sendable {
    /// A structured report entry suitable for UI display.
    public struct Report: Sendable, Identifiable {
        public let id: UUID
        public let timestamp: Date
        public let level: Level
        public let category: Category
        public let message: String
        public let detail: String?

        public enum Level: Sendable, Comparable {
            case trace
            case progress
            case info
            case success
            case warning
            case error
        }

        public enum Category: Sendable {
            case phase
            case extraction
            case indexing
            case moduleCollection
            case printing
        }

        init(level: Level, category: Category, message: String, detail: String? = nil) {
            self.id = UUID()
            self.timestamp = Date()
            self.level = level
            self.category = category
            self.message = message
            self.detail = detail
        }
    }

    /// The minimum report level to emit. Reports below this level are discarded.
    public let minimumLevel: Report.Level

    public let reports: AsyncStream<Report>

    private let continuation: AsyncStream<Report>.Continuation

    public init(minimumLevel: Report.Level = .progress) {
        self.minimumLevel = minimumLevel
        (reports, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    public func finish() {
        continuation.finish()
    }

    public func handle(event: SwiftInterfaceEvents.Payload) {
        switch event {
        // MARK: Phase transitions

        case .phaseTransition(let phase, let state):
            let name = phaseName(phase)
            switch state {
            case .started:
                yield(.progress, .phase, "Starting \(name)")
            case .completed:
                yield(.success, .phase, "\(name.capitalized) completed")
            case .failed(let error):
                yield(.error, .phase, "\(name.capitalized) failed", detail: String(describing: error))
            }

        // MARK: Extraction

        case .extractionStarted(let section):
            yield(.progress, .extraction, "Extracting \(sectionName(section))")

        case .extractionCompleted(let result):
            yield(.info, .extraction, "Extracted \(result.count) \(sectionName(result.section))")

        case .extractionFailed(let section, let error):
            yield(.error, .extraction, "Failed to extract \(sectionName(section))", detail: String(describing: error))

        // MARK: Type indexing

        case .typeIndexingStarted(let totalTypes):
            yield(.progress, .indexing, "Indexing \(totalTypes) types")

        case .typeIndexingCompleted(let result):
            yield(.info, .indexing, "Types indexed: \(result.successful) OK, \(result.failed) failed", detail: formatTypeIndexingDetail(result))

        // MARK: Protocol indexing

        case .protocolIndexingStarted(let totalProtocols):
            yield(.progress, .indexing, "Indexing \(totalProtocols) protocols")

        case .protocolIndexingCompleted(let result):
            yield(.info, .indexing, "Protocols indexed: \(result.successful) OK, \(result.failed) failed")

        // MARK: Conformance indexing

        case .conformanceIndexingStarted(let input):
            yield(.progress, .indexing, "Indexing \(input.totalConformances) conformances, \(input.totalAssociatedTypes) associated types")

        case .conformanceIndexingCompleted(let result):
            let totalFailed = result.failedConformances + result.failedAssociatedTypes + result.failedExtensions
            yield(.info, .indexing, "Conformances indexed: \(result.extensionCount) extensions, \(totalFailed) failed")

        // MARK: Extension indexing

        case .extensionIndexingStarted:
            yield(.progress, .indexing, "Indexing extensions")

        case .extensionIndexingCompleted(let result):
            yield(.info, .indexing, "Extensions indexed: \(result.typeExtensions) type, \(result.protocolExtensions) protocol, \(result.typeAliasExtensions) typealias, \(result.failed) failed")

        // MARK: Structured operations

        case .phaseOperationStarted(let phase, let operation):
            yield(.progress, .indexing, "Starting \(operationName(operation)) in \(phaseName(phase))")

        case .phaseOperationCompleted(let phase, let operation):
            yield(.info, .indexing, "\(operationName(operation)) in \(phaseName(phase)) completed")

        case .phaseOperationFailed(let phase, let operation, let error):
            yield(.error, .indexing, "\(operationName(operation)) in \(phaseName(phase)) failed", detail: String(describing: error))

        // MARK: Module collection

        case .moduleCollectionStarted:
            yield(.progress, .moduleCollection, "Collecting modules")

        case .moduleCollectionCompleted(let result):
            yield(.info, .moduleCollection, "Found \(result.moduleCount) modules", detail: result.modules.joined(separator: ", "))

        // MARK: Trace-level context events

        case .conformanceFound(let context):
            yield(.trace, .indexing, "\(context.typeName) : \(context.protocolName)")

        case .conformanceProcessingFailed(let context, let error):
            yield(.error, .indexing, "Conformance failed: \(context.typeName) : \(context.protocolName)", detail: String(describing: error))

        case .associatedTypeFound(let context):
            yield(.trace, .indexing, "Associated type: \(context.typeName) in \(context.protocolName)")

        case .associatedTypeProcessingFailed(let context, let error):
            yield(.error, .indexing, "Associated type failed: \(context.typeName) in \(context.protocolName)", detail: String(describing: error))

        case .conformanceExtensionCreated(let context):
            yield(.trace, .indexing, "Extension: \(context.typeName) : \(context.protocolName)")

        case .conformanceExtensionCreationFailed(let context, let error):
            yield(.error, .indexing, "Extension creation failed: \(context.typeName) : \(context.protocolName)", detail: String(describing: error))

        case .extensionTargetNotFound(let targetName):
            yield(.trace, .indexing, "Extension target not found: \(targetName)")

        case .extensionCreated(let context):
            yield(.trace, .indexing, "Extension: \(context.targetName) (\(context.memberCount) members)")

        case .extensionCreationFailed(let targetName, let error):
            yield(.error, .indexing, "Extension creation failed: \(targetName)", detail: String(describing: error))

        case .protocolProcessed(let context):
            yield(.trace, .indexing, "Protocol: \(context.protocolName) (\(context.requirementCount) requirements)")

        case .protocolProcessingFailed(let protocolName, let error):
            yield(.error, .indexing, "Protocol processing failed: \(protocolName)", detail: String(describing: error))

        case .moduleFound(let context):
            yield(.trace, .moduleCollection, "Found module: \(context.moduleName)")

        case .symbolScanStarted(let context):
            yield(.progress, .moduleCollection, "Scanning \(context.totalSymbols) symbols")

        case .nameExtractionWarning(let target):
            yield(.warning, .indexing, "Name extraction failed for \(target.description)")

        // MARK: Printing

        case .definitionPrintStarted(let context):
            yield(.trace, .printing, "Printing \(context.kind.description): \(context.name)")

        case .definitionPrintCompleted(let context):
            yield(.trace, .printing, "Printed \(context.kind.description): \(context.name)")

        case .definitionPrintFailed(let context, let error):
            yield(.error, .printing, "Failed to print \(context.kind.description): \(context.name)", detail: String(describing: error))
        }
    }

    // MARK: - Private

    private func yield(_ level: Report.Level, _ category: Report.Category, _ message: String, detail: String? = nil) {
        guard level >= minimumLevel else { return }
        continuation.yield(Report(level: level, category: category, message: message, detail: detail))
    }

    private func formatTypeIndexingDetail(_ result: SwiftInterfaceEvents.TypeIndexingResult) -> String {
        var parts: [String] = []
        if result.cImportedSkipped > 0 { parts.append("\(result.cImportedSkipped) C-imported skipped") }
        if result.nestedTypes > 0 { parts.append("\(result.nestedTypes) nested") }
        if result.extensionTypes > 0 { parts.append("\(result.extensionTypes) in extensions") }
        return parts.joined(separator: ", ")
    }

    private func phaseName(_ phase: SwiftInterfaceEvents.Phase) -> String {
        switch phase {
        case .preparation: return "preparation"
        case .extraction: return "extraction"
        case .indexing: return "indexing"
        case .moduleCollection: return "module collection"
        case .build: return "build"
        }
    }

    private func sectionName(_ section: SwiftInterfaceEvents.Section) -> String {
        switch section {
        case .swiftTypes: return "Swift types"
        case .swiftProtocols: return "Swift protocols"
        case .protocolConformances: return "protocol conformances"
        case .associatedTypes: return "associated types"
        }
    }

    private func operationName(_ operation: SwiftInterfaceEvents.PhaseOperation) -> String {
        switch operation {
        case .typeIndexing: return "type indexing"
        case .protocolIndexing: return "protocol indexing"
        case .conformanceIndexing: return "conformance indexing"
        case .extensionIndexing: return "extension indexing"
        }
    }
}
