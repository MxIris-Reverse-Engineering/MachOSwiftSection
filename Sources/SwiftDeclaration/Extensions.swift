import Foundation
import MachOKit
import MachOSwiftSection
import MemberwiseInit
import OrderedCollections
import SwiftDump
import Demangling
import Semantic
import SwiftStdlibToolbox
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection

extension Node {
    package var accessorKind: AccessorKind {
        guard let node = first(of: .getter, .setter, .modifyAccessor, .readAccessor) else { return .none }
        switch node.kind {
        case .getter: return .getter
        case .setter: return .setter
        case .modifyAccessor: return .modifyAccessor
        case .readAccessor: return .readAccessor
        default: return .none
        }
    }
}

extension ProtocolConformance {
    package func typeName(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> TypeName? {
        switch typeReference {
        case .directTypeDescriptor(let descriptor):
            return try descriptor?.typeContextDescriptorWrapper?.typeName(in: machO)
        case .indirectTypeDescriptor(let descriptorOrSymbol):
            switch descriptorOrSymbol {
            case .symbol(let symbol):
                guard let node = try MetadataReader.demangleType(for: symbol, in: machO)?.first(of: .type) else { return nil }
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
                return TypeName(node: node, kind: kind)

            case .element(let element):
                return try element.typeContextDescriptorWrapper?.typeName(in: machO)

            case nil:
                return nil
            }
        case .directObjCClassName,
             .indirectObjCClass:
            guard let node = try typeNode(in: machO) else { return nil }
            return TypeName(node: node, kind: .class)
        }
    }
    
    package func typeName() throws -> TypeName? {
        switch typeReference {
        case .directTypeDescriptor(let descriptor):
            return try descriptor?.typeContextDescriptorWrapper?.typeName()
        case .indirectTypeDescriptor(let descriptorOrSymbol):
            switch descriptorOrSymbol {
            case .symbol(let symbol):
                guard let node = try MetadataReader.demangleType(for: symbol)?.first(of: .type) else { return nil }
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
                return TypeName(node: node, kind: kind)
            case .element(let element):
                return try element.typeContextDescriptorWrapper?.typeName()
            case nil:
                return nil
            }
        case .directObjCClassName,
             .indirectObjCClass:
            guard let node = try typeNode() else { return nil }
            return TypeName(node: node, kind: .class)
        }
    }

    package func protocolName(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> ProtocolName? {
        guard let node = try protocolNode(in: machO) else { return nil }
        return ProtocolName(node: node)
    }
    
    package func protocolName() throws -> ProtocolName? {
        guard let node = try protocolNode() else { return nil }
        return ProtocolName(node: node)
    }
}

extension AssociatedType {
    package func typeName(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> TypeName? {
        let node = try MetadataReader.demangleType(for: conformingTypeName, in: machO)
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
        return TypeName(node: node, kind: kind)
    }
    
    package func typeName() throws -> TypeName? {
        let node = try MetadataReader.demangleType(for: conformingTypeName)
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
        return TypeName(node: node, kind: kind)
    }

    package func protocolName(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> ProtocolName {
        try ProtocolName(node: MetadataReader.demangleType(for: protocolTypeName, in: machO))
    }
    
    package func protocolName() throws -> ProtocolName {
        try ProtocolName(node: MetadataReader.demangleType(for: protocolTypeName))
    }
}

extension MachOSwiftSection.`Protocol` {
    package func protocolName(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> ProtocolName {
        try descriptor.protocolName(in: machO)
    }
    
    package func protocolName() throws -> ProtocolName {
        try descriptor.protocolName()
    }
}

extension ProtocolDescriptor {
    package func protocolName(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> ProtocolName {
        try ProtocolName(node: MetadataReader.demangleContext(for: .protocol(self), in: machO))
    }
    
    package func protocolName() throws -> ProtocolName {
        try ProtocolName(node: MetadataReader.demangleContext(for: .protocol(self)))
    }
}

extension TypeContextWrapper {
    package func typeName(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> TypeName {
        try typeContextDescriptorWrapper.typeName(in: machO)
    }
    
    package func typeName() throws -> TypeName {
        try typeContextDescriptorWrapper.typeName()
    }
}

extension TypeContextDescriptorWrapper {
    package var kind: TypeKind {
        switch self {
        case .enum:
            .enum
        case .struct:
            .struct
        case .class:
            .class
        }
    }

    package func typeName(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> TypeName {
        return try TypeName(node: MetadataReader.demangleContext(for: .type(self), in: machO), kind: kind)
    }
    
    package func typeName() throws -> TypeName {
        return try TypeName(node: MetadataReader.demangleContext(for: .type(self)), kind: kind)
    }
}

extension FieldRecord {
    package func demangledTypeNode(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> Node {
        try MetadataReader.demangleType(for: mangledTypeName(in: machO), in: machO)
    }

    package func demangledTypeName(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> SemanticString {
        try demangledTypeNode(in: machO).printSemantic(using: .interfaceTypeBuilderOnly)
    }
    
    package func demangledTypeNode() throws -> Node {
        try MetadataReader.demangleType(for: mangledTypeName())
    }

    package func demangledTypeName() throws -> SemanticString {
        try demangledTypeNode().printSemantic(using: .interfaceTypeBuilderOnly)
    }
}

extension Node {
    public var typeKind: TypeKind? {
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

extension Sequence {
    package func filterNonNil<T, E: Swift.Error>(_ filter: (Element) throws(E) -> T?) throws(E) -> [Element] {
        var results: [Element] = []
        for element in self {
            if try filter(element) != nil {
                results.append(element)
            }
        }
        return results
    }

    package func firstNonNil<T, E: Swift.Error>(_ transform: (Element) throws(E) -> T?) throws(E) -> T? {
        for element in self {
            if let newElement = try transform(element) {
                return newElement
            }
        }
        return nil
    }

    package func asyncFirstNonNil<T, E: Swift.Error>(_ transform: (Element) async throws(E) -> T?) async throws(E) -> T? {
        for element in self {
            if let newElement = try await transform(element) {
                return newElement
            }
        }
        return nil
    }
}

extension StrippedSymbolicRequirement {
    @SemanticStringBuilder
    package func strippedSymbolicInfo() -> SemanticString {
        Comment(
            """
            Kind: \(requirement.layout.flags.kind.description), isAsync: \(requirement.layout.flags.isAsync), isInstance: \(requirement.layout.flags.isInstance)
            """
        )
    }
}
