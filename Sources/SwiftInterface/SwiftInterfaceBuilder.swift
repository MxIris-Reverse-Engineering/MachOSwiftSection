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

    private let indexer: SwiftInterfaceIndexer<MachO>

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
        for module in OrderedSet(Self.internalModules + importedModules).sorted() {
            Standard("import \(module)")
            BreakLine()
        }

        for (offset, variable) in indexer.globalVariableDefinitions.offsetEnumerated() {
            BreakLine()

            try await printVariable(variable, level: 0)

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, function) in indexer.globalFunctionDefinitions.offsetEnumerated() {
            BreakLine()

            try await printFunction(function)

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, typeDefinition) in indexer.rootTypeDefinitions.values.offsetEnumerated() {
            BreakLine()

            try await printTypeDefinition(typeDefinition)

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, protocolDefinition) in indexer.rootProtocolDefinitions.values.offsetEnumerated() {
            BreakLine()

            try await printProtocolDefinition(protocolDefinition)

            if offset.isEnd {
                BreakLine()
            }
        }

        for protocolDefinition in indexer.rootProtocolDefinitions.values.filterNonNil(\.parent) {
            for (offset, extensionDefinition) in protocolDefinition.defaultImplementationExtensions.offsetEnumerated() {
                BreakLine()

                try await printExtensionDefinition(extensionDefinition)

                if offset.isEnd {
                    BreakLine()
                }
            }
        }

        for (offset, extensionDefinition) in allExtensionDefinitions.offsetEnumerated() {
            BreakLine()

            try await printExtensionDefinition(extensionDefinition)

            if offset.isEnd {
                BreakLine()
            }
        }
    }

    @_spi(Support)
    @SemanticStringBuilder
    public func printTypeDefinition(_ typeDefinition: TypeDefinition, level: Int = 1, displayParentName: Bool = false) async throws -> SemanticString {
        if !typeDefinition.isIndexed {
            try await typeDefinition.index(in: machO)
        }

        let dumper = typeDefinition.type.dumper(using: .init(demangleResolver: typeDemangleResolver, indentation: level, displayParentName: displayParentName, emitOffsetComments: configuration.printConfiguration.emitOffsetComments), in: machO)

        Indent(level: level - 1)

        try await dumper.declaration

        Space()
        Standard("{")

        for child in typeDefinition.typeChildren {
            BreakLine()
            try await printTypeDefinition(child, level: level + 1)
        }

        for child in typeDefinition.protocolChildren {
            BreakLine()
            try await printProtocolDefinition(child, level: level + 1)
        }

        try await dumper.fields

        try await printDefinition(typeDefinition, level: level)

        if typeDefinition.hasMembers || typeDefinition.typeChildren.count > 0 || typeDefinition.protocolChildren.count > 0 {
            if !typeDefinition.hasMembers {
                BreakLine()
            }
            Indent(level: level - 1)
        }

        Standard("}")
    }

    @_spi(Support)
    @SemanticStringBuilder
    public func printProtocolDefinition(_ protocolDefinition: ProtocolDefinition, level: Int = 1, displayParentName: Bool = false) async throws -> SemanticString {
        if !protocolDefinition.isIndexed {
            try await protocolDefinition.index(in: machO)
        }

        let dumper = ProtocolDumper(protocolDefinition.protocol, using: .init(demangleResolver: typeDemangleResolver, indentation: level, displayParentName: displayParentName, emitOffsetComments: configuration.printConfiguration.emitOffsetComments), in: machO)

        Indent(level: level - 1)

        try await dumper.declaration

        Space()

        Standard("{")

        try await dumper.associatedTypes

        try await printDefinition(protocolDefinition, level: level, offsetPrefix: "protocol witness table")

        if configuration.printConfiguration.printStrippedSymbolicItem, !protocolDefinition.strippedSymbolicRequirements.isEmpty {
            for (offset, strippedSymbolicRequirement) in protocolDefinition.strippedSymbolicRequirements.offsetEnumerated() {
                BreakLine()
                Indent(level: level)
                strippedSymbolicRequirement.strippedSymbolicInfo()
                if offset.isEnd {
                    BreakLine()
                }
            }
        }

        if protocolDefinition.hasMembers {
            Indent(level: level - 1)
        }

        Standard("}")

        if protocolDefinition.parent == nil {
            for (offset, extensionDefinition) in protocolDefinition.defaultImplementationExtensions.offsetEnumerated() {
                BreakLine()
                try await printExtensionDefinition(extensionDefinition)
                if offset.isEnd {
                    BreakLine()
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
        Keyword(.extension)
        Space()
        extensionDefinition.extensionName.print()
        if let protocolConformance = extensionDefinition.protocolConformance, let protocolName = try? await protocolConformance.dumpProtocolName(using: .demangleOptions(.interfaceTypeBuilderOnly), in: machO) {
            Standard(":")
            Space()
            protocolName
        }
        if let genericSignature = extensionDefinition.genericSignature {
            let nodes = genericSignature.all(of: .requirementKinds)
            for (offset, node) in nodes.offsetEnumerated() {
                if offset.isStart {
                    Space()
                    Keyword(.where)
                    Space()
                }
                try await printType(node, isProtocol: extensionDefinition.extensionName.isProtocol, level: level)
                if !offset.isEnd {
                    Standard(",")
                    Space()
                }
            }
        }
        Space()
        Standard("{")

        for (offset, typeDefinition) in extensionDefinition.types.offsetEnumerated() {
            BreakLine()

            try await printTypeDefinition(typeDefinition, level: level + 1)

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, protocolDefinition) in extensionDefinition.protocols.offsetEnumerated() {
            BreakLine()

            try await printProtocolDefinition(protocolDefinition, level: level + 1)

            if offset.isEnd {
                BreakLine()
            }
        }

        if let associatedType = extensionDefinition.associatedType {
            let dumper = AssociatedTypeDumper(associatedType, using: .init(demangleResolver: typeDemangleResolver), in: machO)
            try await dumper.records
        }

        try await printDefinition(extensionDefinition, level: 1)

        Standard("}")
    }

    @_spi(Support)
    @SemanticStringBuilder
    public func printDefinition(_ definition: some Definition, level: Int = 1, offsetPrefix: String = "") async throws -> SemanticString {
        if let mutableDefinition = definition as? MutableDefinition, !mutableDefinition.isIndexed {
            try await mutableDefinition.index(in: machO)
        }

        for (offset, allocator) in definition.allocators.offsetEnumerated() {
            BreakLine()

            if let offset = allocator.offset, configuration.printConfiguration.emitOffsetComments {
                Indent(level: level)
                Comment("\(offsetPrefix) offset: 0x\(String(offset, radix: 16))")
                BreakLine()
            }

            Indent(level: level)

            try await printFunction(allocator)

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, variable) in definition.variables.offsetEnumerated() {
            BreakLine()

            if let offset = variable.offset, configuration.printConfiguration.emitOffsetComments {
                Indent(level: level)
                Comment("\(offsetPrefix) offset: 0x\(String(offset, radix: 16))")
                BreakLine()
            }

            Indent(level: level)

            try await printVariable(variable, level: level)

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, function) in definition.functions.offsetEnumerated() {
            BreakLine()

            if let offset = function.offset, configuration.printConfiguration.emitOffsetComments {
                Indent(level: level)
                Comment("\(offsetPrefix) offset: 0x\(String(offset, radix: 16))")
                BreakLine()
            }

            Indent(level: level)

            try await printFunction(function)

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, `subscript`) in definition.subscripts.offsetEnumerated() {
            BreakLine()

            if let offset = `subscript`.offset, configuration.printConfiguration.emitOffsetComments {
                Indent(level: level)
                Comment("\(offsetPrefix) offset: 0x\(String(offset, radix: 16))")
                BreakLine()
            }

            Indent(level: level)

            try await printSubscript(`subscript`, level: level)

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, variable) in definition.staticVariables.offsetEnumerated() {
            BreakLine()

            if let offset = variable.offset, configuration.printConfiguration.emitOffsetComments {
                Indent(level: level)
                Comment("\(offsetPrefix) offset: 0x\(String(offset, radix: 16))")
                BreakLine()
            }

            Indent(level: level)

            try await printVariable(variable, level: level)

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, function) in definition.staticFunctions.offsetEnumerated() {
            BreakLine()

            if let offset = function.offset, configuration.printConfiguration.emitOffsetComments {
                Indent(level: level)
                Comment("\(offsetPrefix) offset: 0x\(String(offset, radix: 16))")
                BreakLine()
            }

            Indent(level: level)

            try await printFunction(function)

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, `subscript`) in definition.staticSubscripts.offsetEnumerated() {
            BreakLine()

            if let offset = `subscript`.offset, configuration.printConfiguration.emitOffsetComments {
                Indent(level: level)
                Comment("\(offsetPrefix) offset: 0x\(String(offset, radix: 16))")
                BreakLine()
            }

            Indent(level: level)

            try await printSubscript(`subscript`, level: level)

            if offset.isEnd {
                BreakLine()
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
