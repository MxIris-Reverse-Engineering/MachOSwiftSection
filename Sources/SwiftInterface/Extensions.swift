import Foundation
import MachOSwiftSection
import MemberwiseInit
import OrderedCollections
import SwiftDump
import Demangle
import Semantic
import SwiftStdlibToolbox

extension Node {
    var accessorKind: AccessorKind? {
        guard let node = first(of: .getter, .setter, .modifyAccessor) else { return nil }
        switch node.kind {
        case .getter: return .getter
        case .setter: return .setter
        case .modifyAccessor, .modify2Accessor: return .modifyAccessor
        default: return nil
        }
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
                let node = try demangleAsNode(symbol.name)
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
                return .init(name: node.print(using: .interfaceTypeBuilderOnly), kind: kind)

            case .element(let element):
                return try element.typeContextDescriptorWrapper?.typeName(in: machO)

            case nil:
                return nil
            }
        case .directObjCClassName,
             .indirectObjCClass:
            return try .init(name: dumpTypeName(using: .interfaceTypeBuilderOnly, in: machO).string, kind: .class)
        }
    }

    func protocolName<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> ProtocolName? {
        try .init(name: dumpProtocolName(using: .interfaceTypeBuilderOnly, in: machO).string)
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
        return try .init(name: dumpTypeName(using: .interfaceTypeBuilderOnly, in: machO).string, kind: kind)
    }

    func protocolName<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> ProtocolName {
        try .init(name: dumpProtocolName(using: .interfaceTypeBuilderOnly, in: machO).string)
    }
}

extension MachOSwiftSection.`Protocol` {
    func protocolName<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> ProtocolName {
        try .init(name: dumpName(using: .interfaceTypeBuilderOnly, in: machO).string)
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
        return try .init(name: ContextDescriptorWrapper.type(self).dumpName(using: .interfaceTypeBuilderOnly, in: machO).string, kind: kind)
    }
}

extension FieldRecord {
    func demangledTypeNode<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> Node {
        try MetadataReader.demangleType(for: mangledTypeName(in: machO), in: machO)
    }

    func demangledTypeName<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> SemanticString {
        try demangledTypeNode(in: machO).printSemantic(using: .interfaceBuilderOnly)
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

extension Node {
    var typeKind: TypeKind? {
        func findKind(_ node: Node) -> TypeKind? {
            if node.contains(.enum) || node.contains(.boundGenericEnum) {
                return .enum
            } else if node.contains(.structure) || node.contains(.boundGenericStructure) {
                return .struct
            } else if node.contains(.class) || node.contains(.boundGenericClass) {
                return .class
            } else {
                return nil
            }
        }
        if let node = first(of: .type) {
            return findKind(node)
        } else {
            return findKind(self)
        }
    }
}
