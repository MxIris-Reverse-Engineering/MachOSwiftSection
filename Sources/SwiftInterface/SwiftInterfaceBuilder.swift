import MachOSwiftSection
import MemberwiseInit
import OrderedCollections
import SwiftDump
import Demangle
import Semantic
import SwiftStdlibToolbox
import MachOKit
import TypeIndexing
import Dependencies
import Utilities

/// A comprehensive Swift interface builder that generates human-readable Swift interface files from Mach-O binaries.
///
/// The SwiftInterfaceBuilder analyzes Mach-O binaries to extract Swift type information, protocol definitions,
/// extensions, and other Swift language constructs, then generates clean, formatted Swift interface code.
/// This is particularly useful for reverse engineering, documentation generation, and understanding
/// the public API of Swift frameworks and libraries.
///
/// ## Features
/// - Extracts and formats Swift types (classes, structs, enums)
/// - Generates protocol definitions with requirements
/// - Handles protocol conformances and associated types
/// - Processes extensions and their members
/// - Supports generic signatures and constraints
/// - Manages module imports and dependencies
/// - Provides type indexing for better resolution
///
/// ## Usage
/// ```swift
/// let config = SwiftInterfaceBuilderConfiguration(isEnabledTypeIndexing: true)
/// let builder = try SwiftInterfaceBuilder(configuration: config, in: machOFile)
///
/// // Set dependency paths for better type resolution
/// builder.setDependencyPaths([
///     .dyldSharedCache("/path/to/cache"),
///     .usesSystemDyldSharedCache
/// ])
///
/// // Prepare the builder by indexing all symbols
/// try await builder.prepare()
///
/// // Generate the Swift interface
/// let interface = try builder.build()
/// ```
///
public final class SwiftInterfaceBuilder<MachO: MachOSwiftSectionRepresentableWithCache & Sendable>: Sendable {
    /// Swift standard library and internal modules that should not be explicitly imported
    private static var internalModules: [String] {
        ["Swift", "_Concurrency", "_StringProcessing", "_SwiftConcurrencyShims"]
    }

    /// Configuration options for this builder instance
    public let configuration: SwiftInterfaceBuilderConfiguration

    /// The Mach-O binary being analyzed
    public let machO: MachO

    /// Optional type database for enhanced type resolution when indexing is enabled
    private let typeDatabase: TypeDatabase<MachO>?

    /// Resolver for demangling type names using the configured type database
    @Mutex
    private var typeDemangleResolver: DemangleResolver = .using(options: .default)

    /// Event dispatcher for handling logging and progress events
    private let eventDispatcher: SwiftInterfaceBuilderEvents.Dispatcher

    /// All type wrappers (unified representation of enums, structs, and classes)
    @Mutex
    private var types: [TypeContextWrapper] = []

    /// All protocol definitions found in the binary
    @Mutex
    private var protocols: [MachOSwiftSection.`Protocol`] = []

    /// All protocol conformances discovered in the binary
    @Mutex
    private var protocolConformances: [ProtocolConformance] = []

    /// All associated types found in protocol conformances
    @Mutex
    private var associatedTypes: [AssociatedType] = []

    /// Cached mapping of type names to their protocol conformances
    @Mutex
    private var protocolConformancesByTypeName: OrderedDictionary<TypeName, OrderedDictionary<ProtocolName, ProtocolConformance>> = [:]

    /// Cached mapping of type names to their associated types by protocol
    @Mutex
    private var associatedTypesByTypeName: OrderedDictionary<TypeName, OrderedDictionary<ProtocolName, AssociatedType>> = [:]

    /// Set of all imported modules required for the interface
    @Mutex
    private var importedModules: OrderedSet<String> = []

    /// Main type definitions indexed by type name
    @Mutex
    private var rootTypeDefinitions: OrderedDictionary<TypeName, TypeDefinition> = [:]

    @Mutex
    private var allTypeDefinitions: OrderedDictionary<TypeName, TypeDefinition> = [:]

    /// Protocol definitions indexed by protocol name
    @Mutex
    private var rootProtocolDefinitions: OrderedDictionary<ProtocolName, ProtocolDefinition> = [:]

    /// Extension definitions for types (not including conformance extensions)
    @Mutex
    private var typeExtensionDefinitions: OrderedDictionary<TypeName, [ExtensionDefinition]> = [:]

    /// Extension definitions for protocols
    @Mutex
    private var protocolExtensionDefinitions: OrderedDictionary<ProtocolName, [ExtensionDefinition]> = [:]

    /// Extension definitions for type aliases
    @Mutex
    private var typeAliasExtensionDefinitions: OrderedDictionary<String, [ExtensionDefinition]> = [:]

    /// Extension definitions that add protocol conformances to types
    @Mutex
    private var conformanceExtensionDefinitions: OrderedDictionary<TypeName, [ExtensionDefinition]> = [:]

    /// Set of all names encountered during analysis (for conflict resolution)
    @Mutex
    private var allNames: Set<String> = []

    /// List of dependency Mach-O files for enhanced type resolution
    @Mutex
    private var dependencies: [MachO] = []

    @Mutex
    private var globalVariableDefinitions: [VariableDefinition] = []

    @Mutex
    private var globalFunctionDefinitions: [FunctionDefinition] = []

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
        eventDispatcher.dispatch(.initialization(config: SwiftInterfaceBuilderEvents.InitializationConfig(isTypeIndexingEnabled: configuration.isEnabledTypeIndexing, showCImportedTypes: configuration.showCImportedTypes)))

        self.configuration = configuration

        let typeDatabase: TypeDatabase<MachO>? = if configuration.isEnabledTypeIndexing, let platform = machO.loadCommands.buildVersionCommand?.platform.sdkPlatform {
            TypeDatabase(platform: platform)
        } else {
            nil
        }

        self.typeDatabase = typeDatabase
        self.machO = machO
        self.typeDemangleResolver = .using { [weak self] node in
            if let self {
                var printer = TypeNodePrinter(delegate: self)
                try printer.printRoot(node)
            }
        }
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

    public func build() throws -> SemanticString {
        try printRoot()
    }

    /// Indexes all types found in the Mach-O binary and builds parent-child relationships.
    /// This method processes all Swift types and creates a hierarchical structure
    /// representing nested types and their relationships.
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
                let declaration = try TypeDefinition(type: type, in: machO)
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
                    let extensionTypeNode = try MetadataReader.demangle(for: extendedContextMangledName, in: machO)

                    guard let extensionTypeKind = extensionTypeNode.typeKind else { continue }

                    let name = extensionTypeNode.print(using: .interfaceTypeBuilderOnly)

                    let extensionTypeName = TypeName(name: name, kind: extensionTypeKind)

                    var genericSignature: Node?

                    if let currentRequirements = extensionContext.genericContext?.currentRequirements(in: machO), !currentRequirements.isEmpty {
                        genericSignature = try MetadataReader.buildGenericSignature(for: currentRequirements, in: machO)
                    }

                    let extensionDefinition = try ExtensionDefinition(extensionName: extensionTypeName.extensionName, genericSignature: genericSignature, protocolConformance: nil, associatedType: nil, in: machO)
                    extensionDefinition.types = [typeDefinition]
                    typeExtensionDefinitions[extensionTypeName, default: []].append(extensionDefinition)
                case .type(let parentType):
                    let parentTypeName = try parentType.typeName(in: machO)
                    let extensionDefinition = try ExtensionDefinition(extensionName: parentTypeName.extensionName, genericSignature: nil, protocolConformance: nil, associatedType: nil, in: machO)
                    extensionDefinition.types = [typeDefinition]
                    typeExtensionDefinitions[parentTypeName, default: []].append(extensionDefinition)
                case .symbol(let symbol):
                    guard let type = try MetadataReader.demangleType(for: symbol, in: machO)?.children.first else { continue }
                    let kind: TypeKind? = switch type.kind {
                    case .enum:
                        .enum
                    case .structure:
                        .struct
                    case .class:
                        .class
                    default:
                        nil
                    }
                    guard let kind else { continue }
                    let name = type.print(using: .interfaceTypeBuilderOnly)
                    let parentTypeName = TypeName(name: name, kind: kind)
                    let extensionDefinition = try ExtensionDefinition(extensionName: parentTypeName.extensionName, genericSignature: nil, protocolConformance: nil, associatedType: nil, in: machO)
                    extensionDefinition.types = [typeDefinition]
                    typeExtensionDefinitions[parentTypeName, default: []].append(extensionDefinition)
                }
            }
        }

        self.allNames = allNames
        self.rootTypeDefinitions = rootTypeDefinitions
        allTypeDefinitions = currentModuleTypeDefinitions

        eventDispatcher.dispatch(.typeIndexingCompleted(result: SwiftInterfaceBuilderEvents.TypeIndexingResult(totalProcessed: types.count, successful: successfulCount, failed: failedCount, cImportedSkipped: cImportedCount, nestedTypes: nestedTypeCount, extensionTypes: extensionTypeCount)))
    }

    /// Indexes all protocols found in the binary.
    /// Creates protocol definitions with their requirements and default implementations.
    private func indexProtocols() async throws {
        eventDispatcher.dispatch(.protocolIndexingStarted(totalProtocols: protocols.count))
        var protocolDefinitions: OrderedDictionary<ProtocolName, ProtocolDefinition> = [:]
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

                    if isRoot {
                        protocolDefinitions[protocolName] = protocolDefinition
                    } else if let extensionContext = protocolDefinition.extensionContext, let extendedContextMangledName = extensionContext.extendedContextMangledName {
                        let typeNode = try MetadataReader.demangle(for: extendedContextMangledName, in: machO)
                        guard let typeKind = typeNode.typeKind else { continue }
                        let name = typeNode.print(using: .interfaceTypeBuilderOnly)
                        let typeName = TypeName(name: name, kind: typeKind)
                        var genericSignature: Node?
                        if let currentRequirements = extensionContext.genericContext?.currentRequirements(in: machO), !currentRequirements.isEmpty {
                            genericSignature = try MetadataReader.buildGenericSignature(for: currentRequirements, in: machO)
                        }
                        let extensionDefinition = try ExtensionDefinition(extensionName: typeName.extensionName, genericSignature: genericSignature, protocolConformance: nil, associatedType: nil, in: machO)
                        extensionDefinition.protocols = [protocolDefinition]
                        typeExtensionDefinitions[typeName, default: []].append(extensionDefinition)
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

        rootProtocolDefinitions = protocolDefinitions
        eventDispatcher.dispatch(.protocolIndexingCompleted(result: SwiftInterfaceBuilderEvents.ProtocolIndexingResult(totalProcessed: protocols.count, successful: successfulCount, failed: failedCount)))
    }

    /// Indexes protocol conformances and associated types.
    /// Creates cross-reference maps for efficient lookup of conformances by type name
    /// and associated types by protocol name.
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

        var conformanceExtensionDefinitions: OrderedDictionary<TypeName, [ExtensionDefinition]> = [:]
        var extensionCount = 0
        var failedExtensions = 0

        for (typeName, protocolConformances) in protocolConformancesByTypeName {
            for (protocolName, protocolConformance) in protocolConformances {
                do {
                    let extensionDefinition = try ExtensionDefinition(extensionName: typeName.extensionName, genericSignature: MetadataReader.buildGenericSignature(for: protocolConformance.conditionalRequirements, in: machO), protocolConformance: protocolConformance, associatedType: associatedTypesByTypeName[typeName]?[protocolName], in: machO)
                    conformanceExtensionDefinitions[typeName, default: []].append(extensionDefinition)
                    extensionCount += 1
                    eventDispatcher.dispatch(.conformanceExtensionCreated(context: SwiftInterfaceBuilderEvents.ConformanceContext(typeName: typeName.name, protocolName: protocolName.name)))
                } catch {
                    let context = SwiftInterfaceBuilderEvents.ConformanceContext(typeName: typeName.name, protocolName: protocolName.name)
                    eventDispatcher.dispatch(.conformanceExtensionCreationFailed(context: context, error: error))
                    failedExtensions += 1
                }
            }
        }
        self.conformanceExtensionDefinitions = conformanceExtensionDefinitions
        eventDispatcher.dispatch(.conformanceIndexingCompleted(result: SwiftInterfaceBuilderEvents.ConformanceIndexingResult(conformedTypes: protocolConformancesByTypeName.count, associatedTypeCount: associatedTypesByTypeName.count, extensionCount: extensionCount, failedConformances: failedConformances, failedAssociatedTypes: failedAssociatedTypes, failedExtensions: failedExtensions)))
    }

    /// Indexes extensions found in the binary.
    /// Processes member symbols to identify extensions and their contents,
    /// organizing them by the types or protocols they extend.
    private func indexExtensions() async throws {
        eventDispatcher.dispatch(.extensionIndexingStarted)

        @Dependency(\.symbolIndexStore)
        var symbolIndexStore

        let memberSymbolsByName = symbolIndexStore.memberSymbols(
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

        var typeExtensionDefinitions: OrderedDictionary<TypeName, [ExtensionDefinition]> = [:]
        var protocolExtensionDefinitions: OrderedDictionary<ProtocolName, [ExtensionDefinition]> = [:]
        var typeAliasExtensionDefinitions: OrderedDictionary<String, [ExtensionDefinition]> = [:]
        var typeExtensionCount = 0
        var protocolExtensionCount = 0
        var typeAliasExtensionCount = 0
        var failedExtensions = 0

        for (name, memberSymbols) in memberSymbolsByName {
            guard let typeInfo = symbolIndexStore.typeInfo(for: name, in: machO) else {
                eventDispatcher.dispatch(.extensionTargetNotFound(targetName: name))
                continue
            }

            func extensionDefinition(of kind: ExtensionKind, for memberSymbolsByKind: OrderedDictionary<SymbolIndexStore.MemberKind, [DemangledSymbol]>, genericSignature: Node?) throws -> ExtensionDefinition {
                let extensionDefinition = try ExtensionDefinition(extensionName: .init(name: name, kind: kind), genericSignature: genericSignature, protocolConformance: nil, associatedType: nil, in: machO)
                var memberCount = 0

                for (kind, memberSymbols) in memberSymbolsByKind {
                    switch kind {
                    case .allocator(inExtension: true):
                        let allocators = DefinitionBuilder.allocators(for: memberSymbols)
                        extensionDefinition.allocators.append(contentsOf: allocators)
                        memberCount += allocators.count
                    case .variable(inExtension: true, isStatic: false, isStorage: false):
                        let variables = DefinitionBuilder.variables(for: memberSymbols, fieldNames: [], isGlobalOrStatic: false)
                        extensionDefinition.variables.append(contentsOf: variables)
                        memberCount += variables.count
                    case .function(inExtension: true, isStatic: false):
                        let functions = DefinitionBuilder.functions(for: memberSymbols, isGlobalOrStatic: false)
                        extensionDefinition.functions.append(contentsOf: functions)
                        memberCount += functions.count
                    case .variable(inExtension: true, isStatic: true, _):
                        let staticVariables = DefinitionBuilder.variables(for: memberSymbols, fieldNames: [], isGlobalOrStatic: true)
                        extensionDefinition.staticVariables.append(contentsOf: staticVariables)
                        memberCount += staticVariables.count
                    case .function(inExtension: true, isStatic: true):
                        let staticFunctions = DefinitionBuilder.functions(for: memberSymbols, isGlobalOrStatic: true)
                        extensionDefinition.staticFunctions.append(contentsOf: staticFunctions)
                        memberCount += staticFunctions.count
                    case .subscript(inExtension: true, isStatic: false):
                        let subscripts = DefinitionBuilder.subscripts(for: memberSymbols, isStatic: false)
                        extensionDefinition.subscripts.append(contentsOf: subscripts)
                        memberCount += subscripts.count
                    case .subscript(inExtension: true, isStatic: true):
                        let staticSubscripts = DefinitionBuilder.subscripts(for: memberSymbols, isStatic: true)
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
                    let typeName = TypeName(name: name, kind: typeKind)

                    for (node, memberSymbolsByKind) in memberSymbolsByGenericSignature {
                        try typeExtensionDefinitions[typeName, default: []].append(extensionDefinition(of: .type(typeKind), for: memberSymbolsByKind, genericSignature: node))
                        typeExtensionCount += 1
                    }
                    if !memberSymbolsByKind.isEmpty {
                        try typeExtensionDefinitions[typeName, default: []].append(extensionDefinition(of: .type(typeKind), for: memberSymbolsByKind, genericSignature: nil))
                        typeExtensionCount += 1
                    }

                } else if typeInfo.kind == .protocol {
                    let protocolName = ProtocolName(name: name)

                    for (node, memberSymbolsByKind) in memberSymbolsByGenericSignature {
                        try protocolExtensionDefinitions[protocolName, default: []].append(extensionDefinition(of: .protocol, for: memberSymbolsByKind, genericSignature: node))
                        protocolExtensionCount += 1
                    }
                    if !memberSymbolsByKind.isEmpty {
                        try protocolExtensionDefinitions[protocolName, default: []].append(extensionDefinition(of: .protocol, for: memberSymbolsByKind, genericSignature: nil))
                        protocolExtensionCount += 1
                    }
                } else {
                    for (node, memberSymbolsByKind) in memberSymbolsByGenericSignature {
                        try typeAliasExtensionDefinitions[name, default: []].append(extensionDefinition(of: .typeAlias, for: memberSymbolsByKind, genericSignature: node))
                        typeAliasExtensionCount += 1
                    }
                    if !memberSymbolsByKind.isEmpty {
                        try typeAliasExtensionDefinitions[name, default: []].append(extensionDefinition(of: .typeAlias, for: memberSymbolsByKind, genericSignature: nil))
                        typeAliasExtensionCount += 1
                    }
                }
            } catch {
                eventDispatcher.dispatch(.extensionCreationFailed(targetName: name, error: error))
                failedExtensions += 1
            }
        }

        for (typeName, typeExtensionDefinition) in typeExtensionDefinitions {
            self.typeExtensionDefinitions[typeName, default: []].append(contentsOf: typeExtensionDefinition)
        }

        for (protocolName, protocolExtensionDefinition) in protocolExtensionDefinitions {
            self.protocolExtensionDefinitions[protocolName, default: []].append(contentsOf: protocolExtensionDefinition)
        }

        self.typeAliasExtensionDefinitions = typeAliasExtensionDefinitions

        eventDispatcher.dispatch(.extensionIndexingCompleted(result: SwiftInterfaceBuilderEvents.ExtensionIndexingResult(typeExtensions: typeExtensionCount, protocolExtensions: protocolExtensionCount, typeAliasExtensions: typeAliasExtensionCount, failed: failedExtensions)))
    }

    private func indexGlobals() {
        @Dependency(\.symbolIndexStore)
        var symbolIndexStore

        globalVariableDefinitions = DefinitionBuilder.variables(for: symbolIndexStore.globalSymbols(of: .variable(isStorage: false), .variable(isStorage: true), in: machO), fieldNames: [], isGlobalOrStatic: true)
        globalFunctionDefinitions = DefinitionBuilder.functions(for: symbolIndexStore.globalSymbols(of: .function, in: machO), isGlobalOrStatic: true)
    }

    /// Performs complete indexing of the Mach-O binary.
    /// This method coordinates all indexing operations in the correct order
    /// to build a complete picture of the Swift API.
    private func index() async throws {
        eventDispatcher.dispatch(.phaseTransition(phase: .indexing, state: .started))
        dependencies.append(machO)
        if let typeDatabase {
            do {
                let dependencyModules = Set(dependencies.map(\.imagePath.lastPathComponent.deletingPathExtension.deletingPathExtension.strippedLibSwiftPrefix))
                eventDispatcher.dispatch(.typeDatabaseIndexingStarted(input: SwiftInterfaceBuilderEvents.TypeDatabaseIndexingInput(dependencyModules: Array(dependencyModules.sorted()))))
                try await typeDatabase.index(dependencies: dependencies) { dependencyModules.contains($0) }
                eventDispatcher.dispatch(.typeDatabaseIndexingCompleted)
            } catch {
                eventDispatcher.dispatch(.typeDatabaseIndexingFailed(error: error))
                throw error
            }
        } else {
            let reason: SwiftInterfaceBuilderEvents.TypeDatabaseSkipReason = configuration.isEnabledTypeIndexing ? .notAvailable : .notEnabled
            eventDispatcher.dispatch(.typeDatabaseSkipped(reason: reason))
        }

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

        indexGlobals()

        eventDispatcher.dispatch(.phaseTransition(phase: .indexing, state: .completed))
    }

    @SemanticStringBuilder
    private func printRoot() throws -> SemanticString {
        for module in OrderedSet(Self.internalModules + importedModules).sorted() {
            Standard("import \(module)")
            BreakLine()
        }

        for (offset, variable) in globalVariableDefinitions.offsetEnumerated() {
            BreakLine()

            try printVariable(variable, level: 0)

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, function) in globalFunctionDefinitions.offsetEnumerated() {
            BreakLine()

            try printFunction(function)

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, typeDefinition) in rootTypeDefinitions.values.offsetEnumerated() {
            BreakLine()

            try printTypeDefinition(typeDefinition)

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, protocolDefinition) in rootProtocolDefinitions.values.offsetEnumerated() {
            BreakLine()

            try printProtocolDefinition(protocolDefinition)

            if offset.isEnd {
                BreakLine()
            }
        }

        for protocolDefinition in rootProtocolDefinitions.values.filterNonNil(\.parent) {
            for (offset, extensionDefinition) in protocolDefinition.defaultImplementationExtensions.offsetEnumerated() {
                BreakLine()

                try printExtensionDefinition(extensionDefinition)

                if offset.isEnd {
                    BreakLine()
                }
            }
        }

        for (offset, extensionDefinition) in (typeExtensionDefinitions.values.flatMap { $0 } + protocolExtensionDefinitions.values.flatMap { $0 } + typeAliasExtensionDefinitions.values.flatMap { $0 } + conformanceExtensionDefinitions.values.flatMap { $0 }).offsetEnumerated() {
            BreakLine()

            try printExtensionDefinition(extensionDefinition)

            if offset.isEnd {
                BreakLine()
            }
        }
    }

    @SemanticStringBuilder
    private func printTypeDefinition(_ typeDefinition: TypeDefinition, level: Int = 1) throws -> SemanticString {
        let dumper = typeDefinition.type.dumper(using: .init(demangleResolver: typeDemangleResolver, indentation: level, displayParentName: false), in: machO)

        if level > 1 {
            Indent(level: level - 1)
        }

        try dumper.declaration

        Space()
        Standard("{")

        for child in typeDefinition.typeChildren {
            BreakLine()
            try printTypeDefinition(child, level: level + 1)
        }

        for child in typeDefinition.protocolChildren {
            BreakLine()
            try printProtocolDefinition(child, level: level + 1)
        }

        try dumper.fields

        try printDefinition(typeDefinition, level: level)

        if level > 1, typeDefinition.hasMembers || typeDefinition.typeChildren.count > 0 || typeDefinition.protocolChildren.count > 0 {
            if !typeDefinition.hasMembers {
                BreakLine()
            }
            Indent(level: level - 1)
        }

        Standard("}")
    }

    @SemanticStringBuilder
    private func printProtocolDefinition(_ protocolDefinition: ProtocolDefinition, level: Int = 1) throws -> SemanticString {
        let dumper = ProtocolDumper(protocolDefinition.protocol, using: .init(demangleResolver: typeDemangleResolver, indentation: level, displayParentName: false), in: machO)

        if level > 1 {
            Indent(level: level - 1)
        }

        try dumper.declaration

        Space()

        Standard("{")

        try dumper.associatedTypes

        try printDefinition(protocolDefinition, level: level)

        if level > 1, protocolDefinition.hasMembers {
            Indent(level: level - 1)
        }

        Standard("}")

        if protocolDefinition.parent == nil {
            for (offset, extensionDefinition) in protocolDefinition.defaultImplementationExtensions.offsetEnumerated() {
                BreakLine()
                try printExtensionDefinition(extensionDefinition)
                if offset.isEnd {
                    BreakLine()
                }
            }
        }
    }

    @SemanticStringBuilder
    private func printExtensionDefinition(_ extensionDefinition: ExtensionDefinition, level: Int = 1) throws -> SemanticString {
        Keyword(.extension)
        Space()
        extensionDefinition.extensionName.print()
        if let protocolConformance = extensionDefinition.protocolConformance, let protocolName = try? protocolConformance.dumpProtocolName(using: .interfaceTypeBuilderOnly, in: machO) {
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
                node.printSemantic(using: .interfaceBuilderOnly)
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

            try printTypeDefinition(typeDefinition, level: level + 1)

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, protocolDefinition) in extensionDefinition.protocols.offsetEnumerated() {
            BreakLine()

            try printProtocolDefinition(protocolDefinition, level: level + 1)

            if offset.isEnd {
                BreakLine()
            }
        }

        if let associatedType = extensionDefinition.associatedType {
            let dumper = AssociatedTypeDumper(associatedType, using: .init(demangleResolver: typeDemangleResolver), in: machO)
            try dumper.records
        }

        try printDefinition(extensionDefinition, level: 1)

        Standard("}")
    }

    @SemanticStringBuilder
    private func printDefinition(_ definition: some Definition, level: Int = 1) throws -> SemanticString {
        for (offset, allocator) in definition.allocators.offsetEnumerated() {
            BreakLine()

            Indent(level: level)

            try printFunction(allocator)

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, variable) in definition.variables.offsetEnumerated() {
            BreakLine()
            Indent(level: level)

            try printVariable(variable, level: level)

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, function) in definition.functions.offsetEnumerated() {
            BreakLine()

            Indent(level: level)

            try printFunction(function)

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, `subscript`) in definition.subscripts.offsetEnumerated() {
            BreakLine()
            Indent(level: level)

            try printSubscript(`subscript`, level: level)

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, variable) in definition.staticVariables.offsetEnumerated() {
            BreakLine()
            Indent(level: level)

            try printVariable(variable, level: level)

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, function) in definition.staticFunctions.offsetEnumerated() {
            BreakLine()
            Indent(level: level)

            try printFunction(function)

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, `subscript`) in definition.staticSubscripts.offsetEnumerated() {
            BreakLine()

            Indent(level: level)

            try printSubscript(`subscript`, level: level)

            if offset.isEnd {
                BreakLine()
            }
        }
    }

    @SemanticStringBuilder
    private func printVariable(_ variable: VariableDefinition, level: Int) throws -> SemanticString {
        var printer = VariableNodePrinter(isStored: variable.isStored, hasSetter: variable.hasSetter, indentation: level, delegate: self)
        try printer.printRoot(variable.node)
    }

    @SemanticStringBuilder
    private func printFunction(_ function: FunctionDefinition) throws -> SemanticString {
        var printer = FunctionNodePrinter(delegate: self)
        try printer.printRoot(function.node)
    }

    @SemanticStringBuilder
    private func printSubscript(_ `subscript`: SubscriptDefinition, level: Int) throws -> SemanticString {
        var printer = SubscriptNodePrinter(hasSetter: `subscript`.hasSetter, indentation: level, delegate: self)
        try printer.printRoot(`subscript`.node)
    }

    /// Collects all modules that need to be imported for the interface.
    /// Scans all symbols to find module references and builds the import list.
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
}

extension SwiftInterfaceBuilder<MachOFile> {
    /// Sets the dependency paths for loading related Mach-O files and dyld caches.
    /// This improves type resolution by providing access to types from dependencies.
    ///
    /// - Parameter paths: An array of dependency paths specifying where to find related binaries.
    ///                   Can include specific Mach-O files, dyld cache paths, or system cache.
    ///
    /// ## Example
    /// ```swift
    /// builder.setDependencyPaths([
    ///     .machO("/path/to/dependency.framework/Versions/A/dependency"),
    ///     .dyldSharedCache("/path/to/dyld_shared_cache_x86_64"),
    ///     .usesSystemDyldSharedCache
    /// ])
    /// ```
    public func setDependencyPaths(_ paths: [DependencyPath]) {
        eventDispatcher.dispatch(.dependencyLoadingStarted(input: SwiftInterfaceBuilderEvents.DependencyLoadingInput(paths: paths.count)))
        var dependencies: [MachOFile] = []
        let dependencyPaths = Set(machO.dependencies.map(\.dylib.name))

        for searchPath in paths {
            switch searchPath {
            case .machO(let path):
                do {
                    if let machOFile = try File.loadFromFile(url: .init(fileURLWithPath: path)).machOFiles.first {
                        dependencies.append(machOFile)
                        eventDispatcher.dispatch(.dependencyLoadSuccess(context: SwiftInterfaceBuilderEvents.DependencyContext(path: path, count: nil)))
                    } else {
                        eventDispatcher.dispatch(.dependencyLoadWarning(warning: .init(path: path, reason: .noMachOFileFound)))
                    }
                } catch {
                    eventDispatcher.dispatch(.dependencyLoadingFailed(failure: SwiftInterfaceBuilderEvents.DependencyLoadingFailure(path: path, error: error)))
                }
            case .dyldSharedCache(let path):
                do {
                    let fullDyldCache = try FullDyldCache(url: .init(fileURLWithPath: path))
                    var foundCount = 0
                    for machOFile in fullDyldCache.machOFiles() where dependencyPaths.contains(machOFile.imagePath) {
                        dependencies.append(machOFile)
                        foundCount += 1
                    }
                    eventDispatcher.dispatch(.dependencyLoadSuccess(context: SwiftInterfaceBuilderEvents.DependencyContext(path: path, count: foundCount)))
                } catch {
                    eventDispatcher.dispatch(.dependencyLoadingFailed(failure: SwiftInterfaceBuilderEvents.DependencyLoadingFailure(path: path, error: error)))
                }
            case .usesSystemDyldSharedCache:
                if let hostDyldCache = FullDyldCache.host {
                    var foundCount = 0
                    for machOFile in hostDyldCache.machOFiles() where dependencyPaths.contains(machOFile.imagePath) {
                        dependencies.append(machOFile)
                        foundCount += 1
                    }
                    eventDispatcher.dispatch(.dependencyLoadSuccess(context: SwiftInterfaceBuilderEvents.DependencyContext(path: "system dyld cache", count: foundCount)))
                } else {
                    eventDispatcher.dispatch(.dependencyLoadWarning(warning: .init(path: "system dyld cache", reason: .systemCacheNotAvailable)))
                }
            }
        }

        self.dependencies = dependencies
        eventDispatcher.dispatch(.dependencyLoadingCompleted(result: SwiftInterfaceBuilderEvents.DependencyLoadingResult(loadedCount: dependencies.count)))
    }
}

extension SwiftInterfaceBuilder<MachOImage> {
    public func setupDependencies() {
        var dependencies: [MachO] = []
        let dependencyPaths = machO.dependencies.map(\.dylib.name)

        for dependencyPath in dependencyPaths {
            if let machO = MachOImage(name: dependencyPath) {
                dependencies.append(machO)
            }
        }

        self.dependencies = dependencies
    }
}

extension SwiftInterfaceBuilder: NodePrintableDelegate {
    func moduleName(forTypeName typeName: String) -> String? {
        typeDatabase?.moduleName(forTypeName: typeName)
    }

    func swiftName(forCName cName: String) -> String? {
        typeDatabase?.swiftName(forCName: cName)
    }

    func opaqueType(forNode node: Node, index: Int?) -> String? {
        do {
            @Dependency(\.symbolIndexStore)
            var symbolIndexStore

            guard let opaqueTypeDescriptorSymbol = symbolIndexStore.opaqueTypeDescriptorSymbol(for: node, in: machO) else { return nil }

            let opaqueType = try OpaqueType(descriptor: OpaqueTypeDescriptor.resolve(from: opaqueTypeDescriptorSymbol.offset, in: machO), in: machO)
            let requirements = try opaqueType.requirements(in: machO)
            var protocolRequirementsByParamType: OrderedDictionary<String, [GenericRequirementDescriptor]> = [:]
            var protocolRequirements = requirements.filter(\.content.isProtocol)
            for protocolRequirement in protocolRequirements {
                let param = try protocolRequirement.dumpParameterName(resolver: .using(options: .opaqueTypeBuilderOnly), in: machO).string
                protocolRequirementsByParamType[param, default: []].append(protocolRequirement)
            }
            if let index {
                protocolRequirements = protocolRequirementsByParamType.elements[index + 1].value
            } else {
                protocolRequirements = protocolRequirementsByParamType.elements[0].value
            }
            let typeRequirements = requirements.filter(\.content.isType)
            let typeRequirementNodes = try typeRequirements.compactMap { try MetadataReader.buildGenericSignature(for: $0, in: machO) }
            var substitutionMap: SubstitutionMap<Node> = .init()
            var associatedTypeByParamType: [String: [Node]] = [:]
            var witnessTypeByParamType: [String: [Node]] = [:]
            for typeRequirementNode in typeRequirementNodes {
                guard let sameTypeRequirementNode = typeRequirementNode.first(of: .dependentGenericSameTypeRequirement) else { continue }
                guard let firstType = sameTypeRequirementNode.children.at(0), let secondType = sameTypeRequirementNode.children.at(1) else { continue }
                if secondType.children.first?.isKind(of: .dependentMemberType) ?? false {
                    substitutionMap.add(original: firstType, substitution: secondType)
                    if let paramTypeNode = secondType.first(of: .dependentGenericParamType), let paramType = paramTypeNode.text {
                        associatedTypeByParamType[paramType, default: []].append(secondType)
                    }
                } else if let paramTypeNode = firstType.first(of: .dependentGenericParamType), let paramType = paramTypeNode.text {
                    witnessTypeByParamType[paramType, default: []].append(secondType)
                }
            }

            var results: [String] = []
            for protocolRequirement in protocolRequirements {
                var result = ""
                let param = try protocolRequirement.dumpParameterName(resolver: .using(options: .opaqueTypeBuilderOnly), in: machO).string
                let proto = try protocolRequirement.dumpContent(resolver: .using(options: .opaqueTypeBuilderOnly), in: machO).string
                result.write(proto)
                var primaryAssociatedTypes: [String] = []
                if let associatedTypes = associatedTypeByParamType[param] {
                    for associatedType in associatedTypes {
                        let primaryAssociatedTypeNode = substitutionMap.rootOriginal(for: associatedType)
                        primaryAssociatedTypes.append(primaryAssociatedTypeNode.print(using: .opaqueTypeBuilderOnly))
                    }
                }
                
                if let witnessTypes = witnessTypeByParamType[param] {
                    for witnessType in witnessTypes {
                        primaryAssociatedTypes.append(witnessType.print(using: .opaqueTypeBuilderOnly))
                    }
                }
                
                if !primaryAssociatedTypes.isEmpty {
                    result.write("<")
                    result.write(primaryAssociatedTypes.joined(separator: ", "))
                    result.write(">")
                }
                
                results.append(result)
            }

            return results.joined(separator: " & ")
        } catch {
            return nil
        }
    }
}

extension String {
    var strippedLibSwiftPrefix: String {
        if hasPrefix("libswift") {
            return String(dropFirst("libswift".count))
        }
        return self
    }
}

extension MachOKit.Platform {
    var sdkPlatform: SDKPlatform? {
        switch self {
        case .macOS,
             .macCatalyst:
            return .macOS
        case .driverKit:
            return .driverKit
        case .iOS:
            return .iOS
        case .tvOS:
            return .tvOS
        case .watchOS:
            return .watchOS
        case .visionOS:
            return .visionOS
        case .iOSSimulator:
            return .iOSSimulator
        case .tvOSSimulator:
            return .tvOSSimulator
        case .watchOSSimulator:
            return .watchOSSimulator
        case .visionOSSimulator:
            return .visionOSSimulator
        default:
            return nil
        }
    }
}

extension LoadCommandsProtocol {
    var buildVersionCommand: BuildVersionCommand? {
        for command in self {
            switch command {
            case .buildVersion(let buildVersionCommand):
                return buildVersionCommand
            default:
                break
            }
        }
        return nil
    }
}

extension Sequence {
    func filterNonNil<T>(_ filter: (Element) throws -> T?) rethrows -> [Element] {
        var results: [Element] = []
        for element in self {
            if try filter(element) != nil {
                results.append(element)
            }
        }
        return results
    }
}
