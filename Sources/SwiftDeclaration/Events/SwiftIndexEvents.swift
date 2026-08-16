import MemberwiseInit
import Foundation
import FoundationToolbox
import SwiftStdlibToolbox

/// A namespace for all event-related types used by `SwiftInterfaceBuilder`.
public enum SwiftIndexEvents {
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
        case typeProcessed(context: TypeContext)
        case typeProcessingFailed(typeName: String?, error: any Error)
        case typeProcessingSkippedCImported
        case typeNestingResolved(context: TypeNestingContext)
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
        case symbolIndexProgress(currentCount: Int, totalCount: Int)

        case nameExtractionWarning(for: NameExtractionTarget)

        // Printing events
        case definitionPrintStarted(context: PrintingContext)
        case definitionPrintCompleted(context: PrintingContext)
        case definitionPrintFailed(context: PrintingContext, error: any Error)

        /// Something below the definition level degraded: the surrounding work
        /// kept its partial result and carried on, but a piece of it is missing.
        ///
        /// One case rather than one per site because every consumer treats them
        /// identically — record it and move on. ``DegradationSource`` carries
        /// which seam gave way; a site that later needs structured fields can
        /// graduate to its own case then.
        case renderingDegraded(context: DegradationContext, error: any Error)
    }

    /// A protocol for types that can handle events dispatched from `SwiftInterfaceBuilder`.
    public protocol Handler {
        func handle(event: Payload)
    }

    /// Dispatches `SwiftInterfaceBuilder` events to registered handlers.
    @Loggable(.private, subsystem: "com.machoswiftsection.swift-declaration", category: "SwiftIndexEvents.unhandled")
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
            // Read the handler list once. `@Mutex` takes the lock per access, so
            // testing emptiness and then iterating would be two separate critical
            // sections — the list can empty out in between, and the event would
            // reach neither the handlers nor the fallback.
            let currentHandlers = handlers
            guard currentHandlers.isEmpty else {
                for handler in currentHandlers {
                    handler.handle(event: event)
                }
                return
            }
            reportUnhandled(event)
        }

        /// Last-resort reporting for a failure dispatched with no handler attached.
        ///
        /// A library must not pick where diagnostics go — os_log is right for a
        /// GUI host (RuntimeViewer filters on subsystem/category) and wrong for a
        /// CLI, where the operator expects stderr and a piped/CI log. That is why
        /// the choice belongs to the host's `Handler`, and why this is only a
        /// floor: it guarantees that forgetting to attach one degrades to
        /// "somewhere findable" rather than to silence.
        ///
        /// Silence is the failure mode this exists to prevent: a dropped
        /// declaration that reports nowhere is indistinguishable from one that
        /// was compared and found equal, which is how a diff-path payload failure
        /// once turned `case foo(Payload)` into `case foo` unnoticed.
        ///
        /// Progress events are dropped here on purpose — losing a tick costs
        /// nothing, and logging every one of them would bury the failures.
        private func reportUnhandled(_ event: Payload) {
            guard let description = event.unhandledFailureDescription else { return }
            #log(.error, "no event handler attached; \(description, privacy: .public)")
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
        case symbolIndex
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

    @MemberwiseInit(.public)
    public struct ExtractionResult: Sendable {
        public let section: Section
        public let count: Int
    }

    @MemberwiseInit(.public)
    public struct TypeIndexingResult: Sendable {
        public let totalProcessed: Int
        public let successful: Int
        public let failed: Int
        public let cImportedSkipped: Int
        public let nestedTypes: Int
        public let extensionTypes: Int
    }

    @MemberwiseInit(.public)
    public struct ProtocolIndexingResult: Sendable {
        public let totalProcessed: Int
        public let successful: Int
        public let failed: Int
    }

    @MemberwiseInit(.public)
    public struct ConformanceIndexingInput: Sendable {
        public let totalConformances: Int
        public let totalAssociatedTypes: Int
    }

    @MemberwiseInit(.public)
    public struct ConformanceIndexingResult: Sendable {
        public let conformedTypes: Int
        public let associatedTypeCount: Int
        public let extensionCount: Int
        public let failedConformances: Int
        public let failedAssociatedTypes: Int
        public let failedExtensions: Int
    }

    @MemberwiseInit(.public)
    public struct ExtensionIndexingResult: Sendable {
        public let typeExtensions: Int
        public let protocolExtensions: Int
        public let typeAliasExtensions: Int
        public let failed: Int
    }

    @MemberwiseInit(.public)
    public struct ModuleCollectionResult: Sendable {
        public let moduleCount: Int
        public let modules: [String]
    }

    @MemberwiseInit(.public)
    public struct ConformanceContext: Sendable {
        public let typeName: String
        public let protocolName: String
    }

    @MemberwiseInit(.public)
    public struct ExtensionContext: Sendable {
        public let targetName: String
        public let memberCount: Int
    }

    @MemberwiseInit(.public)
    public struct ProtocolContext: Sendable {
        public let protocolName: String
        public let requirementCount: Int
    }

    @MemberwiseInit(.public)
    public struct ModuleContext: Sendable {
        public let moduleName: String
    }

    @MemberwiseInit(.public)
    public struct SymbolScanContext: Sendable {
        public let totalSymbols: Int
        public let filterModules: [String]
    }

    @MemberwiseInit(.public)
    public struct PrintingContext: Sendable {
        public let name: String
        public let kind: PrintingDefinitionKind
    }

    /// Identifies what degraded, for ``Payload/renderingDegraded(context:error:)``.
    public struct DegradationContext: Sendable {
        public let source: DegradationSource

        /// What was being rendered when the seam gave way, when the site knows
        /// it — a type name, a dependency path. `nil` where the failure has no
        /// single subject (an index that failed as a whole).
        public let subject: String?

        public init(source: DegradationSource, subject: String? = nil) {
            self.source = source
            self.subject = subject
        }
    }

    /// The seam that gave way in a ``Payload/renderingDegraded(context:error:)``.
    public enum DegradationSource: Sendable, CustomStringConvertible {
        /// An opaque type's underlying type could not be substituted in, so the
        /// opaque type prints as itself.
        case opaqueTypeRewrite
        /// The image's `__swift5_mpenum` index could not be built, so every
        /// multi-payload enum in it falls back to the tagged projection.
        case multiPayloadEnumIndex
        /// A dependency image (or the dyld shared cache) failed to load, so
        /// cross-module resolution against it is unavailable.
        case dependencyLoad
        /// A subclass could not be materialized into the class hierarchy map.
        case subclassMap
        /// An extra-data provider failed to set up; its enrichment is absent.
        case extraDataProvider
        /// A type node could not be rendered. Reported without a definition
        /// identity because the node is a fragment — an enum case's payload, a
        /// property's type — and the enclosing definition keeps rendering.
        case typeNodeRendering
        /// One of `printRoot()`'s top-level blocks failed as a whole. Its
        /// members already report individually, so this has no single subject.
        case definitionBlock

        public var description: String {
            switch self {
            case .opaqueTypeRewrite: "opaque type rewrite"
            case .multiPayloadEnumIndex: "multi-payload enum index"
            case .dependencyLoad: "dependency load"
            case .subclassMap: "subclass map"
            case .extraDataProvider: "extra data provider"
            case .typeNodeRendering: "type node rendering"
            case .definitionBlock: "definition block"
            }
        }
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

    @MemberwiseInit(.public)
    public struct TypeContext: Sendable {
        public let typeName: String
        public let kind: TypeKind
    }

    @MemberwiseInit(.public)
    public struct TypeNestingContext: Sendable {
        public let childTypeName: String
        public let parentTypeName: String?
    }
}

extension SwiftIndexEvents.Payload {
    /// A one-line description when this event reports a loss, `nil` when it only
    /// reports progress.
    ///
    /// This is the partition `Dispatcher`'s zero-handler fallback runs on, and
    /// the reason it is a whitelist rather than `default: nil` inverted: a new
    /// failure case added without a branch here would silently opt out of the
    /// floor, which is exactly the class of regression the floor exists to stop.
    package var unhandledFailureDescription: String? {
        switch self {
        case let .phaseTransition(phase, state):
            guard case let .failed(error) = state else { return nil }
            return "\(phase) phase failed: \(error)"
        case let .extractionFailed(section, error):
            return "extraction failed for \(section): \(error)"
        case let .typeProcessingFailed(typeName, error):
            return "type processing failed for \(typeName ?? "<unnamed>"): \(error)"
        case let .phaseOperationFailed(phase, operation, error):
            return "\(operation) failed in the \(phase) phase: \(error)"
        case let .conformanceProcessingFailed(context, error):
            return "conformance processing failed for \(context): \(error)"
        case let .associatedTypeProcessingFailed(context, error):
            return "associated type processing failed for \(context): \(error)"
        case let .conformanceExtensionCreationFailed(context, error):
            return "conformance extension creation failed for \(context): \(error)"
        case let .extensionCreationFailed(targetName, error):
            return "extension creation failed for \(targetName): \(error)"
        case let .protocolProcessingFailed(protocolName, error):
            return "protocol processing failed for \(protocolName): \(error)"
        case let .definitionPrintFailed(context, error):
            return "dropped \(context.kind) '\(context.name)': \(error)"
        case let .renderingDegraded(context, error):
            let subject = context.subject.map { " for \($0)" } ?? ""
            return "\(context.source) degraded\(subject): \(error)"
        case .phaseOperationStarted, .phaseOperationCompleted,
             .extractionStarted, .extractionCompleted,
             .typeIndexingStarted, .typeIndexingCompleted, .typeProcessed,
             .typeProcessingSkippedCImported, .typeNestingResolved,
             .protocolIndexingStarted, .protocolIndexingCompleted,
             .conformanceIndexingStarted, .conformanceIndexingCompleted,
             .extensionIndexingStarted, .extensionIndexingCompleted,
             .moduleCollectionStarted, .moduleCollectionCompleted,
             .conformanceFound, .associatedTypeFound, .conformanceExtensionCreated,
             .extensionTargetNotFound, .extensionCreated,
             .protocolProcessed, .moduleFound,
             .symbolScanStarted, .symbolIndexProgress,
             .nameExtractionWarning,
             .definitionPrintStarted, .definitionPrintCompleted:
            return nil
        }
    }
}
