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

extension Node {
    var accessorKind: AccessorKind {
        guard let node = first(of: .getter, .setter, .modifyAccessor, .modify2Accessor, .readAccessor, .read2Accessor) else { return .none }
        switch node.kind {
        case .getter: return .getter
        case .setter: return .setter
        case .modifyAccessor,
             .modify2Accessor: return .modifyAccessor
        case .readAccessor,
             .read2Accessor: return .readAccessor
        default: return .none
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

    func protocolName<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> ProtocolName? {
        guard let node = try protocolNode(in: machO) else { return nil }
        return ProtocolName(node: node)
    }
}

extension AssociatedType {
    func typeName<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> TypeName? {
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

    func protocolName<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> ProtocolName {
        try ProtocolName(node: MetadataReader.demangleType(for: protocolTypeName, in: machO))
    }
}

extension MachOSwiftSection.`Protocol` {
    func protocolName<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> ProtocolName {
        try ProtocolName(node: MetadataReader.demangleContext(for: .protocol(descriptor), in: machO))
    }
}

extension TypeContextWrapper {
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
        return try TypeName(node: MetadataReader.demangleContext(for: .type(self), in: machO), kind: kind)
    }
}

extension FieldRecord {
    func demangledTypeNode<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> Node {
        try MetadataReader.demangleType(for: mangledTypeName(in: machO), in: machO)
    }

    func demangledTypeName<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> SemanticString {
        try demangledTypeNode(in: machO).printSemantic(using: .interfaceTypeBuilderOnly)
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

extension Sequence {
    func filterNonNil<T, E: Swift.Error>(_ filter: (Element) throws(E) -> T?) throws(E) -> [Element] {
        var results: [Element] = []
        for element in self {
            if try filter(element) != nil {
                results.append(element)
            }
        }
        return results
    }

    func firstNonNil<T, E: Swift.Error>(_ transform: (Element) throws(E) -> T?) throws(E) -> T? {
        for element in self {
            if let newElement = try transform(element) {
                return newElement
            }
        }
        return nil
    }

    func asyncFirstNonNil<T, E: Swift.Error>(_ transform: (Element) async throws(E) -> T?) async throws(E) -> T? {
        for element in self {
            if let newElement = try await transform(element) {
                return newElement
            }
        }
        return nil
    }
}

extension ProtocolRequirement {
    @SemanticStringBuilder
    func strippedSymbolicInfo() -> SemanticString {
        Comment(
            """
            Kind: \(layout.flags.kind.description), isAsync: \(layout.flags.isAsync), isInstance: \(layout.flags.isInstance)
            """
        )
    }
}

extension ProtocolRequirementKind: CustomStringConvertible {
    public var description: String {
        switch self {
        case .baseProtocol:
            "BaseProtocol"
        case .method:
            "Method"
        case .`init`:
            "Init"
        case .getter:
            "Getter"
        case .setter:
            "Setter"
        case .readCoroutine:
            "ReadCoroutine"
        case .modifyCoroutine:
            "ModifyCoroutine"
        case .associatedTypeAccessFunction:
            "AssociatedTypeAccessFunction"
        case .associatedConformanceAccessFunction:
            "AssociatedConformanceAccessFunction"
        }
    }
}
