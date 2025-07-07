import Foundation
import MachOSwiftSection
import MemberwiseInit
import OrderedCollections

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
class TypeDeclaration {
    let typeWrapper: TypeWrapper

    weak var parent: TypeDeclaration?

    var children: [TypeDeclaration] = []

    var extensionContext: ExtensionContext?

    var protocolConformances: [ProtocolConformance] = []
}

@MemberwiseInit
class TypeExtension {
    let typeName: TypeName

    let protocolConformance: ProtocolConformance?
}

@MemberwiseInit
class ProtocolDeclaration {
    let `protocol`: MachOSwiftSection.`Protocol`

    weak var parent: TypeDeclaration?

    var extensionContext: ExtensionContext?
}

@MemberwiseInit
class ProtocolExtension {
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

    private var topLevelTypes: OrderedDictionary<TypeName, TypeDeclaration> = [:]

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

    private func index() throws {
        for type in types {
            var parent = try ContextWrapper.type(type).parent(in: machO)?.resolved
            var typeParents: [TypeWrapper] = []
            var extensionContext: ExtensionContext?
            while let currentParent = parent {
                if let _extensionContext = currentParent.extension {
                    extensionContext = _extensionContext
                } else if let typeContext = currentParent.type {
                    typeParents.append(typeContext)
                }
                parent = try currentParent.parent(in: machO)?.resolved
            }
            for typeParent in typeParents {
                
            }
//            TypeDefinition(typeWrapper: type, parent: typeParents.first, extensionContext: extensionContext)
        }
    }

    public func build() throws -> String {
        return output
    }
}
