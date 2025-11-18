import Foundation
import os.log

/// A default event handler implementation that uses `OSLog` for logging.
public struct OSLogEventHandler: SwiftInterfaceEvents.Handler {
    private let logger: Logger
    
    public init(subsystem: String = "com.MxIris.MachOSwiftSection.SwiftInterface", category: String = "SwiftInterfaceBuilder") {
        self.logger = Logger(subsystem: subsystem, category: category)
    }
    
    public func handle(event: SwiftInterfaceEvents.Payload) {
        switch event {
        case .phaseTransition(let phase, let state):
            logPhaseTransition(phase: phase, state: state)
            
        case .initialization(let config):
            logger.info("Initializing SwiftInterfaceBuilder with configuration: isTypeIndexingEnabled=\(config.isTypeIndexingEnabled), showCImportedTypes=\(config.showCImportedTypes)")
            
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
            
        case .dependencyLoadingStarted(let input):
            logger.debug("Loading dependencies from \(input.paths) paths")
            
        case .dependencyLoadingCompleted(let result):
            logger.info("Successfully loaded \(result.loadedCount) total dependencies")
            
        case .dependencyLoadingFailed(let failure):
            logger.error("Failed to load dependency from path '\(failure.path)': \(String(describing: failure.error))")
            
        case .typeDatabaseIndexingStarted(let input):
            logger.debug("Indexing type database dependencies")
            logger.debug("Found \(input.dependencyModules.count) dependency modules: \(input.dependencyModules.joined(separator: ", "))")
            
        case .typeDatabaseIndexingCompleted:
            logger.debug("Type database indexing completed successfully")
            
        case .typeDatabaseIndexingFailed(let error):
            logger.error("Failed to index type database dependencies: \(String(describing: error))")

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
            
        case .dependencyLoadSuccess(let context):
            if let count = context.count {
                logger.debug("Successfully loaded \(count) dependencies from: \(context.path)")
            } else {
                logger.debug("Successfully loaded Mach-O dependency from: \(context.path)")
            }
        case .dependencyLoadWarning(let warning):
            logger.warning("\(warning.reason.description) at path: \(warning.path)")
            
        case .typeDatabaseSkipped(let reason):
            logger.debug("Type database operation skipped: \(reason.description)")
            
        case .nameExtractionWarning(let target):
            logger.warning("Failed to extract type name or protocol name from \(target.description).")
            
        case .diagnostic(let message):
            logDiagnostic(message)
        }
    }
    
    private func operationName(_ operation: SwiftInterfaceEvents.PhaseOperation) -> String {
        switch operation {
        case .typeIndexing: return "Type indexing"
        case .protocolIndexing: return "Protocol indexing"
        case .conformanceIndexing: return "Conformance indexing"
        case .extensionIndexing: return "Extension indexing"
        case .dependencyIndexing: return "Dependency indexing"
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
    
    private func logDiagnostic(_ message: SwiftInterfaceEvents.DiagnosticMessage) {
        let text = message.message
        switch message.level {
        case .warning:
            logger.warning("\(text)")
        case .error:
            if let error = message.error {
                logger.error("\(text): \(String(describing: error))")
            } else {
                logger.error("\(text)")
            }
        case .debug:
            logger.debug("\(text)")
        case .trace:
            logger.trace("\(text)")
        }
    }
    
    private func phaseName(_ phase: SwiftInterfaceEvents.Phase) -> String {
        switch phase {
        case .initialization: return "initialization"
        case .preparation: return "preparation"
        case .extraction: return "extraction"
        case .indexing: return "indexing"
        case .moduleCollection: return "module collection"
        case .dependencyLoading: return "dependency loading"
        case .typeDatabaseIndexing: return "type database indexing"
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
        case .initialization(let config):
            print("[\(timestamp)] [INFO] Initializing SwiftInterfaceBuilder (indexing: \(config.isTypeIndexingEnabled), showCImported: \(config.showCImportedTypes))")
            
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
            
        case .dependencyLoadingCompleted(let result):
            print("[\(timestamp)] [INFO] Loaded \(result.loadedCount) dependencies")
            
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
        
        case .dependencyLoadWarning(let warning):
            print("[\(timestamp)] [WARNING] \(warning.reason.description) at path: \(warning.path)")

        case .diagnostic(let message):
            switch message.level {
            case .error:
                if let error = message.error {
                    print("[\(timestamp)] [ERROR] \(message.message): \(String(describing: error))")
                } else {
                    print("[\(timestamp)] [ERROR] \(message.message)")
                }
            case .warning:
                print("[\(timestamp)] [WARNING] \(message.message)")
            case .debug, .trace:
                break // Ignore debug/trace for console output
            }
            
        default:
            break // Ignore other detailed events
        }
    }
    
    private func phaseName(_ phase: SwiftInterfaceEvents.Phase) -> String {
        switch phase {
        case .initialization: return "initialization"
        case .preparation: return "preparation"
        case .extraction: return "extraction"
        case .indexing: return "indexing"
        case .moduleCollection: return "module collection"
        case .dependencyLoading: return "dependency loading"
        case .typeDatabaseIndexing: return "type database indexing"
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
