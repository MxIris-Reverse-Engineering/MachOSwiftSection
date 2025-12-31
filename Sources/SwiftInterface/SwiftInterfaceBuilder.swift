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

    private let eventDispatcher: SwiftInterfaceEvents.Dispatcher

    @Mutex
    public var configuration: SwiftInterfaceBuilderConfiguration = .init()

    @Mutex
    private var typeDemangleResolver: DemangleResolver = .using(options: .default)

    @Mutex
    public private(set) var importedModules: OrderedSet<String> = []

    @Mutex
    public private(set) var extraDataProviders: [SwiftInterfaceBuilderExtraDataProvider] = []

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
        self.configuration = configuration
        eventDispatcher.addHandlers(eventHandlers)

        self.typeDemangleResolver = .using { [weak self] node in
            if let self {
                var printer = TypeNodePrinter(delegate: self)
                try await printer.printRoot(node)
            }
        }
    }

    public func addExtraDataProvider(_ extraDataProvider: any SwiftInterfaceBuilderExtraDataProvider) {
        extraDataProviders.append(extraDataProvider)
    }

    public func removeAllExtraDataProviders() {
        extraDataProviders.removeAll()
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

    @SemanticStringBuilder
    public func printRoot() async throws -> SemanticString {
        ImportsBlock(OrderedSet(Self.internalModules + importedModules).sorted())

        try await BlockList {
            for variable in indexer.globalVariableDefinitions {
                try await printVariable(variable, level: 0)
            }
        }

        try await BlockList {
            for function in indexer.globalFunctionDefinitions {
                try await printFunction(function)
            }
        }

        try await BlockList {
            for typeDefinition in indexer.rootTypeDefinitions.values {
                try await printTypeDefinition(typeDefinition)
            }
        }

        try await BlockList {
            for protocolDefinition in indexer.rootProtocolDefinitions.values {
                try await printProtocolDefinition(protocolDefinition)
            }
        }

        try await BlockList {
            for protocolDefinition in indexer.rootProtocolDefinitions.values.filterNonNil(\.parent) {
                for extensionDefinition in protocolDefinition.defaultImplementationExtensions {
                    try await printExtensionDefinition(extensionDefinition)
                }
            }
        }

        try await BlockList {
            for extensionDefinition in allExtensionDefinitions {
                try await printExtensionDefinition(extensionDefinition)
            }
        }
    }

    @_spi(Support)
    @SemanticStringBuilder
    public func printTypeDefinition(_ typeDefinition: TypeDefinition, level: Int = 1, displayParentName: Bool = false) async throws -> SemanticString {
        if !typeDefinition.isIndexed {
            try await typeDefinition.index(in: machO)
        }

        let dumper = typeDefinition.type.dumper(using: .init(demangleResolver: typeDemangleResolver, indentation: level, displayParentName: displayParentName, emitOffsetComments: configuration.printConfiguration.emitOffsetComments, printTypeLayout: configuration.printConfiguration.printTypeLayout, printEnumLayout: configuration.printConfiguration.printEnumLayout), in: machO)

        try await DeclarationBlock(level: level) {
            try await dumper.declaration
        } body: {
            for child in typeDefinition.typeChildren {
                try await NestedDeclaration {
                    try await printTypeDefinition(child, level: level + 1)
                }
            }

            for child in typeDefinition.protocolChildren {
                try await NestedDeclaration {
                    try await printProtocolDefinition(child, level: level + 1)
                }
            }

            try await dumper.fields

            try await printDefinition(typeDefinition, level: level)
        }
    }

    @_spi(Support)
    @SemanticStringBuilder
    public func printProtocolDefinition(_ protocolDefinition: ProtocolDefinition, level: Int = 1, displayParentName: Bool = false) async throws -> SemanticString {
        if !protocolDefinition.isIndexed {
            try await protocolDefinition.index(in: machO)
        }

        let dumper = ProtocolDumper(protocolDefinition.protocol, using: .init(demangleResolver: typeDemangleResolver, indentation: level, displayParentName: displayParentName, emitOffsetComments: configuration.printConfiguration.emitOffsetComments), in: machO)

        try await DeclarationBlock(level: level) {
            try await dumper.declaration
        } body: {
            try await dumper.associatedTypes

            try await printDefinition(protocolDefinition, level: level, offsetPrefix: "protocol witness table")

            if configuration.printConfiguration.printStrippedSymbolicItem, !protocolDefinition.strippedSymbolicRequirements.isEmpty {
                MemberList(level: level) {
                    for strippedSymbolicRequirement in protocolDefinition.strippedSymbolicRequirements {
                        strippedSymbolicRequirement.strippedSymbolicInfo()
                    }
                }
            }
        }

        if protocolDefinition.parent == nil {
            try await BlockList {
                for extensionDefinition in protocolDefinition.defaultImplementationExtensions {
                    try await printExtensionDefinition(extensionDefinition)
                }
            }
        }
    }

    @_spi(Support)
    @SemanticStringBuilder
    public func printExtensionDefinition(_ extensionDefinition: ExtensionDefinition, level: Int = 1) async throws -> SemanticString {
        if !extensionDefinition.isIndexed {
            try await extensionDefinition.index(in: machO)
        }

        try await DeclarationBlock(level: level) {
            Keyword(.extension)
            Space()
            extensionDefinition.extensionName.print()

            if let protocolConformance = extensionDefinition.protocolConformance,
               let protocolName = try? await protocolConformance.dumpProtocolName(using: .demangleOptions(.interfaceTypeBuilderOnly), in: machO) {
                Standard(":")
                Space()
                protocolName
            }

            if let genericSignature = extensionDefinition.genericSignature {
                let nodes = genericSignature.all(of: .requirementKinds)
                for (index, node) in nodes.enumerated() {
                    if index == 0 {
                        Space()
                        Keyword(.where)
                        Space()
                    }
                    try await printType(node, isProtocol: extensionDefinition.extensionName.isProtocol, level: level)
                    if index < nodes.count - 1 {
                        Standard(",")
                        Space()
                    }
                }
            }
        } body: {
            for typeDefinition in extensionDefinition.types {
                try await NestedDeclaration {
                    try await printTypeDefinition(typeDefinition, level: level + 1)
                }
            }

            for protocolDefinition in extensionDefinition.protocols {
                try await NestedDeclaration {
                    try await printProtocolDefinition(protocolDefinition, level: level + 1)
                }
            }

            if let associatedType = extensionDefinition.associatedType {
                let dumper = AssociatedTypeDumper(associatedType, using: .init(demangleResolver: typeDemangleResolver), in: machO)
                try await dumper.records
            }

            try await printDefinition(extensionDefinition, level: 1)
        }
    }

    @_spi(Support)
    @SemanticStringBuilder
    public func printDefinition(_ definition: some Definition, level: Int = 1, offsetPrefix: String = "") async throws -> SemanticString {
        if let mutableDefinition = definition as? MutableDefinition, !mutableDefinition.isIndexed {
            try await mutableDefinition.index(in: machO)
        }

        let emitOffset = configuration.printConfiguration.emitOffsetComments

        try await MemberList(level: level) {
            for allocator in definition.allocators {
                OffsetComment(prefix: "\(offsetPrefix) offset", offset: allocator.offset, emit: emitOffset)
                try await printFunction(allocator)
            }
        }

        try await MemberList(level: level) {
            for variable in definition.variables {
                OffsetComment(prefix: "\(offsetPrefix) offset", offset: variable.offset, emit: emitOffset)
                try await printVariable(variable, level: level)
            }
        }

        try await MemberList(level: level) {
            for function in definition.functions {
                OffsetComment(prefix: "\(offsetPrefix) offset", offset: function.offset, emit: emitOffset)
                try await printFunction(function)
            }
        }

        try await MemberList(level: level) {
            for `subscript` in definition.subscripts {
                OffsetComment(prefix: "\(offsetPrefix) offset", offset: `subscript`.offset, emit: emitOffset)
                try await printSubscript(`subscript`, level: level)
            }
        }

        try await MemberList(level: level) {
            for variable in definition.staticVariables {
                OffsetComment(prefix: "\(offsetPrefix) offset", offset: variable.offset, emit: emitOffset)
                try await printVariable(variable, level: level)
            }
        }

        try await MemberList(level: level) {
            for function in definition.staticFunctions {
                OffsetComment(prefix: "\(offsetPrefix) offset", offset: function.offset, emit: emitOffset)
                try await printFunction(function)
            }
        }

        try await MemberList(level: level) {
            for `subscript` in definition.staticSubscripts {
                OffsetComment(prefix: "\(offsetPrefix) offset", offset: `subscript`.offset, emit: emitOffset)
                try await printSubscript(`subscript`, level: level)
            }
        }
    }

    @_spi(Support)
    @SemanticStringBuilder
    public func printVariable(_ variable: VariableDefinition, level: Int) async throws -> SemanticString {
        var printer = VariableNodePrinter(isStored: variable.isStored, isOverride: variable.isOverride, hasSetter: variable.hasSetter, indentation: level, delegate: self)
        try await printer.printRoot(variable.node)
    }

    @_spi(Support)
    @SemanticStringBuilder
    public func printFunction(_ function: FunctionDefinition) async throws -> SemanticString {
        var printer = FunctionNodePrinter(isOverride: function.isOverride, delegate: self)
        try await printer.printRoot(function.node)
    }

    @_spi(Support)
    @SemanticStringBuilder
    public func printSubscript(_ `subscript`: SubscriptDefinition, level: Int) async throws -> SemanticString {
        var printer = SubscriptNodePrinter(isOverride: `subscript`.isOverride, hasSetter: `subscript`.hasSetter, indentation: level, delegate: self)
        try await printer.printRoot(`subscript`.node)
    }

    @_spi(Support)
    @SemanticStringBuilder
    public func printType(_ typeNode: Node, isProtocol: Bool, level: Int) async throws -> SemanticString {
        var printer = TypeNodePrinter(delegate: self, isProtocol: isProtocol)
        try await printer.printRoot(typeNode)
    }
}

extension SwiftInterfaceBuilder: NodePrintableDelegate {
    func moduleName(forTypeName typeName: String) async -> String? {
        await extraDataProviders.asyncFirstNonNil { await $0.moduleName(forTypeName: typeName) }
    }

    func swiftName(forCName cName: String) async -> String? {
        await extraDataProviders.asyncFirstNonNil { await $0.swiftName(forCName: cName) }
    }

    func opaqueType(forNode node: Node, index: Int?) async -> String? {
        await extraDataProviders.asyncFirstNonNil { await $0.opaqueType(forNode: node, index: index) }
    }
}
