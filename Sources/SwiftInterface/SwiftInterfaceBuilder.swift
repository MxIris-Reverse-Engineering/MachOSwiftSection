import Foundation
import SwiftDeclaration
@_spi(Support) import SwiftIndexing
@_spi(Support) import SwiftPrinting
@_spi(Support) import SwiftSpecialization
import MachOSwiftSection
import MemberwiseInit
import OrderedCollections
import SwiftDeclarationRendering
import Demangling
import Semantic
import SwiftStdlibToolbox
import MachOKit
import Dependencies
import Utilities
@_spi(Internals) import MachOSymbols
@_spi(Internals) import MachOCaches

public final class SwiftInterfaceBuilder<MachO: FieldLayoutRenderable>: Sendable {
    private static var internalModules: [String] {
        ["Swift", "_Concurrency", "_StringProcessing", "_SwiftConcurrencyShims"]
    }

    public let machO: MachO

    @_spi(Support)
    public let indexer: SwiftDeclarationIndexer<MachO>

    @_spi(Support)
    public let printer: SwiftDeclarationPrinter<MachO>

    @Mutex
    public var configuration: SwiftInterfaceBuilderConfiguration = .init()

    @Mutex
    public private(set) var importedModules: OrderedSet<String> = []

    @Mutex
    public private(set) var extraDataProviders: [SwiftInterfaceBuilderExtraDataProvider] = []

    private let eventDispatcher: SwiftIndexEvents.Dispatcher

    private var allExtensionDefinitions: [ExtensionDefinition] {
        // Attached definitions render trailing their protocol declaration
        // (evolution proposal 0007) — repeating them here was the duplicate
        // `extension P` block issue #106 §5 reported.
        (indexer.typeExtensionDefinitions.values.flatMap { $0 } + indexer.protocolExtensionDefinitions.values.flatMap { $0 } + indexer.typeAliasExtensionDefinitions.values.flatMap { $0 } + indexer.conformanceExtensionDefinitions.values.flatMap { $0 })
            .filter { !$0.isAttachedToProtocolDefinition }
    }

    /// Creates a new Swift interface builder for the given Mach-O binary.
    ///
    /// - Parameters:
    ///   - configuration: Configuration options for the builder. Defaults to a basic configuration.
    ///   - eventDispatcher: An event dispatcher for handling logging and progress events. A new one is created by default.
    ///   - machO: The Mach-O binary to analyze and generate interfaces from.
    /// - Throws: An error if the binary cannot be read or if required Swift sections are missing.
    public init(configuration: SwiftInterfaceBuilderConfiguration = .init(), eventHandlers: [SwiftIndexEvents.Handler] = [], in machO: MachO) throws {
        self.eventDispatcher = .init()
        self.machO = machO
        self.indexer = .init(configuration: configuration.indexConfiguration, eventHandlers: eventHandlers, in: machO)
        self.printer = .init(configuration: configuration.printConfiguration, eventHandlers: eventHandlers, in: machO)
        self.configuration = configuration
        eventDispatcher.addHandlers(eventHandlers)
    }

    @_spi(Support)
    public init(indexer: SwiftDeclarationIndexer<MachO>, printer: SwiftDeclarationPrinter<MachO>, eventHandlers: [SwiftIndexEvents.Handler] = [], in machO: MachO) {
        self.eventDispatcher = .init()
        self.machO = machO
        self.indexer = indexer
        self.printer = printer
        self.configuration = .init(indexConfiguration: indexer.configuration, printConfiguration: printer.configuration)
        eventDispatcher.addHandlers(eventHandlers)
    }
    
    public func addExtraDataProvider(_ extraDataProvider: some SwiftInterfaceBuilderExtraDataProvider) {
        extraDataProviders.append(extraDataProvider)
        printer.addTypeNameResolver(extraDataProvider)
    }

    public func removeAllExtraDataProviders() {
        extraDataProviders.removeAll()
        printer.removeAllTypeNameResolvers()
    }

    /// Prepares the builder by indexing all symbols and collecting module information.
    /// This is an asynchronous operation that must be called before generating interfaces.
    ///
    /// The preparation process includes:
    /// - Indexing all types, protocols, and extensions
    /// - Building cross-reference maps for conformances and associated types
    /// - Collecting all required module imports
    ///
    /// - Throws: An error if indexing fails or if required data cannot be extracted.
    public func prepare() async throws {
        eventDispatcher.dispatch(.phaseTransition(phase: .preparation, state: .started))

        for extraDataProvider in extraDataProviders {
            do {
                try await extraDataProvider.setup()
            } catch {
                eventDispatcher.dispatch(
                    .renderingDegraded(context: .init(source: .extraDataProvider), error: error)
                )
            }
        }

        do {
            try await indexer.prepare()
        } catch {
            eventDispatcher.dispatch(.phaseTransition(phase: .indexing, state: .failed(error)))
            throw error
        }

        do {
            try await collectModules()
        } catch {
            eventDispatcher.dispatch(.phaseTransition(phase: .moduleCollection, state: .failed(error)))
            throw error
        }

        eventDispatcher.dispatch(.phaseTransition(phase: .preparation, state: .completed))
    }

    @SemanticStringBuilder
    public func printRoot() async throws -> SemanticString {
        // Leading header (evolution proposal 0008), deliberately independent
        // of the imports block below — flag-gated, default absent.
        if let interfaceHeaderInfo = configuration.interfaceHeaderInfo {
            InterfaceHeaderBlock(interfaceHeaderInfo)
        }

        ImportsBlock(OrderedSet(Self.internalModules + importedModules).sorted())

        // The two globals blocks carry no printing context because they cannot
        // fail as a block: `printVariable` / `printFunction` are non-throwing —
        // each already catches per member and dispatches its own
        // `definitionPrintFailed`. These wrappers are belt-and-braces, so there
        // is no definition identity to attribute a block-level failure to, and
        // they report as `.definitionBlock` degradations instead.
        await printCatchedThrowing(dispatchingTo: eventDispatcher, degradationSource: .definitionBlock) {
            await BlockList {
                for variable in indexer.globalVariableDefinitions {
                    await printer.printVariable(variable, level: 0)
                }
            }
        }

        await printCatchedThrowing(dispatchingTo: eventDispatcher, degradationSource: .definitionBlock) {
            await BlockList {
                for function in indexer.globalFunctionDefinitions {
                    await printer.printFunction(function, level: 0)
                }
            }
        }

        // Each definition is caught individually: one definition whose
        // printing throws (e.g. an unresolvable reference in a legacy or
        // damaged binary) drops only itself, never the whole block. A
        // block-level catch used to blank every type of the interface the
        // moment a single one threw.
        await BlockList {
            for typeDefinition in indexer.rootTypeDefinitions.values {
                await printCatchedThrowing(
                    dispatchingTo: eventDispatcher,
                    context: .init(name: typeDefinition.typeName.name, kind: .type)
                ) {
                    try await printer.printTypeDefinition(typeDefinition)
                }
            }
        }

        await BlockList {
            // Specialized variants live on each `TypeDefinition` rather
            // than on the indexer (the indexer is intentionally agnostic
            // of user-driven specialization). Walk every type definition
            // in the module and surface any specialized children it has
            // accumulated through `specialize(with:in:)`.
            for typeDefinition in indexer.allTypeDefinitions.values {
                for specialized in typeDefinition.specializedChildren {
                    await printCatchedThrowing(
                        dispatchingTo: eventDispatcher,
                        context: .init(name: specialized.typeName.name, kind: .type)
                    ) {
                        try await printer.printTypeDefinition(specialized)
                    }
                }
            }
        }

        await BlockList {
            for protocolDefinition in indexer.rootProtocolDefinitions.values {
                await printCatchedThrowing(
                    dispatchingTo: eventDispatcher,
                    context: .init(name: protocolDefinition.protocolName.name, kind: .protocol)
                ) {
                    try await printer.printProtocolDefinition(protocolDefinition)
                }
            }
        }

        await BlockList {
            // NESTED protocols' default-implementation / protocol-extension
            // blocks: the per-protocol printer emits them trailing TOP-LEVEL
            // protocol declarations only (extension blocks cannot nest inside
            // a parent's body), so nested protocols' blocks surface here at
            // the top level instead. This loop was dead before evolution
            // proposal 0007 — it filtered ROOT protocols on `parent != nil`,
            // which no root ever satisfies, so nested protocols' blocks never
            // printed at all.
            for protocolDefinition in indexer.allProtocolDefinitions.values where protocolDefinition.parent != nil {
                for extensionDefinition in protocolDefinition.defaultImplementationExtensions {
                    await printCatchedThrowing(
                        dispatchingTo: eventDispatcher,
                        context: .init(name: extensionDefinition.extensionName.name, kind: .extension)
                    ) {
                        try await printer.printExtensionDefinition(extensionDefinition)
                    }
                }
            }
        }

        await BlockList {
            for extensionDefinition in allExtensionDefinitions {
                await printCatchedThrowing(
                    dispatchingTo: eventDispatcher,
                    context: .init(name: extensionDefinition.extensionName.name, kind: .extension)
                ) {
                    try await printer.printExtensionDefinition(extensionDefinition)
                }
            }
        }
    }

    private func collectModules() async throws {
        eventDispatcher.dispatch(.moduleCollectionStarted)
        @Dependency(\.symbolIndexStore)
        var symbolIndexStore

        var usedModules: OrderedSet<String> = []
        let filterModules: Set<String> = [cModule, objcModule, stdlibName]
        let allSymbols = symbolIndexStore.allSymbols(in: machO)

        eventDispatcher.dispatch(.symbolScanStarted(context: SwiftIndexEvents.SymbolScanContext(totalSymbols: allSymbols.count, filterModules: Array(filterModules.sorted()))))

        for symbol in allSymbols {
            for moduleNode in symbol.demangledNode.all(of: .module) {
                if let module = moduleNode.text, !filterModules.contains(module) {
                    if usedModules.append(module).inserted {
                        eventDispatcher.dispatch(.moduleFound(context: SwiftIndexEvents.ModuleContext(moduleName: module)))
                    }
                }
            }
        }

        importedModules = usedModules
        eventDispatcher.dispatch(.moduleCollectionCompleted(result: SwiftIndexEvents.ModuleCollectionResult(moduleCount: usedModules.count, modules: Array(usedModules.sorted()))))
    }
}
