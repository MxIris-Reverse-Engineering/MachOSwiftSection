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

@_spi(Support)
public final class SwiftInterfaceIndexer<MachO: MachOSwiftSectionRepresentableWithCache>: Sendable {
    public let machO: MachO

    public let configuration: SwiftInterfaceIndexConfiguration

    public let eventDispatcher: SwiftInterfaceEvents.Dispatcher = .init()

    public init(machO: MachO, configuration: SwiftInterfaceIndexConfiguration) {
        self.machO = machO
        self.configuration = configuration
    }

    @Mutex
    public private(set) var types: [TypeContextWrapper] = []

    @Mutex
    public private(set) var protocols: [MachOSwiftSection.`Protocol`] = []

    @Mutex
    public private(set) var protocolConformances: [ProtocolConformance] = []

    @Mutex
    public private(set) var associatedTypes: [AssociatedType] = []

    @Mutex
    public private(set) var protocolConformancesByTypeName: OrderedDictionary<TypeName, OrderedDictionary<ProtocolName, ProtocolConformance>> = [:]

    @Mutex
    public private(set) var associatedTypesByTypeName: OrderedDictionary<TypeName, OrderedDictionary<ProtocolName, AssociatedType>> = [:]

    @Mutex
    public private(set) var rootTypeDefinitions: OrderedDictionary<TypeName, TypeDefinition> = [:]

    @Mutex
    public private(set) var allTypeDefinitions: OrderedDictionary<TypeName, TypeDefinition> = [:]

    @Mutex
    public private(set) var rootProtocolDefinitions: OrderedDictionary<ProtocolName, ProtocolDefinition> = [:]

    @Mutex
    public private(set) var allProtocolDefinitions: OrderedDictionary<ProtocolName, ProtocolDefinition> = [:]

    @Mutex
    public private(set) var typeExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> = [:]

    @Mutex
    public private(set) var protocolExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> = [:]

    @Mutex
    public private(set) var typeAliasExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> = [:]

    @Mutex
    public private(set) var conformanceExtensionDefinitions: OrderedDictionary<ExtensionName, [ExtensionDefinition]> = [:]

    @Mutex
    public private(set) var globalVariableDefinitions: [VariableDefinition] = []

    @Mutex
    public private(set) var globalFunctionDefinitions: [FunctionDefinition] = []

    func prepare() async throws {
        eventDispatcher.dispatch(.phaseTransition(phase: .preparation, state: .started))

        do {
            eventDispatcher.dispatch(.extractionStarted(section: .swiftTypes))
            types = try machO.swift.types
            eventDispatcher.dispatch(.extractionCompleted(result: SwiftInterfaceEvents.ExtractionResult(section: .swiftTypes, count: types.count)))
        } catch {
            eventDispatcher.dispatch(.extractionFailed(section: .swiftTypes, error: error))
            types = []
        }

        do {
            eventDispatcher.dispatch(.extractionStarted(section: .swiftProtocols))
            protocols = try machO.swift.protocols
            eventDispatcher.dispatch(.extractionCompleted(result: SwiftInterfaceEvents.ExtractionResult(section: .swiftProtocols, count: protocols.count)))
        } catch {
            eventDispatcher.dispatch(.extractionFailed(section: .swiftProtocols, error: error))
            protocols = []
        }

        do {
            eventDispatcher.dispatch(.extractionStarted(section: .protocolConformances))
            protocolConformances = try machO.swift.protocolConformances
            eventDispatcher.dispatch(.extractionCompleted(result: SwiftInterfaceEvents.ExtractionResult(section: .protocolConformances, count: protocolConformances.count)))
        } catch {
            eventDispatcher.dispatch(.extractionFailed(section: .protocolConformances, error: error))
            protocolConformances = []
        }

        do {
            eventDispatcher.dispatch(.extractionStarted(section: .associatedTypes))
            associatedTypes = try machO.swift.associatedTypes
            eventDispatcher.dispatch(.extractionCompleted(result: SwiftInterfaceEvents.ExtractionResult(section: .associatedTypes, count: associatedTypes.count)))
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

        eventDispatcher.dispatch(.phaseTransition(phase: .preparation, state: .completed))
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

    private func indexTypes() async throws {
        eventDispatcher.dispatch(.typeIndexingStarted(totalTypes: types.count))
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

        self.rootTypeDefinitions = rootTypeDefinitions
        allTypeDefinitions = currentModuleTypeDefinitions

        eventDispatcher.dispatch(.typeIndexingCompleted(result: SwiftInterfaceEvents.TypeIndexingResult(totalProcessed: types.count, successful: successfulCount, failed: failedCount, cImportedSkipped: cImportedCount, nestedTypes: nestedTypeCount, extensionTypes: extensionTypeCount)))
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

                    successfulCount += 1

                    eventDispatcher.dispatch(.protocolProcessed(context: SwiftInterfaceEvents.ProtocolContext(protocolName: protocolName.name, requirementCount: protocolDefinition.protocol.requirements.count)))
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
        eventDispatcher.dispatch(.protocolIndexingCompleted(result: SwiftInterfaceEvents.ProtocolIndexingResult(totalProcessed: protocols.count, successful: successfulCount, failed: failedCount)))
    }

    private func indexConformances() async throws {
        eventDispatcher.dispatch(.conformanceIndexingStarted(input: SwiftInterfaceEvents.ConformanceIndexingInput(totalConformances: protocolConformances.count, totalAssociatedTypes: associatedTypes.count)))
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
                    eventDispatcher.dispatch(.conformanceFound(context: SwiftInterfaceEvents.ConformanceContext(typeName: typeName.name, protocolName: protocolName.name)))
                } else {
                    eventDispatcher.dispatch(.nameExtractionWarning(for: .protocolConformance))
                    failedConformances += 1
                }
            } catch {
                let context = SwiftInterfaceEvents.ConformanceContext(typeName: typeName?.name ?? "unknown", protocolName: protocolName?.name ?? "unknown")
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
                    eventDispatcher.dispatch(.associatedTypeFound(context: SwiftInterfaceEvents.ConformanceContext(typeName: typeName.name, protocolName: protocolName.name)))
                } else {
                    eventDispatcher.dispatch(.nameExtractionWarning(for: .associatedType))
                    failedAssociatedTypes += 1
                }
            } catch {
                let context = SwiftInterfaceEvents.ConformanceContext(typeName: typeName?.name ?? "unknown", protocolName: protocolName?.name ?? "unknown")
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
                    eventDispatcher.dispatch(.conformanceExtensionCreated(context: SwiftInterfaceEvents.ConformanceContext(typeName: typeName.name, protocolName: protocolName.name)))
                } catch {
                    let context = SwiftInterfaceEvents.ConformanceContext(typeName: typeName.name, protocolName: protocolName.name)
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
        eventDispatcher.dispatch(.conformanceIndexingCompleted(result: SwiftInterfaceEvents.ConformanceIndexingResult(conformedTypes: protocolConformancesByTypeName.count, associatedTypeCount: associatedTypesByTypeName.count, extensionCount: extensionCount, failedConformances: failedConformances, failedAssociatedTypes: failedAssociatedTypes, failedExtensions: failedExtensions)))
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

                eventDispatcher.dispatch(.extensionCreated(context: SwiftInterfaceEvents.ExtensionContext(targetName: name, memberCount: memberCount)))
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

        eventDispatcher.dispatch(.extensionIndexingCompleted(result: SwiftInterfaceEvents.ExtensionIndexingResult(typeExtensions: typeExtensionCount, protocolExtensions: protocolExtensionCount, typeAliasExtensions: typeAliasExtensionCount, failed: failedExtensions)))
    }

    private func indexGlobals() async throws {
        @Dependency(\.symbolIndexStore)
        var symbolIndexStore

        globalVariableDefinitions = DefinitionBuilder.variables(for: symbolIndexStore.globalSymbols(of: .variable(isStorage: false), .variable(isStorage: true), in: machO).mapToDemangledSymbolWithOffset(), fieldNames: [], isGlobalOrStatic: true)
        globalFunctionDefinitions = DefinitionBuilder.functions(for: symbolIndexStore.globalSymbols(of: .function, in: machO).mapToDemangledSymbolWithOffset(), isGlobalOrStatic: true)
    }
}
