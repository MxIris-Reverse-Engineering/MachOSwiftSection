import Foundation
import MachOSwiftSection
import MemberwiseInit
import OrderedCollections
import SwiftDump
import Demangle

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
}

@MemberwiseInit
final class TypeExtension {
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
final class ProtocolExtension {
    let protocolName: ProtocolName
}

public final class SwiftInterfaceBuilder<MachO: MachOSwiftSectionRepresentableWithCache> {
    private let machO: MachO

    private let enums: [Enum]

    private let structs: [Struct]

    private let classes: [Class]

    private let types: [TypeWrapper]

    private let protocols: [MachOSwiftSection.`Protocol`]

    private let protocolConformances: [ProtocolConformance]

    private let associatedTypes: [AssociatedType]

    private var protocolConformancesByTypeName: [TypeName: [ProtocolConformance]] = [:]

    private var associatedTypesByTypeName: [TypeName: [AssociatedType]] = [:]

    private var output: String = ""

    private var importedModules: OrderedSet<String> = []

    private var topLevelTypes: OrderedDictionary<TypeName, TypeDefinition> = [:]

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

    func index() throws {
        for conformance in protocolConformances {
            if let typeName = try? conformance.typeName(in: machO) {
                protocolConformancesByTypeName[typeName, default: []].append(conformance)
            }
        }

        var definitionsCache: OrderedDictionary<TypeName, TypeDefinition> = [:]

        for type in types {
            if let typeName = try? type.typeName(in: machO) {
                let declaration = TypeDefinition(
                    type: type,
                    typeName: typeName,
                    protocolConformances: protocolConformancesByTypeName[typeName] ?? []
                )
                definitionsCache[typeName] = declaration
            }
        }

        for type in types {
            if let typeName = try? type.typeName(in: machO) {
                guard let childDefinition = definitionsCache[typeName] else {
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
        }

        for (typeName, definition) in definitionsCache {
            if definition.parent == nil {
                topLevelTypes[typeName] = definition
            }
        }
    }

    public func build() throws -> String {
        return output
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
        try typeContextDescriptor.typeName(in: machO)
    }
}

extension TypeContextDescriptorWrapper {
    func typeName<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> TypeName {
        let kind: TypeKind = switch self {
        case .enum(let `enum`):
            .enum
        case .struct(let `struct`):
            .struct
        case .class(let `class`):
            .class
        }
        return try .init(name: ContextDescriptorWrapper.type(self).dumpName(using: .interfaceType, in: machO).string, kind: kind)
    }
}
