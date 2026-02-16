import Foundation
import OSLog

/// A default event handler implementation that uses `OSLog` for logging.
@available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
public struct OSLogEventHandler: SwiftInterfaceEvents.Handler {
    private let logger: Logger

    public init(subsystem: String = "com.MxIris.MachOSwiftSection.SwiftInterface", category: String = "SwiftInterfaceBuilder") {
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    public func handle(event: SwiftInterfaceEvents.Payload) {
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
        }
    }

    private func operationName(_ operation: SwiftInterfaceEvents.PhaseOperation) -> String {
        switch operation {
        case .typeIndexing: return "Type indexing"
        case .protocolIndexing: return "Protocol indexing"
        case .conformanceIndexing: return "Conformance indexing"
        case .extensionIndexing: return "Extension indexing"
        }
    }

    private func logPhaseTransition(phase: SwiftInterfaceEvents.Phase, state: SwiftInterfaceEvents.State) {
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
}

/// A simple event handler that prints summary information to the console.
public struct ConsoleEventHandler: SwiftInterfaceEvents.Handler {
    public init() {}

    public func handle(event: SwiftInterfaceEvents.Payload) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)

        switch event {
        case .extractionCompleted(let result):
            print("[\(timestamp)] [INFO] Extracted \(result.count) \(sectionName(result.section))")

        case .typeIndexingCompleted(let result):
            print("[\(timestamp)] [INFO] Types: \(result.successful) successful, \(result.failed) failed, \(result.cImportedSkipped) C-imported skipped, \(result.nestedTypes) nested, \(result.extensionTypes) in extensions")

        case .protocolIndexingCompleted(let result):
            print("[\(timestamp)] [INFO] Protocols: \(result.successful) successful, \(result.failed) failed")

        case .conformanceIndexingCompleted(let result):
            print("[\(timestamp)] [INFO] Conformances: \(result.extensionCount) extensions, \(result.failedConformances + result.failedAssociatedTypes + result.failedExtensions) failed")

        case .extensionIndexingCompleted(let result):
            print("[\(timestamp)] [INFO] Extensions: \(result.typeExtensions) type, \(result.protocolExtensions) protocol, \(result.typeAliasExtensions) typealias, \(result.failed) failed")

        case .moduleCollectionCompleted(let result):
            print("[\(timestamp)] [INFO] Found \(result.moduleCount) modules to import")

        case .phaseTransition(let phase, let state):
            let phaseName = phaseName(phase)
            switch state {
            case .completed:
                print("[\(timestamp)] [SUCCESS] \(phaseName.capitalized) completed")
            case .failed(let error):
                print("[\(timestamp)] [ERROR] \(phaseName.capitalized) failed: \(String(describing: error))")
            case .started:
                break // Ignore started events for console output
            }

        case .definitionPrintFailed(let context, let error):
            print("[\(timestamp)] [ERROR] Failed to print \(context.kind.description) '\(context.name)': \(String(describing: error))")

        default:
            break // Ignore other detailed events
        }
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
}
