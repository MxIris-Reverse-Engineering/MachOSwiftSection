import Foundation
import SwiftStdlibToolbox

/// A namespace for all event-related types used by `SwiftInterfaceBuilder`.
public enum SwiftInterfaceEvents {
    /// The payload for a dispatched event, containing structured data about the builder's progress and state.
    public enum Payload {
        /// Phase-based events
        case phaseTransition(phase: Phase, state: State)

        // Extraction events
        case extractionStarted(section: Section)
        case extractionCompleted(result: ExtractionResult)
        case extractionFailed(section: Section, error: any Error)

        // Indexing events
        case typeIndexingStarted(totalTypes: Int)
        case typeIndexingCompleted(result: TypeIndexingResult)
        case protocolIndexingStarted(totalProtocols: Int)
        case protocolIndexingCompleted(result: ProtocolIndexingResult)
        case conformanceIndexingStarted(input: ConformanceIndexingInput)
        case conformanceIndexingCompleted(result: ConformanceIndexingResult)
        case extensionIndexingStarted
        case extensionIndexingCompleted(result: ExtensionIndexingResult)

        // Module collection events
        case moduleCollectionStarted
        case moduleCollectionCompleted(result: ModuleCollectionResult)

        // Structured operation events
        case phaseOperationStarted(phase: Phase, operation: PhaseOperation)
        case phaseOperationCompleted(phase: Phase, operation: PhaseOperation)
        case phaseOperationFailed(phase: Phase, operation: PhaseOperation, error: any Error)

        // Structured context events
        case conformanceFound(context: ConformanceContext)
        case conformanceProcessingFailed(context: ConformanceContext, error: any Error)
        case associatedTypeFound(context: ConformanceContext)
        case associatedTypeProcessingFailed(context: ConformanceContext, error: any Error)
        case conformanceExtensionCreated(context: ConformanceContext)
        case conformanceExtensionCreationFailed(context: ConformanceContext, error: any Error)

        case extensionTargetNotFound(targetName: String)
        case extensionCreated(context: ExtensionContext)
        case extensionCreationFailed(targetName: String, error: any Error)

        case protocolProcessed(context: ProtocolContext)
        case protocolProcessingFailed(protocolName: String, error: any Error)

        case moduleFound(context: ModuleContext)
        case symbolScanStarted(context: SymbolScanContext)

        case nameExtractionWarning(for: NameExtractionTarget)

        // Printing events
        case definitionPrintStarted(context: PrintingContext)
        case definitionPrintCompleted(context: PrintingContext)
        case definitionPrintFailed(context: PrintingContext, error: any Error)
    }

    /// A protocol for types that can handle events dispatched from `SwiftInterfaceBuilder`.
    public protocol Handler {
        func handle(event: Payload)
    }

    /// Dispatches `SwiftInterfaceBuilder` events to registered handlers.
    public final class Dispatcher: Sendable {
        @Mutex
        private var handlers: [Handler] = []

        public init() {}

        public func addHandler(_ handler: Handler) {
            handlers.append(handler)
        }

        public func addHandlers(_ newHandlers: [Handler]) {
            handlers.append(contentsOf: newHandlers)
        }

        public func removeAllHandlers() {
            handlers.removeAll()
        }

        public func dispatch(_ event: Payload) {
            for handler in handlers {
                handler.handle(event: event)
            }
        }
    }

    // MARK: - Nested Types

    /// Represents different phases of the Swift interface building process.
    public enum Phase: Sendable {
        case preparation
        case extraction
        case indexing
        case moduleCollection
        case build
    }

    /// Represents the current state of a `Phase` or operation.
    public enum State: Sendable {
        case started
        case completed
        case failed(any Error)
    }

    /// Represents a specific section of data within the Mach-O file being processed.
    public enum Section: Sendable {
        case swiftTypes
        case swiftProtocols
        case protocolConformances
        case associatedTypes
    }

    /// Specifies a distinct operation within a larger `Phase`.
    public enum PhaseOperation: Sendable {
        case typeIndexing
        case protocolIndexing
        case conformanceIndexing
        case extensionIndexing
    }

    /// Identifies the target for a name extraction operation that resulted in a warning.
    public enum NameExtractionTarget: Sendable, CustomStringConvertible {
        case protocolConformance
        case associatedType

        public var description: String {
            switch self {
            case .protocolConformance: return "protocol conformance"
            case .associatedType: return "associated type"
            }
        }
    }

    // MARK: - Context and Result Structs

    public struct ExtractionResult: Sendable {
        public let section: Section
        public let count: Int
    }

    public struct TypeIndexingResult: Sendable {
        public let totalProcessed: Int
        public let successful: Int
        public let failed: Int
        public let cImportedSkipped: Int
        public let nestedTypes: Int
        public let extensionTypes: Int
    }

    public struct ProtocolIndexingResult: Sendable {
        public let totalProcessed: Int
        public let successful: Int
        public let failed: Int
    }

    public struct ConformanceIndexingInput: Sendable {
        public let totalConformances: Int
        public let totalAssociatedTypes: Int
    }

    public struct ConformanceIndexingResult: Sendable {
        public let conformedTypes: Int
        public let associatedTypeCount: Int
        public let extensionCount: Int
        public let failedConformances: Int
        public let failedAssociatedTypes: Int
        public let failedExtensions: Int
    }

    public struct ExtensionIndexingResult: Sendable {
        public let typeExtensions: Int
        public let protocolExtensions: Int
        public let typeAliasExtensions: Int
        public let failed: Int
    }

    public struct ModuleCollectionResult: Sendable {
        public let moduleCount: Int
        public let modules: [String]
    }

    public struct ConformanceContext: Sendable {
        public let typeName: String
        public let protocolName: String
    }

    public struct ExtensionContext: Sendable {
        public let targetName: String
        public let memberCount: Int
    }

    public struct ProtocolContext: Sendable {
        public let protocolName: String
        public let requirementCount: Int
    }

    public struct ModuleContext: Sendable {
        public let moduleName: String
    }

    public struct SymbolScanContext: Sendable {
        public let totalSymbols: Int
        public let filterModules: [String]
    }

    public struct PrintingContext: Sendable {
        public let name: String
        public let kind: PrintingDefinitionKind
    }

    public enum PrintingDefinitionKind: Sendable, CustomStringConvertible {
        case type
        case `protocol`
        case `extension`
        case variable
        case function
        case `subscript`

        public var description: String {
            switch self {
            case .type: return "type"
            case .protocol: return "protocol"
            case .extension: return "extension"
            case .variable: return "variable"
            case .function: return "function"
            case .subscript: return "subscript"
            }
        }
    }
}
