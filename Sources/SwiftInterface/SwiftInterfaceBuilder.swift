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
final class TypeDefinition {
    let type: TypeWrapper

    let typeName: TypeName

    weak var parent: TypeDefinition?

    var children: [TypeDefinition] = []

    var extensionContext: ExtensionContext?

    var protocolConformances: [ProtocolConformance] = []

    var fields: [TypeFieldDefinition] = []

    var variables: [TypeVariableDefinition] = []

    var functions: [TypeFunctionDefinition] = []

    var staticVariables: [TypeVariableDefinition] = []

    var staticFunctions: [TypeFunctionDefinition] = []

    var allocators: [TypeFunctionDefinition] = []

    var hasMembers: Bool {
        !fields.isEmpty || !variables.isEmpty || !functions.isEmpty || !staticVariables.isEmpty || !staticFunctions.isEmpty || !allocators.isEmpty
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

        func variables(for demangledSymbols: [DemangledSymbol]) -> [TypeVariableDefinition] {
            typealias NodeAndVariableKinds = (node: Node, kind: TypeVariableKind)
            var variables: [TypeVariableDefinition] = []
            var nodeAndVariableKindsByName: [String: [NodeAndVariableKinds]] = [:]
            for demangledSymbol in demangledSymbols {
                let node = demangledSymbol.demangledNode
                guard let variableNode = node.first(of: .variable) else { continue }
                guard let name = variableNode.children.at(1)?.contents.name else { continue }
                guard let variableKind = node.variableKind else { continue }
                nodeAndVariableKindsByName[name, default: []].append((node, variableKind))
            }

            for (name, nodeAndVariableKinds) in nodeAndVariableKindsByName {
                guard !fieldNames.contains(name) else { continue }
                let nodes = nodeAndVariableKinds.map(\.node)
                let kinds = nodeAndVariableKinds.map(\.kind)
                variables.append(.init(nodes: nodes, name: name, hasSetter: kinds.contains(.setter), hasModifyAccessor: kinds.contains(.modifyAccessor)))
            }
            return variables
        }
        func functions(for demangledSymbols: [DemangledSymbol]) -> [TypeFunctionDefinition] {
            var functions: [TypeFunctionDefinition] = []
            for demangledSymbol in demangledSymbols {
                guard let functionNode = demangledSymbol.demangledNode.first(of: .function), let name = functionNode.children.at(1)?.contents.name else { continue }
                functions.append(.init(node: demangledSymbol.demangledNode, name: .function(name)))
            }
            return functions
        }

        self.variables = variables(for: SymbolIndexStore.shared.memberSymbols(of: .variable, for: typeName.name, in: machO))
        staticVariables = variables(for: SymbolIndexStore.shared.memberSymbols(of: .staticVariable, for: typeName.name, in: machO))

        self.functions = functions(for: SymbolIndexStore.shared.memberSymbols(of: .function, for: typeName.name, in: machO))
        staticFunctions = functions(for: SymbolIndexStore.shared.memberSymbols(of: .staticFunction, for: typeName.name, in: machO))
        allocators = SymbolIndexStore.shared.memberSymbols(of: .allocator, for: typeName.name, in: machO).map { .init(node: $0.demangledNode, name: .allocator) }
    }
}

extension Node {
    var variableKind: TypeVariableKind? {
        guard let node = first(of: .getter, .setter, .modifyAccessor) else { return nil }
        switch node.kind {
        case .getter: return .getter
        case .setter: return .setter
        case .modifyAccessor: return .modifyAccessor
        default: return nil
        }
    }
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

enum TypeVariableKind {
    case getter
    case setter
    case modifyAccessor
}

@MemberwiseInit
struct TypeVariableDefinition {
    let nodes: [Node]
    let name: String
    let hasSetter: Bool
    let hasModifyAccessor: Bool
}

@MemberwiseInit
struct TypeFunctionDefinition {
    let node: Node
    enum Name {
        case function(String)
        case allocator
        case deallocator
    }

    let name: Name
}

@MemberwiseInit
struct TypeExtensionDefinition {
    let type: TypeWrapper

    let typeName: TypeName

    let protocolConformance: ProtocolConformance?
}

@MemberwiseInit
final class ProtocolDefinition {
    let `protocol`: MachOSwiftSection.`Protocol`

    weak var parent: TypeDefinition?

    var extensionContext: ExtensionContext?
}

@MemberwiseInit
struct ProtocolExtensionDefinition {
    let protocolName: ProtocolName
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
    private var protocolConformancesByTypeName: [TypeName: [ProtocolConformance]] = [:]

    @Mutex
    private var associatedTypesByTypeName: [TypeName: [AssociatedType]] = [:]

    @Mutex
    private var importedModules: OrderedSet<String> = []

    @Mutex
    private var topLevelTypeDefinitions: OrderedDictionary<TypeName, TypeDefinition> = [:]

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
        collectModules()
    }

    private func index() throws {
        for conformance in protocolConformances {
            if let typeName = try? conformance.typeName(in: machO) {
                protocolConformancesByTypeName[typeName, default: []].append(conformance)
            }
        }

        var definitionsCache: OrderedDictionary<TypeName, TypeDefinition> = [:]

        for type in types {
            guard let module = try? type.contextDescriptorWrapper.contextDescriptor.moduleContextDesciptor(in: machO) else { continue }

            guard let moduleName = try? module.name(in: machO), moduleName != cModule, moduleName != objcModule else { continue }

            guard let typeName = try? type.typeName(in: machO) else { continue }

            let declaration = TypeDefinition(type: type, typeName: typeName, protocolConformances: protocolConformancesByTypeName[typeName] ?? [])

            do {
                try declaration.index(in: machO)
                definitionsCache[typeName] = declaration
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
                        parentDefinition.children.append(childDefinition)
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

        for (typeName, definition) in definitionsCache {
            if definition.parent == nil {
                topLevelTypeDefinitions[typeName] = definition
            }
        }
    }

    @SemanticStringBuilder
    public func build() throws -> SemanticString {
        for module in Self.internalModules + importedModules.sorted() {
            Standard("import \(module)")
            BreakLine()
        }

        BreakLine()

        for (offset, typeDefinition) in topLevelTypeDefinitions.values.offsetEnumerated() {
            try printTypeDefinition(typeDefinition)

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

        for child in typeDefinition.children {
            BreakLine()
            try printTypeDefinition(child, level: level + 1)
        }

        let fields = try dumper.fields

        if fields.string.isEmpty, level == 1, !typeDefinition.children.isEmpty {
            BreakLine()
        } else {
            fields
        }

        for (offset, variable) in typeDefinition.variables.offsetEnumerated() {
            let node = variable.nodes.first { $0.contains(.getter) }
            if let node {
                BreakLine()
                Indent(level: level)
                var printer = VariableNodePrinter(hasSetter: variable.hasSetter)
                try printer.printRoot(node)

                if offset.isEnd {
                    BreakLine()
                }
            }
        }

        for (offset, allocator) in typeDefinition.allocators.offsetEnumerated() {
            BreakLine()
            Indent(level: level)
            var printer = FunctionNodePrinter()
            try printer.printRoot(allocator.node)

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, function) in typeDefinition.functions.offsetEnumerated() {
            BreakLine()
            Indent(level: level)
            var printer = FunctionNodePrinter()
            try printer.printRoot(function.node)

            if offset.isEnd {
                BreakLine()
            }
        }

        for (offset, variable) in typeDefinition.staticVariables.offsetEnumerated() {
            let node = variable.nodes.first { $0.contains(.getter) }
            if let node {
                BreakLine()
                Indent(level: level)
                var printer = VariableNodePrinter(hasSetter: variable.hasSetter)
                try printer.printRoot(node)

                if offset.isEnd {
                    BreakLine()
                }
            }
        }

        for (offset, function) in typeDefinition.staticFunctions.offsetEnumerated() {
            BreakLine()
            Indent(level: level)
            var printer = FunctionNodePrinter()
            try printer.printRoot(function.node)

            if offset.isEnd {
                BreakLine()
            }
        }

        if level > 1, typeDefinition.hasMembers {
            Indent(level: level - 1)
        }

        Standard("}")
    }

    private func collectModules() {
        var usedModules: OrderedSet<String> = []
        let filterModules: Set<String> = [cModule, objcModule, stdlibName]

        func addModule(_ module: String) {
            if !filterModules.contains(module) {
                usedModules.append(module)
            }
        }

        for symbol in machO.symbols where symbol.name.isSwiftSymbol {
            if let globalNode = try? symbol.demangledNode {
                for moduleNode in globalNode.preorder().all(of: .module) {
                    if let module = moduleNode.text, !filterModules.contains(module) {
                        usedModules.append(module)
                    }
                }
            }
        }

        for symbol in machO.exportedSymbols where symbol.name.isSwiftSymbol {
            if let globalNode = try? symbol.demangledNode {
                for moduleNode in globalNode.preorder().all(of: .module) {
                    if let module = moduleNode.text, !filterModules.contains(module) {
                        usedModules.append(module)
                    }
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

                let allChildren = node.preorder().map { $0 }
                let kind: TypeKind
                if allChildren.contains(.enum) {
                    kind = .enum
                } else if allChildren.contains(.structure) {
                    kind = .struct
                } else if allChildren.contains(.class) {
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
}

extension TypeWrapper {
    func typeName<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> TypeName {
        try typeContextDescriptorWrapper.typeName(in: machO)
    }
}

extension TypeContextDescriptorWrapper {
    func typeName<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> TypeName {
        let kind: TypeKind = switch self {
        case .enum:
            .enum
        case .struct:
            .struct
        case .class:
            .class
        }
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
