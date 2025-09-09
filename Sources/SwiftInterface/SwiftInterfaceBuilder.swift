import Foundation
import MachOSwiftSection
import MemberwiseInit
import OrderedCollections
import SwiftDump
import Demangle
import Semantic
import SwiftStdlibToolbox
import MachOKit
import OSLog
import TypeIndexing

@available(iOS, unavailable)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@available(visionOS, unavailable)
public enum DependencyPath {
    case machO(String)
    case dyldSharedCache(String)
    case usesSystemDyldSharedCache
}

@available(iOS, unavailable)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@available(visionOS, unavailable)
private let logger = Logger(subsystem: "com.MachOSwiftSection.SwiftInterface", category: "SwiftInterfaceBuilder")

@available(iOS, unavailable)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@available(visionOS, unavailable)
public final class SwiftInterfaceBuilder<MachO: MachOSwiftSectionRepresentableWithCache & Sendable>: Sendable {
    private let machO: MachO

    private let typeDatabase: TypeDatabase?

    private let enums: [Enum]

    private let structs: [Struct]

    private let classes: [Class]

    private let types: [TypeWrapper]

    private let protocols: [MachOSwiftSection.`Protocol`]

    private let protocolConformances: [ProtocolConformance]

    private let associatedTypes: [AssociatedType]

    @Mutex
    private var protocolConformancesByTypeName: OrderedDictionary<TypeName, OrderedDictionary<ProtocolName, ProtocolConformance>> = [:]

    @Mutex
    private var associatedTypesByTypeName: OrderedDictionary<TypeName, OrderedDictionary<ProtocolName, AssociatedType>> = [:]

    @Mutex
    private var importedModules: OrderedSet<String> = []

    @Mutex
    private var typeDefinitions: OrderedDictionary<TypeName, TypeDefinition> = [:]

    @Mutex
    private var protocolDefinitions: OrderedDictionary<ProtocolName, ProtocolDefinition> = [:]

    @Mutex
    private var typeExtensionDefinitions: OrderedDictionary<TypeName, [ExtensionDefinition]> = [:]

    @Mutex
    private var protocolExtensionDefinitions: OrderedDictionary<ProtocolName, [ExtensionDefinition]> = [:]

    @Mutex
    private var typeAliasExtensionDefinitions: OrderedDictionary<String, [ExtensionDefinition]> = [:]

    @Mutex
    private var conformanceExtensionDefinitions: OrderedDictionary<TypeName, [ExtensionDefinition]> = [:]

    @Mutex
    private var globalVariables: [VariableDefinition] = []

    @Mutex
    private var globalFunctions: [FunctionDefinition] = []

    @Mutex
    private var allNames: Set<String> = []

    private static var internalModules: [String] {
        ["Swift", "_Concurrency", "_StringProcessing", "_SwiftConcurrencyShims"]
    }

    public init(machO: MachO) throws {
        self.typeDatabase = machO.loadCommands.buildVersionCommand?.platform.sdkPlatform.map { .init(platform: $0) }
        self.machO = machO
        let types = try machO.swift.types
        var enums: [Enum] = []
        var structs: [Struct] = []
        var classes: [Class] = []
        for type in types {
            switch type {
            case .enum(let `enum`):
                enums.append(`enum`)
            case .struct(let `struct`):
                structs.append(`struct`)
            case .class(let `class`):
                classes.append(`class`)
            }
        }
        self.types = types
        self.enums = enums
        self.structs = structs
        self.classes = classes
        self.protocols = try machO.swift.protocols
        self.protocolConformances = try machO.swift.protocolConformances
        self.associatedTypes = try machO.swift.associatedTypes
    }

    @Mutex
    private var dependencies: [MachOFile] = []

    public func setDependencyPaths(_ paths: [DependencyPath]) {
        do {
            var dependencies: [MachOFile] = []
            let dependencyPaths = Set(machO.dependencies.map(\.dylib.name))
            for searchPath in paths {
                switch searchPath {
                case .machO(let path):
                    if let machOFile = try File.loadFromFile(url: .init(fileURLWithPath: path)).machOFiles.first {
                        dependencies.append(machOFile)
                    }
                case .dyldSharedCache(let path):
                    let fullDyldCache = try FullDyldCache(url: .init(fileURLWithPath: path))
                    for machOFile in fullDyldCache.machOFiles() where dependencyPaths.contains(machOFile.imagePath) {
                        dependencies.append(machOFile)
                    }
                case .usesSystemDyldSharedCache:
                    if let hostDyldCache = FullDyldCache.host {
                        for machOFile in hostDyldCache.machOFiles() where dependencyPaths.contains(machOFile.imagePath) {
                            dependencies.append(machOFile)
                        }
                    }
                }
            }
            self.dependencies = dependencies
        } catch {
            logger.error("\(error)")
        }
    }

    public nonisolated func prepare() async throws {
        try await index()
        try await collectModules()
    }

    private func indexTypes() async throws {
        var allNames: Set<String> = []
        var definitionsCache: OrderedDictionary<TypeName, TypeDefinition> = [:]

        for type in types {
            guard let isCImportedContext = try? type.contextDescriptorWrapper.contextDescriptor.isCImportedContextDescriptor(in: machO), !isCImportedContext else { continue }

            do {
                let declaration = try TypeDefinition(type: type, in: machO)
                definitionsCache[declaration.typeName] = declaration
                allNames.insert(declaration.typeName.name)
            } catch {
                print(error)
            }
        }

        for type in types {
            guard let typeName = try? type.typeName(in: machO), let childDefinition = definitionsCache[typeName] else {
                continue
            }

            var parentContext = try ContextWrapper.type(type).parent(in: machO)?.resolved

            while let currentContext = parentContext {
                if case .type(let typeContext) = currentContext, let parentTypeName = try? typeContext.typeName(in: machO) {
                    if let parentDefinition = definitionsCache[parentTypeName] {
                        childDefinition.parent = parentDefinition
                        parentDefinition.typeChildren.append(childDefinition)
                    }
                    break
                }
                parentContext = try currentContext.parent(in: machO)?.resolved
            }

            while let currentContext = parentContext {
                if case .extension(let extensionContext) = currentContext {
                    childDefinition.extensionContext = extensionContext
                    break
                }
                parentContext = try currentContext.parent(in: machO)?.resolved
            }
        }

        var typeDefinitions: OrderedDictionary<TypeName, TypeDefinition> = [:]
        for (typeName, definition) in definitionsCache {
            if definition.parent == nil {
                typeDefinitions[typeName] = definition
            }
        }

        self.allNames = allNames
        self.typeDefinitions = typeDefinitions
    }

    private func indexConformances() async throws {
        var protocolConformancesByTypeName: OrderedDictionary<TypeName, OrderedDictionary<ProtocolName, ProtocolConformance>> = [:]

        for conformance in protocolConformances {
            if let typeName = try? conformance.typeName(in: machO), let protocolName = try? conformance.protocolName(in: machO) {
                protocolConformancesByTypeName[typeName, default: [:]][protocolName] = conformance
            }
        }

        self.protocolConformancesByTypeName = protocolConformancesByTypeName

        var associatedTypesByTypeName: OrderedDictionary<TypeName, OrderedDictionary<ProtocolName, AssociatedType>> = [:]

        for associatedType in associatedTypes {
            if let typeName = try? associatedType.typeName(in: machO), let protocolName = try? associatedType.protocolName(in: machO) {
                associatedTypesByTypeName[typeName, default: [:]][protocolName] = associatedType
            }
        }
        self.associatedTypesByTypeName = associatedTypesByTypeName

        var conformanceExtensionDefinitions: OrderedDictionary<TypeName, [ExtensionDefinition]> = [:]

        for (typeName, protocolConformances) in protocolConformancesByTypeName {
            for (protocolName, protocolConformance) in protocolConformances {
                let extensionDefinition = try ExtensionDefinition(name: typeName.name, kind: .type(typeName.kind), genericSignature: MetadataReader.buildGenericSignature(for: protocolConformance.conditionalRequirements, in: machO), protocolConformance: protocolConformance, associatedType: associatedTypesByTypeName[typeName]?[protocolName], in: machO)
                conformanceExtensionDefinitions[typeName, default: []].append(extensionDefinition)
            }
        }
        self.conformanceExtensionDefinitions = conformanceExtensionDefinitions
    }

    private func indexExtensions() async throws {
        let memberSymbolsByName = SymbolIndexStore.shared.memberSymbols(
            of: .allocatorInExtension,
            .variableInExtension,
            .functionInExtension,
            .staticVariableInExtension,
            .staticFunctionInExtension,
            excluding: allNames,
            in: machO
        )

        var typeExtensionDefinitions: OrderedDictionary<TypeName, [ExtensionDefinition]> = [:]
        var protocolExtensionDefinitions: OrderedDictionary<ProtocolName, [ExtensionDefinition]> = [:]
        var typeAliasExtensionDefinitions: OrderedDictionary<String, [ExtensionDefinition]> = [:]
        for (name, memberSymbols) in memberSymbolsByName {
            guard let typeInfo = SymbolIndexStore.shared.typeInfo(for: name, in: machO) else { continue }
            func extensionDefinition(of kind: ExtensionDefinition.Kind, for memberSymbolsByKind: OrderedDictionary<SymbolIndexStore.MemberKind, [DemangledSymbol]>, genericSignature: Node?) throws -> ExtensionDefinition {
                var extensionDefinition = try ExtensionDefinition(name: name, kind: kind, genericSignature: genericSignature, protocolConformance: nil, associatedType: nil, in: machO)
                for (kind, memberSymbols) in memberSymbolsByKind {
                    let nodes = memberSymbols.map(\.demangledNode)
                    switch kind {
                    case .allocatorInExtension:
                        extensionDefinition.allocators.append(contentsOf: DefinitionBuilder.allocators(for: nodes))
                    case .variableInExtension:
                        extensionDefinition.variables.append(contentsOf: DefinitionBuilder.variables(for: nodes, fieldNames: [], isStatic: false))
                    case .functionInExtension:
                        extensionDefinition.functions.append(contentsOf: DefinitionBuilder.functions(for: nodes, isStatic: false))
                    case .staticVariableInExtension:
                        extensionDefinition.staticVariables.append(contentsOf: DefinitionBuilder.variables(for: nodes, fieldNames: [], isStatic: true))
                    case .staticFunctionInExtension:
                        extensionDefinition.staticFunctions.append(contentsOf: DefinitionBuilder.functions(for: nodes, isStatic: true))
                    default:
                        break
                    }
                }
                return extensionDefinition
            }
            var memberSymbolsByGenericSignature: OrderedDictionary<Node, OrderedDictionary<SymbolIndexStore.MemberKind, [DemangledSymbol]>> = [:]
            var memberSymbolsByKind: OrderedDictionary<SymbolIndexStore.MemberKind, [DemangledSymbol]> = [:]

            for (kind, memberSymbols) in memberSymbols {
                for memberSymbol in memberSymbols {
                    if let genericSignature = memberSymbol.demangledNode.first(of: .dependentGenericSignature), kind == .variableInExtension || kind == .staticVariableInExtension {
                        memberSymbolsByGenericSignature[genericSignature, default: [:]][kind, default: []].append(memberSymbol)
                    } else {
                        memberSymbolsByKind[kind, default: []].append(memberSymbol)
                    }
                }
            }
            if let typeKind = typeInfo.kind.typeKind {
                let typeName = TypeName(name: name, kind: typeKind)

                for (node, memberSymbolsByKind) in memberSymbolsByGenericSignature {
                    try typeExtensionDefinitions[typeName, default: []].append(extensionDefinition(of: .type(typeKind), for: memberSymbolsByKind, genericSignature: node))
                }
                if !memberSymbolsByKind.isEmpty {
                    try typeExtensionDefinitions[typeName, default: []].append(extensionDefinition(of: .type(typeKind), for: memberSymbolsByKind, genericSignature: nil))
                }

            } else if typeInfo.kind == .protocol {
                let protocolName = ProtocolName(name: name)

                for (node, memberSymbolsByKind) in memberSymbolsByGenericSignature {
                    try protocolExtensionDefinitions[protocolName, default: []].append(extensionDefinition(of: .protocol, for: memberSymbolsByKind, genericSignature: node))
                }
                if !memberSymbolsByKind.isEmpty {
                    try protocolExtensionDefinitions[protocolName, default: []].append(extensionDefinition(of: .protocol, for: memberSymbolsByKind, genericSignature: nil))
                }
            } else {
                for (node, memberSymbolsByKind) in memberSymbolsByGenericSignature {
                    try typeAliasExtensionDefinitions[name, default: []].append(extensionDefinition(of: .typeAlias, for: memberSymbolsByKind, genericSignature: node))
                }
                if !memberSymbolsByKind.isEmpty {
                    try typeAliasExtensionDefinitions[name, default: []].append(extensionDefinition(of: .typeAlias, for: memberSymbolsByKind, genericSignature: nil))
                }
            }
        }
        self.typeExtensionDefinitions = typeExtensionDefinitions
        self.protocolExtensionDefinitions = protocolExtensionDefinitions
        self.typeAliasExtensionDefinitions = typeAliasExtensionDefinitions
    }

    private func indexProtocols() async throws {
        var protocolDefinitions: OrderedDictionary<ProtocolName, ProtocolDefinition> = [:]

        for `protocol` in protocols {
            do {
                let protocolDefinition = try ProtocolDefinition(protocol: `protocol`, in: machO)
                let protocolName = try `protocol`.protocolName(in: machO)
                protocolDefinitions[protocolName] = protocolDefinition
                allNames.insert(protocolName.name)
            } catch {
                print(error)
            }
        }

        self.protocolDefinitions = protocolDefinitions
    }

    private func index() async throws {
        if let typeDatabase {
            let dependencyModules = Set(dependencies.map(\.imagePath.lastPathComponent.deletingPathExtension.deletingPathExtension.strippedLibSwiftPrefix))
            try await typeDatabase.index(dependencies: dependencies) { dependencyModules.contains($0) }
        }
        try await indexTypes()
        try await indexProtocols()
        try await indexConformances()
        try await indexExtensions()
    }

    @SemanticStringBuilder
    public func build() throws -> SemanticString {
        for module in Self.internalModules + importedModules.sorted() {
            Standard("import \(module)")
            BreakLine()
        }

        BreakLine()

        for (offset, typeDefinition) in typeDefinitions.values.offsetEnumerated() {
            try printTypeDefinition(typeDefinition)

            if !offset.isEnd {
                BreakLine()
                BreakLine()
            }
        }

        for (offset, protocolDefinition) in protocolDefinitions.values.offsetEnumerated() {
            if offset.isStart {
                BreakLine()
                BreakLine()
            }

            try printProtocolDefinition(protocolDefinition)

            if !offset.isEnd {
                BreakLine()
                BreakLine()
            }
        }

        for (offset, extensionDefinition) in (typeExtensionDefinitions.values.flatMap { $0 } + protocolExtensionDefinitions.values.flatMap { $0 } + typeAliasExtensionDefinitions.values.flatMap { $0 } + conformanceExtensionDefinitions.values.flatMap { $0 }).offsetEnumerated() {
            if offset.isStart {
                BreakLine()
                BreakLine()
            }

            try printExtensionDefinition(extensionDefinition)

            if !offset.isEnd {
                BreakLine()
                BreakLine()
            }
        }
    }

    @SemanticStringBuilder
    private func printGenericSignature(_ genericContext: TypeGenericContext?, @SemanticStringBuilder contentsBuilder: () throws -> SemanticString = { "" }) throws -> SemanticString {
        if let genericContext {
            if genericContext.currentParameters.count > 0 {
                try genericContext.dumpGenericParameters(in: machO)
            }

            try contentsBuilder()

            if genericContext.currentRequirements.count > 0 {
                Space()
                Keyword(.where)
                Space()
                try genericContext.dumpGenericRequirements(in: machO) {
                    var printer = TypeNodePrinter(cImportedInfoProvider: typeDatabase)
                    try printer.printRoot($0)
                }
            }
        }
    }

    @SemanticStringBuilder
    private func printTypeDefinition(_ typeDefinition: TypeDefinition, level: Int = 1) throws -> SemanticString {
        if level > 1 {
            Indent(level: level - 1)
        }

        switch typeDefinition.type {
        case .enum(let `enum`):
            Keyword(.enum)

            Space()

            TypeDeclaration(kind: .enum, typeDefinition.typeName.currentName)

            try printGenericSignature(`enum`.genericContext)

        case .struct(let `struct`):
            Keyword(.struct)

            Space()

            TypeDeclaration(kind: .struct, typeDefinition.typeName.currentName)

            try printGenericSignature(`struct`.genericContext)

        case .class(let `class`):
            if `class`.descriptor.isActor {
                Keyword(.actor)
            } else {
                Keyword(.class)
            }

            Space()

            TypeDeclaration(kind: .class, typeDefinition.typeName.currentName)

            try printGenericSignature(`class`.genericContext) {
                if let superclassMangledName = try `class`.descriptor.superclassTypeMangledName(in: machO) {
                    Standard(":")
                    Space()

                    var printer = TypeNodePrinter(cImportedInfoProvider: typeDatabase)
                    try printer.printRoot(MetadataReader.demangleType(for: superclassMangledName, in: machO))
                } else if let resilientSuperclass = `class`.resilientSuperclass, let kind = `class`.descriptor.resilientSuperclassReferenceKind, let superclassNode = try resilientSuperclass.dumpSuperclassNode(for: kind, in: machO) {
                    Standard(":")
                    Space()

                    var printer = TypeNodePrinter(cImportedInfoProvider: typeDatabase)
                    try printer.printRoot(superclassNode)
                }
            }
        }

//        try dumper.declaration

        Space()
        Standard("{")

        for child in typeDefinition.typeChildren {
            BreakLine()
            try printTypeDefinition(child, level: level + 1)
        }

//        let fields = try dumper.fields

        switch typeDefinition.type {
        case .enum(let `enum`):
            for (offset, fieldRecord) in try `enum`.descriptor.fieldDescriptor(in: machO).records(in: machO).offsetEnumerated() {
                if offset.isStart, level == 1, !typeDefinition.typeChildren.isEmpty {
                    BreakLine()
                }

                BreakLine()

                Indent(level: level)

                if fieldRecord.flags.contains(.isIndirectCase) {
                    Keyword(.indirect)
                    Space()
                    Keyword(.case)
                    Space()
                } else {
                    Keyword(.case)
                    Space()
                }

                try MemberDeclaration("\(fieldRecord.fieldName(in: machO))")

                let mangledName = try fieldRecord.mangledTypeName(in: machO)

                if !mangledName.isEmpty {
                    var printer = TypeNodePrinter(cImportedInfoProvider: typeDatabase)

                    let demangledName = try printer.printRoot(MetadataReader.demangleType(for: mangledName, in: machO))

                    let demangledNameString = demangledName.string
                    if demangledNameString.hasPrefix("("), demangledNameString.hasSuffix(")") {
                        demangledName
                    } else {
                        Standard("(")
                        demangledName
                        Standard(")")
                    }
                }

                if offset.isEnd {
                    BreakLine()
                }
            }
        case .struct(let `struct`):
            for (offset, fieldRecord) in try `struct`.descriptor.fieldDescriptor(in: machO).records(in: machO).offsetEnumerated() {
                if offset.isStart, level == 1, !typeDefinition.typeChildren.isEmpty {
                    BreakLine()
                }

                BreakLine()

                Indent(level: level)

                let demangledTypeNode = try MetadataReader.demangleType(for: fieldRecord.mangledTypeName(in: machO), in: machO)

                let fieldName = try fieldRecord.fieldName(in: machO)

                if fieldRecord.flags.contains(.isVariadic) {
                    if demangledTypeNode.hasWeakNode {
                        Keyword(.weak)
                        Space()
                        Keyword(.var)
                        Space()
                    } else if fieldName.hasLazyPrefix {
                        Keyword(.lazy)
                        Space()
                        Keyword(.var)
                        Space()
                    } else {
                        Keyword(.var)
                        Space()
                    }
                } else {
                    Keyword(.let)
                    Space()
                }

                MemberDeclaration(fieldName.stripLazyPrefix)

                Standard(":")

                Space()

                var printer = TypeNodePrinter(cImportedInfoProvider: typeDatabase)

                try printer.printRoot(demangledTypeNode)

                if offset.isEnd {
                    BreakLine()
                }
            }
        case .class(let `class`):
            for (offset, fieldRecord) in try `class`.descriptor.fieldDescriptor(in: machO).records(in: machO).offsetEnumerated() {
                if offset.isStart, level == 1, !typeDefinition.typeChildren.isEmpty {
                    BreakLine()
                }

                BreakLine()

                Indent(level: level)

                let demangledTypeNode = try MetadataReader.demangleType(for: fieldRecord.mangledTypeName(in: machO), in: machO)

                let fieldName = try fieldRecord.fieldName(in: machO)

                if fieldRecord.flags.contains(.isVariadic) {
                    if demangledTypeNode.contains(.weak) {
                        Keyword(.weak)
                        Space()
                        Keyword(.var)
                        Space()
                    } else if fieldName.hasLazyPrefix {
                        Keyword(.lazy)
                        Space()
                        Keyword(.var)
                        Space()
                    } else {
                        Keyword(.var)
                        Space()
                    }
                } else {
                    Keyword(.let)
                    Space()
                }

                MemberDeclaration(fieldName.stripLazyPrefix)

                Standard(":")

                Space()

                var printer = TypeNodePrinter(cImportedInfoProvider: typeDatabase)

                try printer.printRoot(demangledTypeNode)

                if offset.isEnd {
                    BreakLine()
                }
            }
        }

        try printDefinition(typeDefinition, level: level)

        if level > 1, typeDefinition.hasMembers {
            Indent(level: level - 1)
        }

        Standard("}")
    }

    @SemanticStringBuilder
    private func printProtocolDefinition(_ protocolDefinition: ProtocolDefinition) throws -> SemanticString {
        let dumper = ProtocolDumper(protocolDefinition.protocol, using: .init(demangleOptions: .interfaceBuilderOnly), in: machO)
        try dumper.declaration
        Space()
        Standard("{")
        try dumper.associatedTypes
        for (offset, requirment) in protocolDefinition.requirements.offsetEnumerated() {
            BreakLine()
            Indent(level: 1)
            var printer: any InterfaceNodePrinter = switch requirment {
            case .function:
                FunctionNodePrinter(cImportedInfoProvider: typeDatabase)
            case .variable(let variable):
                VariableNodePrinter(hasSetter: variable.hasSetter, indentation: 1, cImportedInfoProvider: typeDatabase)
            }
            try printer.printRoot(requirment.node)

            if offset.isEnd {
                BreakLine()
            }
        }
        Standard("}")
        for (offset, extensionDefinition) in protocolDefinition.defaultImplementationExtensions.offsetEnumerated() {
            BreakLine()
            try printExtensionDefinition(extensionDefinition)
            if offset.isEnd {
                BreakLine()
            }
        }
    }

    @SemanticStringBuilder
    private func printExtensionDefinition(_ extensionDefinition: ExtensionDefinition) throws -> SemanticString {
        Keyword(.extension)
        Space()
        extensionDefinition.printName()
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
        if let associatedType = extensionDefinition.associatedType {
            let dumper = AssociatedTypeDumper(associatedType, using: .init(demangleOptions: .interfaceBuilderOnly), in: machO)
            try dumper.records
//            for (offset, record) in associatedType.records.offsetEnumerated() {
//                BreakLine()
//
//                Indent(level: 1)
//
//                Keyword(.typealias)
//
//                Space()
//
//                try TypeDeclaration(kind: .other, record.name(in: machO))
//
//                Space()
//
//                Standard("=")
//
//                Space()
//
//                var printer = TypeNodePrinter(cImportedInfoProvider: typeDatabase)
//                try printer.printRoot(MetadataReader.demangleSymbol(for: record.substitutedTypeName(in: machO), in: machO))
//
//                if offset.isEnd {
//                    BreakLine()
//                }
//            }
        }

        try printDefinition(extensionDefinition, level: 1)

        Standard("}")
    }

    @SemanticStringBuilder
    private func printDefinition(_ definition: some Definition, level: Int = 1) throws -> SemanticString {
        for (offset, allocator) in definition.allocators.offsetEnumerated() {
            BreakLine()
            Indent(level: level)
            var printer = FunctionNodePrinter(cImportedInfoProvider: typeDatabase)
            try printer.printRoot(allocator.node)

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, variable) in definition.variables.offsetEnumerated() {
            BreakLine()
            Indent(level: level)
            var printer = VariableNodePrinter(hasSetter: variable.hasSetter, indentation: level, cImportedInfoProvider: typeDatabase)
            try printer.printRoot(variable.node)

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, function) in definition.functions.offsetEnumerated() {
            BreakLine()
            Indent(level: level)
            var printer = FunctionNodePrinter(cImportedInfoProvider: typeDatabase)
            try printer.printRoot(function.node)

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, variable) in definition.staticVariables.offsetEnumerated() {
            BreakLine()
            Indent(level: level)
            var printer = VariableNodePrinter(hasSetter: variable.hasSetter, indentation: level, cImportedInfoProvider: typeDatabase)
            try printer.printRoot(variable.node)

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, function) in definition.staticFunctions.offsetEnumerated() {
            BreakLine()
            Indent(level: level)
            var printer = FunctionNodePrinter(cImportedInfoProvider: typeDatabase)
            try printer.printRoot(function.node)

            if offset.isEnd {
                BreakLine()
            }
        }
    }

    private func collectModules() async throws {
        var usedModules: OrderedSet<String> = []
        let filterModules: Set<String> = [cModule, objcModule, stdlibName]

        func addModule(_ module: String) {
            if !filterModules.contains(module) {
                usedModules.append(module)
            }
        }

        for symbol in SymbolIndexStore.shared.allSymbols(in: machO) {
            for moduleNode in symbol.demangledNode.all(of: .module) {
                if let module = moduleNode.text, !filterModules.contains(module) {
                    usedModules.append(module)
                }
            }
        }

        importedModules = usedModules
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

extension TypeDatabase: CImportedInfoProvider {}
