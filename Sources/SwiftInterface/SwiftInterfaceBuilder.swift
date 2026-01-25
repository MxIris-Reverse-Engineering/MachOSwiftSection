import MachOSwiftSection
import MemberwiseInit
import OrderedCollections
import SwiftDump
import Demangling
import Semantic
import SwiftStdlibToolbox
import MachOKit
import Dependencies
import Utilities
@_spi(Internals) import MachOSymbols
@_spi(Internals) import MachOCaches

public final class SwiftInterfaceBuilder<MachO: MachOSwiftSectionRepresentableWithCache>: Sendable {
    private static var internalModules: [String] {
        ["Swift", "_Concurrency", "_StringProcessing", "_SwiftConcurrencyShims"]
    }

    public let machO: MachO

    @_spi(Support)
    public let indexer: SwiftInterfaceIndexer<MachO>

    @_spi(Support)
    public let printer: SwiftInterfacePrinter<MachO>

    @Mutex
    public var configuration: SwiftInterfaceBuilderConfiguration = .init()

    @Mutex
    public private(set) var importedModules: OrderedSet<String> = []

    @Mutex
    public private(set) var extraDataProviders: [SwiftInterfaceBuilderExtraDataProvider] = []

    private let eventDispatcher: SwiftInterfaceEvents.Dispatcher

    private var allExtensionDefinitions: [ExtensionDefinition] {
        (indexer.typeExtensionDefinitions.values.flatMap { $0 } + indexer.protocolExtensionDefinitions.values.flatMap { $0 } + indexer.typeAliasExtensionDefinitions.values.flatMap { $0 } + indexer.conformanceExtensionDefinitions.values.flatMap { $0 })
    }

    /// Creates a new Swift interface builder for the given Mach-O binary.
    ///
    /// - Parameters:
    ///   - configuration: Configuration options for the builder. Defaults to a basic configuration.
    ///   - eventDispatcher: An event dispatcher for handling logging and progress events. A new one is created by default.
    ///   - machO: The Mach-O binary to analyze and generate interfaces from.
    /// - Throws: An error if the binary cannot be read or if required Swift sections are missing.
    public init(configuration: SwiftInterfaceBuilderConfiguration = .init(), eventHandlers: [SwiftInterfaceEvents.Handler] = [], in machO: MachO) throws {
        self.eventDispatcher = .init()
        self.machO = machO
        self.indexer = .init(configuration: configuration.indexConfiguration, eventHandlers: eventHandlers, in: machO)
        self.printer = .init(configuration: configuration.printConfiguration, eventHandlers: eventHandlers, in: machO)
        self.configuration = configuration
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
                print(error)
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
        ImportsBlock(OrderedSet(Self.internalModules + importedModules).sorted())

        await printCatchedThrowing {
            await BlockList {
                for variable in indexer.globalVariableDefinitions {
                    await printer.printVariable(variable, level: 0)
                }
            }
        }

        await printCatchedThrowing {
            await BlockList {
                for function in indexer.globalFunctionDefinitions {
                    await printer.printFunction(function)
                }
            }
        }

        await printCatchedThrowing {
            try await BlockList {
                for typeDefinition in indexer.rootTypeDefinitions.values {
                    try await printer.printTypeDefinition(typeDefinition)
                }
            }
        }

        await printCatchedThrowing {
            try await BlockList {
                for protocolDefinition in indexer.rootProtocolDefinitions.values {
                    try await printer.printProtocolDefinition(protocolDefinition)
                }
            }
        }

        await printCatchedThrowing {
            try await BlockList {
                for protocolDefinition in indexer.rootProtocolDefinitions.values.filterNonNil(\.parent) {
                    for extensionDefinition in protocolDefinition.defaultImplementationExtensions {
                        try await printer.printExtensionDefinition(extensionDefinition)
                    }
                }
            }
        }

        await printCatchedThrowing {
            try await BlockList {
                for extensionDefinition in allExtensionDefinitions {
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

        eventDispatcher.dispatch(.symbolScanStarted(context: SwiftInterfaceEvents.SymbolScanContext(totalSymbols: allSymbols.count, filterModules: Array(filterModules.sorted()))))

        for symbol in allSymbols {
            for moduleNode in symbol.demangledNode.all(of: .module) {
                if let module = moduleNode.text, !filterModules.contains(module) {
                    if usedModules.append(module).inserted {
                        eventDispatcher.dispatch(.moduleFound(context: SwiftInterfaceEvents.ModuleContext(moduleName: module)))
                    }
                }
            }
        }

        importedModules = usedModules
        eventDispatcher.dispatch(.moduleCollectionCompleted(result: SwiftInterfaceEvents.ModuleCollectionResult(moduleCount: usedModules.count, modules: Array(usedModules.sorted()))))
    }
}
