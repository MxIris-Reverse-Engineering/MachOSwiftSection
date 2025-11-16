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

    private let eventDispatcher: SwiftInterfaceBuilderEvents.Dispatcher

    @Mutex
    public var configuration: SwiftInterfaceBuilderConfiguration = .init()

    @Mutex
    private var typeDemangleResolver: DemangleResolver = .using(options: .default)

    @Mutex
    private var types: [TypeContextWrapper] = []

    @Mutex
    private var protocols: [MachOSwiftSection.`Protocol`] = []

    @Mutex
    private var protocolConformances: [ProtocolConformance] = []

    @Mutex
    private var associatedTypes: [AssociatedType] = []

    @Mutex
    private var protocolConformancesByTypeName: OrderedDictionary<TypeName, OrderedDictionary<ProtocolName, ProtocolConformance>> = [:]

    @Mutex
    private var associatedTypesByTypeName: OrderedDictionary<TypeName, OrderedDictionary<ProtocolName, AssociatedType>> = [:]

    @Mutex
    private var allNames: Set<String> = []

    @Mutex
    @_spi(Support) public private(set) var importedModules: OrderedSet<String> = []

    @Mutex
    @_spi(Support) public private(set) var rootTypeDefinitions: OrderedDictionary<TypeName, TypeDefinition> = [:]

    @Mutex
    @_spi(Support) public private(set) var allTypeDefinitions: OrderedDictionary<TypeName, TypeDefinition> = [:]

    @Mutex
    @_spi(Support) public private(set) var rootProtocolDefinitions: OrderedDictionary<ProtocolName, ProtocolDefinition> = [:]

    @Mutex
    @_spi(Support) public private(set) var allProtocolDefinitions: OrderedDictionary<ProtocolName, ProtocolDefinition> = [:]

    @Mutex
    @_spi(Support) public private(set) var typeExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> = [:]

    @Mutex
    @_spi(Support) public private(set) var protocolExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> = [:]

    @Mutex
    @_spi(Support) public private(set) var typeAliasExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> = [:]

    @Mutex
    @_spi(Support) public private(set) var conformanceExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> = [:]

    @Mutex
    @_spi(Support) public private(set) var globalVariableDefinitions: [VariableDefinition] = []

    @Mutex
    @_spi(Support) public private(set) var globalFunctionDefinitions: [FunctionDefinition] = []

    @Mutex
    @_spi(Support) public private(set) var extraDataProviders: [SwiftInterfaceBuilderExtraDataProvider] = []

    private var allExtensionDefinitions: [ExtensionDefinition] {
        (typeExtensionDefinitions.values.flatMap { $0 } + protocolExtensionDefinitions.values.flatMap { $0 } + typeAliasExtensionDefinitions.values.flatMap { $0 } + conformanceExtensionDefinitions.values.flatMap { $0 })
    }

    /// Creates a new Swift interface builder for the given Mach-O binary.
    ///
    /// - Parameters:
    ///   - configuration: Configuration options for the builder. Defaults to a basic configuration.
    ///   - eventDispatcher: An event dispatcher for handling logging and progress events. A new one is created by default.
    ///   - machO: The Mach-O binary to analyze and generate interfaces from.
    /// - Throws: An error if the binary cannot be read or if required Swift sections are missing.
    public init(configuration: SwiftInterfaceBuilderConfiguration = .init(), eventHandlers: [SwiftInterfaceBuilderEvents.Handler] = [], in machO: MachO) throws {
        self.eventDispatcher = .init()
        eventDispatcher.addHandlers(eventHandlers)
        self.machO = machO
        self.configuration = configuration

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
            eventDispatcher.dispatch(.extractionStarted(section: .swiftTypes))
            types = try machO.swift.types
            eventDispatcher.dispatch(.extractionCompleted(result: SwiftInterfaceBuilderEvents.ExtractionResult(section: .swiftTypes, count: types.count)))
        } catch {
            eventDispatcher.dispatch(.extractionFailed(section: .swiftTypes, error: error))
            types = []
        }

        do {
            eventDispatcher.dispatch(.extractionStarted(section: .swiftProtocols))
            protocols = try machO.swift.protocols
            eventDispatcher.dispatch(.extractionCompleted(result: SwiftInterfaceBuilderEvents.ExtractionResult(section: .swiftProtocols, count: protocols.count)))
        } catch {
            eventDispatcher.dispatch(.extractionFailed(section: .swiftProtocols, error: error))
            protocols = []
        }

        do {
            eventDispatcher.dispatch(.extractionStarted(section: .protocolConformances))
            protocolConformances = try machO.swift.protocolConformances
            eventDispatcher.dispatch(.extractionCompleted(result: SwiftInterfaceBuilderEvents.ExtractionResult(section: .protocolConformances, count: protocolConformances.count)))
        } catch {
            eventDispatcher.dispatch(.extractionFailed(section: .protocolConformances, error: error))
            protocolConformances = []
        }

        do {
            eventDispatcher.dispatch(.extractionStarted(section: .associatedTypes))
            associatedTypes = try machO.swift.associatedTypes
            eventDispatcher.dispatch(.extractionCompleted(result: SwiftInterfaceBuilderEvents.ExtractionResult(section: .associatedTypes, count: associatedTypes.count)))
        } catch {
            eventDispatcher.dispatch(.extractionFailed(section: .associatedTypes, error: error))
            associatedTypes = []
        }

        @Dependency(\.symbolIndexStore)
        var symbolIndexStore

        symbolIndexStore.prepare(in: machO)

        do {
            try await index()
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

    private func indexTypes() async throws {
        eventDispatcher.dispatch(.typeIndexingStarted(totalTypes: types.count))
        var allNames: Set<String> = []
        var currentModuleTypeDefinitions: OrderedDictionary<TypeName, TypeDefinition> = [:]
        var cImportedCount = 0
        var successfulCount = 0
        var failedCount = 0

        for type in types {
            if let isCImportedContext = try? type.contextDescriptorWrapper.contextDescriptor.isCImportedContextDescriptor(in: machO), !configuration.showCImportedTypes, isCImportedContext {
                cImportedCount += 1
                continue
            }

            do {
                let declaration = try await TypeDefinition(type: type, in: machO)
                currentModuleTypeDefinitions[declaration.typeName] = declaration
                allNames.insert(declaration.typeName.name)
                successfulCount += 1
            } catch {
                failedCount += 1
            }
        }

        var nestedTypeCount = 0
        var extensionTypeCount = 0

        for type in types {
            guard let typeName = try? type.typeName(in: machO), let childDefinition = currentModuleTypeDefinitions[typeName] else {
                continue
            }

            var parentContext = try ContextWrapper.type(type).parent(in: machO)

            parentLoop: while let currentContextOrSymbol = parentContext {
                switch currentContextOrSymbol {
                case .symbol(let symbol):
                    childDefinition.parentContext = .symbol(symbol)
                    break parentLoop
                case .element(let currentContext):
                    if case .type(let typeContext) = currentContext, let parentTypeName = try? typeContext.typeName(in: machO) {
                        if let parentDefinition = currentModuleTypeDefinitions[parentTypeName] {
                            childDefinition.parent = parentDefinition
                            parentDefinition.typeChildren.append(childDefinition)
                        } else {
                            childDefinition.parentContext = .type(typeContext)
                        }
                        nestedTypeCount += 1
                        break parentLoop
                    } else if case .extension(let extensionContext) = currentContext {
                        childDefinition.parentContext = .extension(extensionContext)
                        extensionTypeCount += 1
                        break parentLoop
                    }
                    parentContext = try currentContext.parent(in: machO)
                }
            }
        }

        var rootTypeDefinitions: OrderedDictionary<TypeName, TypeDefinition> = [:]

        for (typeName, typeDefinition) in currentModuleTypeDefinitions {
            if typeDefinition.parent == nil, typeDefinition.parentContext == nil {
                rootTypeDefinitions[typeName] = typeDefinition
            } else if let parentContext = typeDefinition.parentContext {
                switch parentContext {
                case .extension(let extensionContext):
                    guard let extendedContextMangledName = extensionContext.extendedContextMangledName else { continue }
                    guard let extensionTypeNode = try MetadataReader.demangleType(for: extendedContextMangledName, in: machO).first(of: .type) else { continue }
                    guard let extensionTypeKind = extensionTypeNode.typeKind else { continue }

                    let extensionTypeName = TypeName(node: extensionTypeNode, kind: extensionTypeKind)

                    var genericSignature: Node?

                    if let currentRequirements = extensionContext.genericContext?.currentRequirements(in: machO), !currentRequirements.isEmpty {
                        genericSignature = try MetadataReader.buildGenericSignature(for: currentRequirements, in: machO)
                    }

                    let extensionDefinition = try ExtensionDefinition(extensionName: extensionTypeName.extensionName, genericSignature: genericSignature, protocolConformance: nil, associatedType: nil, in: machO)
                    extensionDefinition.types = [typeDefinition]
                    typeExtensionDefinitions[extensionDefinition.extensionName, default: []].append(extensionDefinition)
                case .type(let parentType):
                    let parentTypeName = try parentType.typeName(in: machO)
                    let extensionDefinition = try ExtensionDefinition(extensionName: parentTypeName.extensionName, genericSignature: nil, protocolConformance: nil, associatedType: nil, in: machO)
                    extensionDefinition.types = [typeDefinition]
                    typeExtensionDefinitions[extensionDefinition.extensionName, default: []].append(extensionDefinition)
                case .symbol(let symbol):
                    guard let type = try MetadataReader.demangleType(for: symbol, in: machO)?.first(of: .type), let kind = type.typeKind else { continue }
                    let parentTypeName = TypeName(node: type, kind: kind)
                    let extensionDefinition = try ExtensionDefinition(extensionName: parentTypeName.extensionName, genericSignature: nil, protocolConformance: nil, associatedType: nil, in: machO)
                    extensionDefinition.types = [typeDefinition]
                    typeExtensionDefinitions[extensionDefinition.extensionName, default: []].append(extensionDefinition)
                }
            }
        }

        self.allNames = allNames
        self.rootTypeDefinitions = rootTypeDefinitions
        allTypeDefinitions = currentModuleTypeDefinitions

        eventDispatcher.dispatch(.typeIndexingCompleted(result: SwiftInterfaceBuilderEvents.TypeIndexingResult(totalProcessed: types.count, successful: successfulCount, failed: failedCount, cImportedSkipped: cImportedCount, nestedTypes: nestedTypeCount, extensionTypes: extensionTypeCount)))
    }

    private func indexProtocols() async throws {
        eventDispatcher.dispatch(.protocolIndexingStarted(totalProtocols: protocols.count))
        var rootProtocolDefinitions: OrderedDictionary<ProtocolName, ProtocolDefinition> = [:]
        var allProtocolDefinitions: OrderedDictionary<ProtocolName, ProtocolDefinition> = [:]
        var successfulCount = 0
        var failedCount = 0

        for proto in protocols {
            var protocolName: ProtocolName?
            do {
                let protocolDefinition = try ProtocolDefinition(protocol: proto, in: machO)
                protocolName = try proto.protocolName(in: machO)
                if let protocolName {
                    var parentContext = try ContextWrapper.protocol(proto).parent(in: machO)?.resolved
                    var isRoot = true
                    while let currentContext = parentContext {
                        if case .type(let typeContext) = currentContext, let parentTypeName = try? typeContext.typeName(in: machO) {
                            if let parentDefinition = allTypeDefinitions[parentTypeName] {
                                protocolDefinition.parent = parentDefinition
                                parentDefinition.protocolChildren.append(protocolDefinition)
                                isRoot = false
                            }
                            break
                        } else if case .extension(let extensionContext) = currentContext {
                            protocolDefinition.extensionContext = extensionContext
                            isRoot = false
                            break
                        }
                        parentContext = try currentContext.parent(in: machO)?.resolved
                    }
                    allProtocolDefinitions[protocolName] = protocolDefinition
                    if isRoot {
                        rootProtocolDefinitions[protocolName] = protocolDefinition
                    } else if let extensionContext = protocolDefinition.extensionContext, let extendedContextMangledName = extensionContext.extendedContextMangledName {
                        guard let typeNode = try MetadataReader.demangleType(for: extendedContextMangledName, in: machO).first(of: .type) else { continue }
                        guard let typeKind = typeNode.typeKind else { continue }
                        let typeName = TypeName(node: typeNode, kind: typeKind)
                        var genericSignature: Node?
                        if let currentRequirements = extensionContext.genericContext?.currentRequirements(in: machO), !currentRequirements.isEmpty {
                            genericSignature = try MetadataReader.buildGenericSignature(for: currentRequirements, in: machO)
                        }
                        let extensionDefinition = try ExtensionDefinition(extensionName: typeName.extensionName, genericSignature: genericSignature, protocolConformance: nil, associatedType: nil, in: machO)
                        extensionDefinition.protocols = [protocolDefinition]
                        typeExtensionDefinitions[extensionDefinition.extensionName, default: []].append(extensionDefinition)
                    }

                    allNames.insert(protocolName.name)

                    successfulCount += 1

                    eventDispatcher.dispatch(.protocolProcessed(context: SwiftInterfaceBuilderEvents.ProtocolContext(protocolName: protocolName.name, requirementCount: protocolDefinition.protocol.requirements.count)))
                } else {
                    failedCount += 1
                }
            } catch {
                eventDispatcher.dispatch(.protocolProcessingFailed(protocolName: protocolName?.name ?? "unknown", error: error))
                failedCount += 1
            }
        }

        self.rootProtocolDefinitions = rootProtocolDefinitions
        self.allProtocolDefinitions = allProtocolDefinitions
        eventDispatcher.dispatch(.protocolIndexingCompleted(result: SwiftInterfaceBuilderEvents.ProtocolIndexingResult(totalProcessed: protocols.count, successful: successfulCount, failed: failedCount)))
    }

    private func indexConformances() async throws {
        eventDispatcher.dispatch(.conformanceIndexingStarted(input: SwiftInterfaceBuilderEvents.ConformanceIndexingInput(totalConformances: protocolConformances.count, totalAssociatedTypes: associatedTypes.count)))
        var protocolConformancesByTypeName: OrderedDictionary<TypeName, OrderedDictionary<ProtocolName, ProtocolConformance>> = [:]
        var failedConformances = 0

        for conformance in protocolConformances {
            var typeName: TypeName?
            var protocolName: ProtocolName?
            do {
                typeName = try conformance.typeName(in: machO)
                protocolName = try conformance.protocolName(in: machO)
                if let typeName, let protocolName {
                    protocolConformancesByTypeName[typeName, default: [:]][protocolName] = conformance
                    eventDispatcher.dispatch(.conformanceFound(context: SwiftInterfaceBuilderEvents.ConformanceContext(typeName: typeName.name, protocolName: protocolName.name)))
                } else {
                    eventDispatcher.dispatch(.nameExtractionWarning(for: .protocolConformance))
                    failedConformances += 1
                }
            } catch {
                let context = SwiftInterfaceBuilderEvents.ConformanceContext(typeName: typeName?.name ?? "unknown", protocolName: protocolName?.name ?? "unknown")
                eventDispatcher.dispatch(.conformanceProcessingFailed(context: context, error: error))
                failedConformances += 1
            }
        }

        self.protocolConformancesByTypeName = protocolConformancesByTypeName

        var associatedTypesByTypeName: OrderedDictionary<TypeName, OrderedDictionary<ProtocolName, AssociatedType>> = [:]
        var failedAssociatedTypes = 0

        for associatedType in associatedTypes {
            var typeName: TypeName?
            var protocolName: ProtocolName?
            do {
                typeName = try associatedType.typeName(in: machO)
                protocolName = try associatedType.protocolName(in: machO)

                if let typeName, let protocolName {
                    associatedTypesByTypeName[typeName, default: [:]][protocolName] = associatedType
                    eventDispatcher.dispatch(.associatedTypeFound(context: SwiftInterfaceBuilderEvents.ConformanceContext(typeName: typeName.name, protocolName: protocolName.name)))
                } else {
                    eventDispatcher.dispatch(.nameExtractionWarning(for: .associatedType))
                    failedAssociatedTypes += 1
                }
            } catch {
                let context = SwiftInterfaceBuilderEvents.ConformanceContext(typeName: typeName?.name ?? "unknown", protocolName: protocolName?.name ?? "unknown")
                eventDispatcher.dispatch(.associatedTypeProcessingFailed(context: context, error: error))
                failedAssociatedTypes += 1
            }
        }
        self.associatedTypesByTypeName = associatedTypesByTypeName
        var associatedTypesByTypeNameCopy = associatedTypesByTypeName

        var conformanceExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> = [:]
        var extensionCount = 0
        var failedExtensions = 0

        for (typeName, protocolConformances) in protocolConformancesByTypeName {
            for (protocolName, protocolConformance) in protocolConformances {
                do {
                    let associatedType = associatedTypesByTypeNameCopy[typeName]?[protocolName]
                    if associatedType != nil {
                        associatedTypesByTypeNameCopy[typeName]?.removeValue(forKey: protocolName)
                        if associatedTypesByTypeNameCopy[typeName]?.isEmpty == true {
                            associatedTypesByTypeNameCopy.removeValue(forKey: typeName)
                        }
                    }

                    let extensionDefinition = try ExtensionDefinition(extensionName: typeName.extensionName, genericSignature: MetadataReader.buildGenericSignature(for: protocolConformance.conditionalRequirements, in: machO), protocolConformance: protocolConformance, associatedType: associatedType, in: machO)
                    conformanceExtensionDefinitions[extensionDefinition.extensionName, default: []].append(extensionDefinition)
                    extensionCount += 1
                    eventDispatcher.dispatch(.conformanceExtensionCreated(context: SwiftInterfaceBuilderEvents.ConformanceContext(typeName: typeName.name, protocolName: protocolName.name)))
                } catch {
                    let context = SwiftInterfaceBuilderEvents.ConformanceContext(typeName: typeName.name, protocolName: protocolName.name)
                    eventDispatcher.dispatch(.conformanceExtensionCreationFailed(context: context, error: error))
                    failedExtensions += 1
                }
            }
        }
        for (remainingTypeName, remainingAssociatedTypeByProtocolName) in associatedTypesByTypeNameCopy {
            for (_, remainingAssociatedType) in remainingAssociatedTypeByProtocolName {
                let extensionDefinition = try ExtensionDefinition(extensionName: remainingTypeName.extensionName, genericSignature: nil, protocolConformance: nil, associatedType: remainingAssociatedType, in: machO)
                conformanceExtensionDefinitions[extensionDefinition.extensionName, default: []].append(extensionDefinition)
            }
        }

        self.conformanceExtensionDefinitions = conformanceExtensionDefinitions
        eventDispatcher.dispatch(.conformanceIndexingCompleted(result: SwiftInterfaceBuilderEvents.ConformanceIndexingResult(conformedTypes: protocolConformancesByTypeName.count, associatedTypeCount: associatedTypesByTypeName.count, extensionCount: extensionCount, failedConformances: failedConformances, failedAssociatedTypes: failedAssociatedTypes, failedExtensions: failedExtensions)))
    }

    private func indexExtensions() async throws {
        eventDispatcher.dispatch(.extensionIndexingStarted)

        @Dependency(\.symbolIndexStore)
        var symbolIndexStore

        let memberSymbolsByName = await symbolIndexStore.memberSymbols(
            of: .allocator(inExtension: true),
            .variable(inExtension: true, isStatic: false, isStorage: false),
            .variable(inExtension: true, isStatic: true, isStorage: false),
            .variable(inExtension: true, isStatic: true, isStorage: true),
            .function(inExtension: true, isStatic: false),
            .function(inExtension: true, isStatic: true),
            .subscript(inExtension: true, isStatic: false),
            .subscript(inExtension: true, isStatic: true),
            excluding: [],
            in: machO
        )

        var typeExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> = [:]
        var protocolExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> = [:]
        var typeAliasExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> = [:]
        var typeExtensionCount = 0
        var protocolExtensionCount = 0
        var typeAliasExtensionCount = 0
        var failedExtensions = 0

        for (node, memberSymbols) in memberSymbolsByName {
            let name = node.print(using: .interfaceTypeBuilderOnly)
            guard let typeInfo = symbolIndexStore.typeInfo(for: name, in: machO) else {
                eventDispatcher.dispatch(.extensionTargetNotFound(targetName: name))
                continue
            }

            func extensionDefinition(of kind: ExtensionKind, for memberSymbolsByKind: OrderedDictionary<SymbolIndexStore.MemberKind, [DemangledSymbol]>, genericSignature: Node?) throws -> ExtensionDefinition {
                let extensionDefinition = try ExtensionDefinition(extensionName: .init(node: node, kind: kind), genericSignature: genericSignature, protocolConformance: nil, associatedType: nil, in: machO)
                var memberCount = 0

                for (kind, memberSymbols) in memberSymbolsByKind {
                    switch kind {
                    case .allocator(inExtension: true):
                        let allocators = DefinitionBuilder.allocators(for: memberSymbols.mapToDemangledSymbolWithOffset())
                        extensionDefinition.allocators.append(contentsOf: allocators)
                        memberCount += allocators.count
                    case .variable(inExtension: true, isStatic: false, isStorage: false):
                        let variables = DefinitionBuilder.variables(for: memberSymbols.mapToDemangledSymbolWithOffset(), fieldNames: [], isGlobalOrStatic: false)
                        extensionDefinition.variables.append(contentsOf: variables)
                        memberCount += variables.count
                    case .function(inExtension: true, isStatic: false):
                        let functions = DefinitionBuilder.functions(for: memberSymbols.mapToDemangledSymbolWithOffset(), isGlobalOrStatic: false)
                        extensionDefinition.functions.append(contentsOf: functions)
                        memberCount += functions.count
                    case .variable(inExtension: true, isStatic: true, _):
                        let staticVariables = DefinitionBuilder.variables(for: memberSymbols.mapToDemangledSymbolWithOffset(), fieldNames: [], isGlobalOrStatic: true)
                        extensionDefinition.staticVariables.append(contentsOf: staticVariables)
                        memberCount += staticVariables.count
                    case .function(inExtension: true, isStatic: true):
                        let staticFunctions = DefinitionBuilder.functions(for: memberSymbols.mapToDemangledSymbolWithOffset(), isGlobalOrStatic: true)
                        extensionDefinition.staticFunctions.append(contentsOf: staticFunctions)
                        memberCount += staticFunctions.count
                    case .subscript(inExtension: true, isStatic: false):
                        let subscripts = DefinitionBuilder.subscripts(for: memberSymbols.mapToDemangledSymbolWithOffset(), isStatic: false)
                        extensionDefinition.subscripts.append(contentsOf: subscripts)
                        memberCount += subscripts.count
                    case .subscript(inExtension: true, isStatic: true):
                        let staticSubscripts = DefinitionBuilder.subscripts(for: memberSymbols.mapToDemangledSymbolWithOffset(), isStatic: true)
                        extensionDefinition.staticSubscripts.append(contentsOf: staticSubscripts)
                        memberCount += staticSubscripts.count
                    default:
                        break
                    }
                }

                eventDispatcher.dispatch(.extensionCreated(context: SwiftInterfaceBuilderEvents.ExtensionContext(targetName: name, memberCount: memberCount)))
                return extensionDefinition
            }

            var memberSymbolsByGenericSignature: OrderedDictionary<Node, OrderedDictionary<SymbolIndexStore.MemberKind, [DemangledSymbol]>> = [:]
            var memberSymbolsByKind: OrderedDictionary<SymbolIndexStore.MemberKind, [DemangledSymbol]> = [:]

            for (kind, memberSymbols) in memberSymbols {
                for memberSymbol in memberSymbols {
                    if let genericSignature = memberSymbol.demangledNode.first(of: .dependentGenericSignature), case .variable = kind {
                        memberSymbolsByGenericSignature[genericSignature, default: [:]][kind, default: []].append(memberSymbol)
                    } else {
                        memberSymbolsByKind[kind, default: []].append(memberSymbol)
                    }
                }
            }

            do {
                if let typeKind = typeInfo.kind.typeKind {
                    let extensionName = ExtensionName(node: node, kind: .type(typeKind))

                    for (node, memberSymbolsByKind) in memberSymbolsByGenericSignature {
                        try typeExtensionDefinitions[extensionName, default: []].append(extensionDefinition(of: .type(typeKind), for: memberSymbolsByKind, genericSignature: node))
                        typeExtensionCount += 1
                    }
                    if !memberSymbolsByKind.isEmpty {
                        try typeExtensionDefinitions[extensionName, default: []].append(extensionDefinition(of: .type(typeKind), for: memberSymbolsByKind, genericSignature: nil))
                        typeExtensionCount += 1
                    }

                } else if typeInfo.kind == .protocol {
                    let extensionName = ExtensionName(node: node, kind: .protocol)

                    for (node, memberSymbolsByKind) in memberSymbolsByGenericSignature {
                        try protocolExtensionDefinitions[extensionName, default: []].append(extensionDefinition(of: .protocol, for: memberSymbolsByKind, genericSignature: node))
                        protocolExtensionCount += 1
                    }
                    if !memberSymbolsByKind.isEmpty {
                        try protocolExtensionDefinitions[extensionName, default: []].append(extensionDefinition(of: .protocol, for: memberSymbolsByKind, genericSignature: nil))
                        protocolExtensionCount += 1
                    }
                } else {
                    let extensionName = ExtensionName(node: node, kind: .typeAlias)

                    for (node, memberSymbolsByKind) in memberSymbolsByGenericSignature {
                        try typeAliasExtensionDefinitions[extensionName, default: []].append(extensionDefinition(of: .typeAlias, for: memberSymbolsByKind, genericSignature: node))
                        typeAliasExtensionCount += 1
                    }
                    if !memberSymbolsByKind.isEmpty {
                        try typeAliasExtensionDefinitions[extensionName, default: []].append(extensionDefinition(of: .typeAlias, for: memberSymbolsByKind, genericSignature: nil))
                        typeAliasExtensionCount += 1
                    }
                }
            } catch {
                eventDispatcher.dispatch(.extensionCreationFailed(targetName: name, error: error))
                failedExtensions += 1
            }
        }

        for (extensionName, typeExtensionDefinition) in typeExtensionDefinitions {
            self.typeExtensionDefinitions[extensionName, default: []].append(contentsOf: typeExtensionDefinition)
        }

        for (extensionName, protocolExtensionDefinition) in protocolExtensionDefinitions {
            self.protocolExtensionDefinitions[extensionName, default: []].append(contentsOf: protocolExtensionDefinition)
        }

        self.typeAliasExtensionDefinitions = typeAliasExtensionDefinitions

        eventDispatcher.dispatch(.extensionIndexingCompleted(result: SwiftInterfaceBuilderEvents.ExtensionIndexingResult(typeExtensions: typeExtensionCount, protocolExtensions: protocolExtensionCount, typeAliasExtensions: typeAliasExtensionCount, failed: failedExtensions)))
    }

    private func indexGlobals() async throws {
        @Dependency(\.symbolIndexStore)
        var symbolIndexStore

        globalVariableDefinitions = DefinitionBuilder.variables(for: symbolIndexStore.globalSymbols(of: .variable(isStorage: false), .variable(isStorage: true), in: machO).mapToDemangledSymbolWithOffset(), fieldNames: [], isGlobalOrStatic: true)
        globalFunctionDefinitions = DefinitionBuilder.functions(for: symbolIndexStore.globalSymbols(of: .function, in: machO).mapToDemangledSymbolWithOffset(), isGlobalOrStatic: true)
    }

    private func collectModules() async throws {
        eventDispatcher.dispatch(.moduleCollectionStarted)
        @Dependency(\.symbolIndexStore)
        var symbolIndexStore

        var usedModules: OrderedSet<String> = []
        let filterModules: Set<String> = [cModule, objcModule, stdlibName]
        let allSymbols = symbolIndexStore.allSymbols(in: machO)

        eventDispatcher.dispatch(.symbolScanStarted(context: SwiftInterfaceBuilderEvents.SymbolScanContext(totalSymbols: allSymbols.count, filterModules: Array(filterModules.sorted()))))

        for symbol in allSymbols {
            for moduleNode in symbol.demangledNode.all(of: .module) {
                if let module = moduleNode.text, !filterModules.contains(module) {
                    if usedModules.append(module).inserted {
                        eventDispatcher.dispatch(.moduleFound(context: SwiftInterfaceBuilderEvents.ModuleContext(moduleName: module)))
                    }
                }
            }
        }

        importedModules = usedModules
        eventDispatcher.dispatch(.moduleCollectionCompleted(result: SwiftInterfaceBuilderEvents.ModuleCollectionResult(moduleCount: usedModules.count, modules: Array(usedModules.sorted()))))
    }

    private func index() async throws {
        eventDispatcher.dispatch(.phaseTransition(phase: .indexing, state: .started))

        do {
            eventDispatcher.dispatch(.phaseOperationStarted(phase: .indexing, operation: .typeIndexing))
            try await indexTypes()
            eventDispatcher.dispatch(.phaseOperationCompleted(phase: .indexing, operation: .typeIndexing))
        } catch {
            eventDispatcher.dispatch(.phaseOperationFailed(phase: .indexing, operation: .typeIndexing, error: error))
            throw error
        }

        do {
            eventDispatcher.dispatch(.phaseOperationStarted(phase: .indexing, operation: .protocolIndexing))
            try await indexProtocols()
            eventDispatcher.dispatch(.phaseOperationCompleted(phase: .indexing, operation: .protocolIndexing))
        } catch {
            eventDispatcher.dispatch(.phaseOperationFailed(phase: .indexing, operation: .protocolIndexing, error: error))
            throw error
        }

        do {
            eventDispatcher.dispatch(.phaseOperationStarted(phase: .indexing, operation: .conformanceIndexing))
            try await indexConformances()
            eventDispatcher.dispatch(.phaseOperationCompleted(phase: .indexing, operation: .conformanceIndexing))
        } catch {
            eventDispatcher.dispatch(.phaseOperationFailed(phase: .indexing, operation: .conformanceIndexing, error: error))
            throw error
        }

        do {
            eventDispatcher.dispatch(.phaseOperationStarted(phase: .indexing, operation: .extensionIndexing))
            try await indexExtensions()
            eventDispatcher.dispatch(.phaseOperationCompleted(phase: .indexing, operation: .extensionIndexing))
        } catch {
            eventDispatcher.dispatch(.phaseOperationFailed(phase: .indexing, operation: .extensionIndexing, error: error))
            throw error
        }

        try await indexGlobals()

        eventDispatcher.dispatch(.phaseTransition(phase: .indexing, state: .completed))
    }

    @SemanticStringBuilder
    public func printRoot() async throws -> SemanticString {
        for module in OrderedSet(Self.internalModules + importedModules).sorted() {
            Standard("import \(module)")
            BreakLine()
        }

        for (offset, variable) in globalVariableDefinitions.offsetEnumerated() {
            BreakLine()

            try await printVariable(variable, level: 0)

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, function) in globalFunctionDefinitions.offsetEnumerated() {
            BreakLine()

            try await printFunction(function)

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, typeDefinition) in rootTypeDefinitions.values.offsetEnumerated() {
            BreakLine()

            try await printTypeDefinition(typeDefinition)

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, protocolDefinition) in rootProtocolDefinitions.values.offsetEnumerated() {
            BreakLine()

            try await printProtocolDefinition(protocolDefinition)

            if offset.isEnd {
                BreakLine()
            }
        }

        for protocolDefinition in rootProtocolDefinitions.values.filterNonNil(\.parent) {
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

        let dumper = typeDefinition.type.dumper(using: .init(demangleResolver: typeDemangleResolver, indentation: level, displayParentName: displayParentName, emitOffsetComments: configuration.emitOffsetComments), in: machO)

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

        let dumper = ProtocolDumper(protocolDefinition.protocol, using: .init(demangleResolver: typeDemangleResolver, indentation: level, displayParentName: displayParentName, emitOffsetComments: configuration.emitOffsetComments), in: machO)

        Indent(level: level - 1)

        try await dumper.declaration

        Space()

        Standard("{")

        try await dumper.associatedTypes

        try await printDefinition(protocolDefinition, level: level, offsetPrefix: "protocol witness table")

        if configuration.printStrippedSymbolicItem, !protocolDefinition.strippedSymbolicRequirements.isEmpty {
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

            if let offset = allocator.offset, configuration.emitOffsetComments {
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

            if let offset = variable.offset, configuration.emitOffsetComments {
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

            if let offset = function.offset, configuration.emitOffsetComments {
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

            if let offset = `subscript`.offset, configuration.emitOffsetComments {
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

            if let offset = variable.offset, configuration.emitOffsetComments {
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

            if let offset = function.offset, configuration.emitOffsetComments {
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

            if let offset = `subscript`.offset, configuration.emitOffsetComments {
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
