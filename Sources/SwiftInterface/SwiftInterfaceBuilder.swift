import Foundation
import MachOSwiftSection
import MemberwiseInit
import OrderedCollections
import SwiftDump
import Demangle
import Semantic
import SwiftStdlibToolbox

@MemberwiseInit
struct TypeName: Hashable {
    let name: String
    let kind: TypeKind

    var currentName: String {
        name.components(separatedBy: ".").last ?? name
    }

    @SemanticStringBuilder
    func print() -> SemanticString {
        switch kind {
        case .enum:
            TypeDeclaration(kind: .enum, name)
        case .struct:
            TypeDeclaration(kind: .struct, name)
        case .class:
            TypeDeclaration(kind: .class, name)
        }
    }
}

enum TypeKind: Hashable {
    case `enum`
    case `struct`
    case `class`
}

@MemberwiseInit
struct ProtocolName: Hashable {
    let name: String
}

@MemberwiseInit
final class TypeDefinition: Definition {
    let type: TypeWrapper

    let typeName: TypeName

    weak var parent: TypeDefinition?

    var typeChildren: [TypeDefinition] = []

    var protocolChildren: [ProtocolDefinition] = []

    var extensionContext: ExtensionContext?

    var extensions: [ExtensionDefinition] = []

    var fields: [TypeFieldDefinition] = []

    var variables: [VariableDefinition] = []

    var functions: [FunctionDefinition] = []

    var staticVariables: [VariableDefinition] = []

    var staticFunctions: [FunctionDefinition] = []

    var allocators: [FunctionDefinition] = []

    var hasDeallocator: Bool = false

    var hasMembers: Bool {
        !fields.isEmpty || !variables.isEmpty || !functions.isEmpty || !staticVariables.isEmpty || !staticFunctions.isEmpty || !allocators.isEmpty || hasDeallocator
    }

    func index<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws {
        var fields: [TypeFieldDefinition] = []
        let typeContextDescriptor = try required(type.contextDescriptorWrapper.typeContextDescriptor)
        let fieldDescriptor = try typeContextDescriptor.fieldDescriptor(in: machO)
        let records = try fieldDescriptor.records(in: machO)
        for record in records {
            let node = try record.demangledTypeNode(in: machO)
            let name = try record.fieldName(in: machO)
            let isLazy = name.hasLazyPrefix
            let isWeak = node.contains(.weak)
            let isVar = record.flags.contains(.isVariadic)
            let isIndirectCase = record.flags.contains(.isIndirectCase)
            let field = TypeFieldDefinition(node: node, name: name.stripLazyPrefix, isLazy: isLazy, isWeak: isWeak, isVar: isVar, isIndirectCase: isIndirectCase)
            fields.append(field)
        }

        self.fields = fields

        let fieldNames = Set(fields.map(\.name))

        variables = Self.variables(for: SymbolIndexStore.shared.memberSymbols(of: .variable, for: typeName.name, in: machO).map(\.demangledNode), fieldNames: fieldNames)
        staticVariables = Self.variables(for: SymbolIndexStore.shared.memberSymbols(of: .staticVariable, for: typeName.name, in: machO).map(\.demangledNode), fieldNames: fieldNames)

        functions = Self.functions(for: SymbolIndexStore.shared.memberSymbols(of: .function, for: typeName.name, in: machO).map(\.demangledNode))
        staticFunctions = Self.functions(for: SymbolIndexStore.shared.memberSymbols(of: .staticFunction, for: typeName.name, in: machO).map(\.demangledNode))
        allocators = Self.allocators(for: SymbolIndexStore.shared.memberSymbols(of: .allocator, for: typeName.name, in: machO).map(\.demangledNode))
        hasDeallocator = !SymbolIndexStore.shared.memberSymbols(of: .deallocator, for: typeName.name, in: machO).isEmpty
    }

    static func variables(for nodes: [Node], fieldNames: borrowing Set<String>) -> [VariableDefinition] {
        typealias NodeAndVariableKinds = (node: Node, kind: VariableKind)
        var variables: [VariableDefinition] = []
        var nodeAndVariableKindsByName: [String: [NodeAndVariableKinds]] = [:]
        for node in nodes {
            guard let variableNode = node.first(of: .variable) else { continue }
            guard let name = variableNode.identifier else { continue }
            guard let variableKind = node.variableKind else { continue }
            nodeAndVariableKindsByName[name, default: []].append((node, variableKind))
        }

        for (name, nodeAndVariableKinds) in nodeAndVariableKindsByName {
            guard !fieldNames.contains(name) else { continue }
            let nodes = nodeAndVariableKinds.map(\.node)
            guard let node = nodes.first(where: { $0.contains(.getter) }) else { continue }
            let kinds = nodeAndVariableKinds.map(\.kind)
            variables.append(.init(node: node, name: name, hasSetter: kinds.contains(.setter), hasModifyAccessor: kinds.contains(.modifyAccessor)))
        }
        return variables
    }

    static func allocators(for nodes: [Node]) -> [FunctionDefinition] {
        var allocators: [FunctionDefinition] = []
        for node in nodes {
            allocators.append(.init(node: node, name: "", kind: .allocator))
        }
        return allocators
    }

    static func functions(for nodes: [Node]) -> [FunctionDefinition] {
        var functions: [FunctionDefinition] = []
        for node in nodes {
            guard let functionNode = node.first(of: .function), let name = functionNode.identifier else { continue }
            functions.append(.init(node: node, name: name, kind: .function))
        }
        return functions
    }
}

extension Node {
    var variableKind: VariableKind? {
        guard let node = first(of: .getter, .setter, .modifyAccessor) else { return nil }
        switch node.kind {
        case .getter: return .getter
        case .setter: return .setter
        case .modifyAccessor: return .modifyAccessor
        default: return nil
        }
    }
}

protocol Definition {
    var allocators: [FunctionDefinition] { get set }
    var variables: [VariableDefinition] { get set }
    var functions: [FunctionDefinition] { get set }
    var staticVariables: [VariableDefinition] { get set }
    var staticFunctions: [FunctionDefinition] { get set }
}

@MemberwiseInit
struct TypeFieldDefinition {
    let node: Node
    let name: String
    let isLazy: Bool
    let isWeak: Bool
    let isVar: Bool
    let isIndirectCase: Bool
}

enum VariableKind {
    case getter
    case setter
    case modifyAccessor
}

@MemberwiseInit
struct VariableDefinition {
    let node: Node
    let name: String
    let hasSetter: Bool
    let hasModifyAccessor: Bool
}

@MemberwiseInit
struct FunctionDefinition {
    enum Kind {
        case function
        case allocator
        case deallocator
    }

    let node: Node
    let name: String
    let kind: Kind
}

@MemberwiseInit
struct ExtensionDefinition: Definition {
    enum Kind {
        case type(TypeKind)
        case `protocol`
        case typeAlias
    }

    let name: String

    let kind: Kind

    let genericSignature: Node?

    let protocolConformance: ProtocolConformance?

    let associatedType: AssociatedType?

    var allocators: [FunctionDefinition] = []

    var variables: [VariableDefinition] = []

    var functions: [FunctionDefinition] = []

    var staticVariables: [VariableDefinition] = []

    var staticFunctions: [FunctionDefinition] = []

    @SemanticStringBuilder
    func printName() -> SemanticString {
        switch kind {
        case .type(.enum):
            TypeDeclaration(kind: .enum, name)
        case .type(.struct):
            TypeDeclaration(kind: .struct, name)
        case .type(.class):
            TypeDeclaration(kind: .class, name)
        case .protocol:
            TypeDeclaration(kind: .protocol, name)
        case .typeAlias:
            TypeDeclaration(kind: .other, name)
        }
    }

    mutating func index<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws {
        guard let protocolConformance, !protocolConformance.resilientWitnesses.isEmpty else { return }
        func _node(for symbols: Symbols, typeName: String, visitedNodes: borrowing OrderedSet<Node> = []) throws -> Node? {
            for symbol in symbols {
                if let node = try? MetadataReader.demangleSymbol(for: symbol, in: machO), let protocolConformanceNode = node.first(of: .protocolConformance), let symbolTypeName = protocolConformanceNode.children.at(0)?.print(using: .interfaceType), symbolTypeName == typeName || PrimitiveTypeMappingCache.shared.entry(in: machO)?.primitiveType(for: typeName) == symbolTypeName, !visitedNodes.contains(node) {
                    return node
                }
            }
            return nil
        }
        var visitedNodes: OrderedSet<Node> = []
        var memberSymbolsByKind: OrderedDictionary<SymbolIndexStore.MemberKind, [Node]> = [:]

        func addNode(_ node: Node) {
            if node.contains(.variable) {
                if node.contains(.static) {
                    memberSymbolsByKind[.staticVariable, default: []].append(node)
                } else {
                    memberSymbolsByKind[.variable, default: []].append(node)
                }
            } else if node.contains(.allocator) {
                memberSymbolsByKind[.allocator, default: []].append(node)
            } else if node.contains(.function) {
                if node.contains(.static) {
                    memberSymbolsByKind[.staticFunction, default: []].append(node)
                } else {
                    memberSymbolsByKind[.function, default: []].append(node)
                }
            }
        }

        for resilientWitness in protocolConformance.resilientWitnesses {
            if let symbols = try resilientWitness.implementationSymbols(in: machO), let node = try _node(for: symbols, typeName: name, visitedNodes: visitedNodes) {
                _ = visitedNodes.append(node)
                addNode(node)
            } else if let requirement = try resilientWitness.requirement(in: machO) {
                switch requirement {
                case .symbol(let symbol):
                    if let demangledNode = try? MetadataReader.demangleSymbol(for: symbol, in: machO) {
                        addNode(demangledNode)
                    }
                case .element(let element):
                    if let symbols = try Symbols.resolve(from: element.offset, in: machO), let node = try _node(for: symbols, typeName: name, visitedNodes: visitedNodes) {
                        _ = visitedNodes.append(node)
                        addNode(node)
                    } else if let defaultImplementationSymbols = try element.defaultImplementationSymbols(in: machO), let node = try _node(for: defaultImplementationSymbols, typeName: name, visitedNodes: visitedNodes) {
                        _ = visitedNodes.append(node)
                        addNode(node)
                    } else if !element.defaultImplementation.isNull {
                    } else if !resilientWitness.implementation.isNull {
                    } else {}
                }
            } else if !resilientWitness.implementation.isNull {
            } else {}
        }

        for (kind, memberSymbols) in memberSymbolsByKind {
            switch kind {
            case .variable:
                variables = TypeDefinition.variables(for: memberSymbols, fieldNames: [])
            case .allocator:
                allocators = TypeDefinition.allocators(for: memberSymbols)
            case .function:
                functions = TypeDefinition.functions(for: memberSymbols)
            case .staticVariable:
                staticVariables = TypeDefinition.variables(for: memberSymbols, fieldNames: [])
            case .staticFunction:
                staticFunctions = TypeDefinition.functions(for: memberSymbols)
            default:
                break
            }
        }
    }
}

enum ProtocolRequirementDefinition {
    case variable(VariableDefinition)
    case function(FunctionDefinition)

    var node: Node {
        switch self {
        case .variable(let variable):
            return variable.node
        case .function(let function):
            return function.node
        }
    }

    var name: String {
        switch self {
        case .variable(let variable):
            return variable.name
        case .function(let function):
            return function.name
        }
    }
}

@MemberwiseInit
final class ProtocolDefinition {
    let `protocol`: MachOSwiftSection.`Protocol`

    weak var parent: TypeDefinition?

    var extensionContext: ExtensionContext?

    var requirements: [ProtocolRequirementDefinition] = []

    var defaultImplementationRequirements: [ProtocolRequirementDefinition] = []

    var extensions: [ProtocolExtensionDefinition] = []

    func index<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws {
        func _name() throws -> SemanticString {
            try MetadataReader.demangleContext(for: .protocol(`protocol`.descriptor), in: machO).printSemantic(using: .interfaceType).replacingTypeNameOrOtherToTypeDeclaration()
        }

        func _node(for symbols: Symbols, visitedNodes: borrowing OrderedSet<Node> = []) throws -> Node? {
            let currentInterfaceName = try _name().string
            for symbol in symbols {
                if let node = try? MetadataReader.demangleSymbol(for: symbol, in: machO), let protocolNode = node.first(of: .protocol), protocolNode.print(using: .interfaceType) == currentInterfaceName, !visitedNodes.contains(node) {
                    return node
                }
            }
            return nil
        }
        var requirements: [ProtocolRequirementDefinition] = []
        var defaultImplementationRequirements: [ProtocolRequirementDefinition] = []
        var visitedNodes: OrderedSet<Node> = []
        var variableKindsByName: OrderedDictionary<String, Set<VariableKind>> = [:]
        var nodeAndRequirements: [(node: Node, requirement: ProtocolRequirement)] = []
        for requirement in `protocol`.requirements {
            guard let symbols = try Symbols.resolve(from: requirement.offset, in: machO), let node = try? _node(for: symbols, visitedNodes: visitedNodes) else { continue }
            nodeAndRequirements.append((node, requirement))
            if let variable = node.first(of: .variable), let name = variable.identifier, let variableKind = node.variableKind {
                variableKindsByName[name, default: []].insert(variableKind)
            }
            visitedNodes.append(node)
        }
        for (node, requirement) in nodeAndRequirements {
            let requirementDefinition: ProtocolRequirementDefinition
            if let variable = node.first(of: .variable), let name = variable.identifier, node.contains(.getter), let variableKinds = variableKindsByName[name] {
                requirementDefinition = .variable(VariableDefinition(node: variable, name: name, hasSetter: variableKinds.contains(.setter), hasModifyAccessor: variableKinds.contains(.modifyAccessor)))
            } else if node.contains(.allocator) {
                requirementDefinition = .function(FunctionDefinition(node: node, name: "", kind: .allocator))
            } else if let function = node.first(of: .function), let name = function.identifier {
                requirementDefinition = .function(FunctionDefinition(node: function, name: name, kind: .function))
            } else {
                continue
            }
            requirements.append(requirementDefinition)
            if try requirement.defaultImplementationSymbols(in: machO) != nil {
                defaultImplementationRequirements.append(requirementDefinition)
            }
        }
        self.requirements = requirements
        self.defaultImplementationRequirements = defaultImplementationRequirements
    }
}

@MemberwiseInit
struct ProtocolExtensionDefinition: Definition {
    let protocolName: ProtocolName

    let genericSignature: Node?

    var allocators: [FunctionDefinition] = []

    var variables: [VariableDefinition] = []

    var functions: [FunctionDefinition] = []

    var staticVariables: [VariableDefinition] = []

    var staticFunctions: [FunctionDefinition] = []
}

public final class SwiftInterfaceBuilder<MachO: MachOSwiftSectionRepresentableWithCache & Sendable>: Sendable {
    private let machO: MachO

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

    private static var internalModules: [String] {
        ["Swift", "_Concurrency", "_StringProcessing", "_SwiftConcurrencyShims"]
    }

    public init(machO: MachO) throws {
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

    func prepare() throws {
        try index()
        try collectModules()
    }

    private func index() throws {
        var allNames: Set<String> = []

        var definitionsCache: OrderedDictionary<TypeName, TypeDefinition> = [:]

        for type in types {
            guard let module = try? type.contextDescriptorWrapper.contextDescriptor.moduleContextDesciptor(in: machO) else { continue }

            guard let moduleName = try? module.name(in: machO), moduleName != cModule, moduleName != objcModule else { continue }

            guard let typeName = try? type.typeName(in: machO) else { continue }

            let declaration = TypeDefinition(type: type, typeName: typeName)

            do {
                try declaration.index(in: machO)
                definitionsCache[typeName] = declaration
                allNames.insert(typeName.name)
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
                var extensionDefinition = try ExtensionDefinition(name: typeName.name, kind: .type(typeName.kind), genericSignature: MetadataReader.buildGenericSignature(for: protocolConformance.conditionalRequirements, in: machO), protocolConformance: protocolConformance, associatedType: associatedTypesByTypeName[typeName]?[protocolName])
                try extensionDefinition.index(in: machO)
                conformanceExtensionDefinitions[typeName, default: []].append(extensionDefinition)
            }
        }
        self.conformanceExtensionDefinitions = conformanceExtensionDefinitions
        
        var typeDefinitions: OrderedDictionary<TypeName, TypeDefinition> = [:]
        for (typeName, definition) in definitionsCache {
            if definition.parent == nil {
                typeDefinitions[typeName] = definition
            }
        }

        self.typeDefinitions = typeDefinitions

        var protocolDefinitions: OrderedDictionary<ProtocolName, ProtocolDefinition> = [:]

        for `protocol` in protocols {
            do {
                let protocolDefinition = ProtocolDefinition(protocol: `protocol`)
                try protocolDefinition.index(in: machO)
                let protocolName = try `protocol`.protocolName(in: machO)
                protocolDefinitions[protocolName] = protocolDefinition
                allNames.insert(protocolName.name)
            } catch {
                print(error)
            }
        }

        self.protocolDefinitions = protocolDefinitions

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
            func extensionDefinition(of kind: ExtensionDefinition.Kind, for memberSymbolsByKind: OrderedDictionary<SymbolIndexStore.MemberKind, [DemangledSymbol]>, genericSignature: Node?) -> ExtensionDefinition {
                var extensionDefinition = ExtensionDefinition(name: name, kind: kind, genericSignature: genericSignature, protocolConformance: nil, associatedType: nil)
                for (kind, memberSymbols) in memberSymbolsByKind {
                    let nodes = memberSymbols.map(\.demangledNode)
                    switch kind {
                    case .allocatorInExtension:
                        extensionDefinition.allocators.append(contentsOf: TypeDefinition.allocators(for: nodes))
                    case .variableInExtension:
                        extensionDefinition.variables.append(contentsOf: TypeDefinition.variables(for: nodes, fieldNames: []))
                    case .functionInExtension:
                        extensionDefinition.functions.append(contentsOf: TypeDefinition.functions(for: nodes))
                    case .staticVariableInExtension:
                        extensionDefinition.staticVariables.append(contentsOf: TypeDefinition.variables(for: nodes, fieldNames: []))
                    case .staticFunctionInExtension:
                        extensionDefinition.staticFunctions.append(contentsOf: TypeDefinition.functions(for: nodes))
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
                    typeExtensionDefinitions[typeName, default: []].append(extensionDefinition(of: .type(typeKind), for: memberSymbolsByKind, genericSignature: node))
                }
                if !memberSymbolsByKind.isEmpty {
                    typeExtensionDefinitions[typeName, default: []].append(extensionDefinition(of: .type(typeKind), for: memberSymbolsByKind, genericSignature: nil))
                }

            } else if typeInfo.kind == .protocol {
                let protocolName = ProtocolName(name: name)

                for (node, memberSymbolsByKind) in memberSymbolsByGenericSignature {
                    protocolExtensionDefinitions[protocolName, default: []].append(extensionDefinition(of: .protocol, for: memberSymbolsByKind, genericSignature: node))
                }
                if !memberSymbolsByKind.isEmpty {
                    protocolExtensionDefinitions[protocolName, default: []].append(extensionDefinition(of: .protocol, for: memberSymbolsByKind, genericSignature: nil))
                }
            } else {
                for (node, memberSymbolsByKind) in memberSymbolsByGenericSignature {
                    typeAliasExtensionDefinitions[name, default: []].append(extensionDefinition(of: .typeAlias, for: memberSymbolsByKind, genericSignature: node))
                }
                if !memberSymbolsByKind.isEmpty {
                    typeAliasExtensionDefinitions[name, default: []].append(extensionDefinition(of: .typeAlias, for: memberSymbolsByKind, genericSignature: nil))
                }
            }
        }
        self.typeExtensionDefinitions = typeExtensionDefinitions
        self.protocolExtensionDefinitions = protocolExtensionDefinitions
        self.typeAliasExtensionDefinitions = typeAliasExtensionDefinitions
    }

    @SemanticStringBuilder
    public func build() throws -> SemanticString {
        for module in Self.internalModules + importedModules.sorted() {
            Standard("import \(module)")
            BreakLine()
        }

        BreakLine()

        for (offset, typeDefinition) in typeDefinitions.values.offsetEnumerated() {
            if offset.isStart {
                BreakLine()
                BreakLine()
            }

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

        for (offset, extensionDefinition) in (typeExtensionDefinitions.values.flatMap({ $0 }) + protocolExtensionDefinitions.values.flatMap({ $0 }) + typeAliasExtensionDefinitions.values.flatMap({ $0 }) + conformanceExtensionDefinitions.values.flatMap({ $0 })).offsetEnumerated() {
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
    private func printTypeDefinition(_ typeDefinition: TypeDefinition, level: Int = 1) throws -> SemanticString {
        let dumper = typeDefinition.type.dumper(using: .init(demangleOptions: .interface, indentation: level, displayParentName: level == 1), in: machO)
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

        let fields = try dumper.fields

        if fields.string.isEmpty, level == 1, !typeDefinition.typeChildren.isEmpty {
            BreakLine()
        } else {
            fields
        }

        try printDefinition(typeDefinition, level: level)

        if level > 1, typeDefinition.hasMembers {
            Indent(level: level - 1)
        }

        Standard("}")
    }

    @SemanticStringBuilder
    private func printProtocolDefinition(_ protocolDefinition: ProtocolDefinition) throws -> SemanticString {
        let dumper = ProtocolDumper(protocolDefinition.protocol, using: .init(demangleOptions: .interface), in: machO)
        try dumper.declaration
        Space()
        Standard("{")
        try dumper.associatedTypes
        for (offset, requirment) in protocolDefinition.requirements.offsetEnumerated() {
            BreakLine()
            Indent(level: 1)
            var printer: any InterfaceNodePrinter = switch requirment {
            case .function:
                FunctionNodePrinter()
            case .variable(let variable):
                VariableNodePrinter(hasSetter: variable.hasSetter, indentation: 1)
            }
            try printer.printRoot(requirment.node)

            if offset.isEnd {
                BreakLine()
            }
        }
        Standard("}")
    }

    @SemanticStringBuilder
    private func printExtensionDefinition(_ extensionDefinition: ExtensionDefinition) throws -> SemanticString {
        Keyword(.extension)
        Space()
        extensionDefinition.printName()
        if let protocolConformance = extensionDefinition.protocolConformance, let protocolName = try? protocolConformance.dumpProtocolName(using: .interfaceType, in: machO) {
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
                node.printSemantic(using: .interface)
                if !offset.isEnd {
                    Standard(",")
                    Space()
                }
            }
        }
        Space()
        Standard("{")
        if let associatedType = extensionDefinition.associatedType {
            let dumper = AssociatedTypeDumper(associatedType, using: .init(demangleOptions: .interface), in: machO)
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
            var printer = FunctionNodePrinter()
            try printer.printRoot(allocator.node)

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, variable) in definition.variables.offsetEnumerated() {
            BreakLine()
            Indent(level: level)
            var printer = VariableNodePrinter(hasSetter: variable.hasSetter, indentation: level)
            try printer.printRoot(variable.node)

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, function) in definition.functions.offsetEnumerated() {
            BreakLine()
            Indent(level: level)
            var printer = FunctionNodePrinter()
            try printer.printRoot(function.node)

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, variable) in definition.staticVariables.offsetEnumerated() {
            BreakLine()
            Indent(level: level)
            var printer = VariableNodePrinter(hasSetter: variable.hasSetter, indentation: level)
            try printer.printRoot(variable.node)

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, function) in definition.staticFunctions.offsetEnumerated() {
            BreakLine()
            Indent(level: level)
            var printer = FunctionNodePrinter()
            try printer.printRoot(function.node)

            if offset.isEnd {
                BreakLine()
            }
        }
    }

    private func collectModules() throws {
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

extension ProtocolConformance {
    func typeName<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> TypeName? {
        switch typeReference {
        case .directTypeDescriptor(let descriptor):
            return try descriptor?.typeContextDescriptorWrapper?.typeName(in: machO)
        case .indirectTypeDescriptor(let descriptorOrSymbol):
            switch descriptorOrSymbol {
            case .symbol(let symbol):
                let node = try demangleAsNode(symbol.stringValue)
                print(#function, node)
                let allChildren = node.map { $0 }
                let kind: TypeKind
                if allChildren.contains(.enum) || allChildren.contains(.boundGenericEnum) {
                    kind = .enum
                } else if allChildren.contains(.structure) || allChildren.contains(.boundGenericStructure) {
                    kind = .struct
                } else if allChildren.contains(.class) || allChildren.contains(.boundGenericClass) {
                    kind = .class
                } else {
                    return nil
                }
                return .init(name: node.print(using: .interfaceType), kind: kind)

            case .element(let element):
                return try element.typeContextDescriptorWrapper?.typeName(in: machO)

            case nil:
                return nil
            }
        case .directObjCClassName,
             .indirectObjCClass:
            return try .init(name: dumpTypeName(using: .interfaceType, in: machO).string, kind: .class)
        }
    }

    func protocolName<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> ProtocolName? {
        try .init(name: dumpProtocolName(using: .interfaceType, in: machO).string)
    }
}

extension AssociatedType {
    
    func typeName<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> TypeName? {
        let node = try MetadataReader.demangleSymbol(for: conformingTypeName, in: machO)
        let kind: TypeKind
        if node.contains(.enum) || node.contains(.boundGenericEnum) {
            kind = .enum
        } else if node.contains(.structure) || node.contains(.boundGenericStructure) {
            kind = .struct
        } else if node.contains(.class) || node.contains(.boundGenericClass) {
            kind = .class
        } else {
            return nil
        }
        return try .init(name: dumpTypeName(using: .interfaceType, in: machO).string, kind: kind)
    }
    
    func protocolName<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> ProtocolName {
        try .init(name: dumpProtocolName(using: .interfaceType, in: machO).string)
    }
}

extension MachOSwiftSection.`Protocol` {
    func protocolName<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> ProtocolName {
        try .init(name: dumpName(using: .interfaceType, in: machO).string)
    }
}

extension TypeWrapper {
    func typeName<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> TypeName {
        try typeContextDescriptorWrapper.typeName(in: machO)
    }
}

extension TypeContextDescriptorWrapper {
    var kind: TypeKind {
        switch self {
        case .enum:
            .enum
        case .struct:
            .struct
        case .class:
            .class
        }
    }

    func typeName<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> TypeName {
        return try .init(name: ContextDescriptorWrapper.type(self).dumpName(using: .interfaceType, in: machO).string, kind: kind)
    }
}

extension FieldRecord {
    func demangledTypeNode<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> Node {
        try MetadataReader.demangleType(for: mangledTypeName(in: machO), in: machO)
    }

    func demangledTypeName<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> SemanticString {
        try demangledTypeNode(in: machO).printSemantic(using: .interface)
    }
}

extension SymbolIndexStore.TypeInfo.Kind {
    var typeKind: TypeKind? {
        switch self {
        case .enum:
            .enum
        case .struct:
            .struct
        case .class:
            .class
        default:
            nil
        }
    }
}
