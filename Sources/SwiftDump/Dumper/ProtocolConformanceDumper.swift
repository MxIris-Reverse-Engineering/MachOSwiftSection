import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Demangling
import Utilities
import OrderedCollections
import SwiftInspection

package struct ProtocolConformanceDumper<MachO: MachOSwiftSectionRepresentableWithCache>: ConformedDumper {
    package let dumped: ProtocolConformance

    package let configuration: DumperConfiguration

    package let machO: MachO

    private var typeNameOptions: DemangleOptions { .interfaceType }

    package init(_ dumped: ProtocolConformance, using configuration: DumperConfiguration, in machO: MachO) {
        self.dumped = dumped
        self.configuration = configuration
        self.machO = machO
    }

    private var demangleResolver: DemangleResolver {
        configuration.demangleResolver
    }

    package var declaration: SemanticString {
        get async throws {
            Keyword(.extension)

            Space()

            try await typeName

            Standard(":")

            Space()

            try await protocolName

            if !dumped.conditionalRequirements.isEmpty {
                Space()
                Keyword(.where)
                Space()
            }

            for conditionalRequirement in dumped.conditionalRequirements {
                try await conditionalRequirement.dump(resolver: demangleResolver, in: machO)
            }
        }
    }

    package var body: SemanticString {
        get async throws {
            try await declaration

            let typeNameString = try await typeName.string

            if dumped.resilientWitnesses.isEmpty {
                Space()
                Standard("{}")
            } else {
                Space()
                Standard("{")

                var visitedNodes: OrderedSet<Node> = []

                for resilientWitness in dumped.resilientWitnesses {
                    BreakLine()

                    Indent(level: 1)

                    if let symbols = try resilientWitness.implementationSymbols(in: machO), let node = try await _node(for: symbols, typeName: typeNameString, visitedNodes: visitedNodes) {
                        _ = visitedNodes.append(node)
                        try await demangleResolver.resolve(for: node)
                    } else if let requirement = try resilientWitness.requirement(in: machO) {
                        switch requirement {
                        case .symbol(let symbol):
                            try await MetadataReader.demangleSymbol(for: symbol, in: machO).asyncMap { try await demangleResolver.resolve(for: $0) }
                        case .element(let element):
                            if let symbols = try await Symbols.resolve(from: element.offset, in: machO), let node = try await _node(for: symbols, typeName: typeNameString, visitedNodes: visitedNodes) {
                                _ = visitedNodes.append(node)
                                try await demangleResolver.resolve(for: node)
                            } else if let defaultImplementationSymbols = try element.defaultImplementationSymbols(in: machO), let node = try await _node(for: defaultImplementationSymbols, typeName: typeNameString, visitedNodes: visitedNodes) {
                                _ = visitedNodes.append(node)
                                try await demangleResolver.resolve(for: node)
                            } else if !element.defaultImplementation.isNull {
                                FunctionDeclaration(addressString(of: element.defaultImplementation.resolveDirectOffset(from: element.offset(of: \.defaultImplementation)), in: machO).insertSubFunctionPrefix)
                            } else if !resilientWitness.implementation.isNull {
//                                do {
//                                try demangleResolver.resolve(for: MetadataReader.demangle(for: MangledName.resolve(from: resilientWitness.implementation.resolveDirectOffset(from: resilientWitness.offset(of: \.implementation)) - 1, in: machO), in: machO))
//                                } catch {
                                FunctionDeclaration(addressString(of: resilientWitness.implementation.resolveDirectOffset(from: resilientWitness.offset(of: \.implementation)), in: machO).insertSubFunctionPrefix)
//                                }
                            } else {
                                Error("Symbol not found")
                            }
                        }
                    } else if !resilientWitness.implementation.isNull {
                        FunctionDeclaration(addressString(of: resilientWitness.implementation.resolveDirectOffset(from: resilientWitness.offset(of: \.implementation)), in: machO).insertSubFunctionPrefix)
                    } else {
                        Error("Symbol not found")
                    }
                }

                BreakLine()

                Standard("}")
            }
        }
    }

    @SemanticStringBuilder
    package var typeName: SemanticString {
        get async throws {
            try dumped.typeNode(in: machO)?.printSemantic(using: typeNameOptions).replacingTypeNameOrOtherToTypeDeclaration()
        }
    }

    @SemanticStringBuilder
    package var protocolName: SemanticString {
        get async throws {
            try await dumped.protocolNode(in: machO).asyncMap { try await demangleResolver.resolve(for: $0) }
        }
    }

    private func _node(for symbols: Symbols, typeName: String, visitedNodes: borrowing OrderedSet<Node> = []) async throws -> Node? {
        for symbol in symbols {
            if let node = try? MetadataReader.demangleSymbol(for: symbol, in: machO), let dumpedNode = node.preorder().first(where: { $0.kind == .protocolConformance }), let symbolTypeName = dumpedNode.children.at(0)?.print(using: .interfaceType), symbolTypeName == typeName || PrimitiveTypeMappingCache.shared.storage(in: machO)?.primitiveType(for: typeName) == symbolTypeName, !visitedNodes.contains(node) {
                return node
            }
        }
        return nil
    }
}

package func protocolConformanceDemangledSymbol<MachO: MachOSwiftSectionRepresentableWithCache>(for symbols: Symbols, typeName: String, visitedNodes: borrowing OrderedSet<Node> = [], in machO: MachO) throws -> DemangledSymbol? {
    for symbol in symbols {
        if let node = try? MetadataReader.demangleSymbol(for: symbol, in: machO), let targetNode = node.first(of: .protocolConformance), let symbolTypeName = targetNode.children.at(0)?.print(using: .interfaceType), symbolTypeName == typeName || PrimitiveTypeMappingCache.shared.storage(in: machO)?.primitiveType(for: typeName) == symbolTypeName, !visitedNodes.contains(node) {
            return .init(symbol: symbol, demangledNode: node)
        }
    }
    return nil
}

extension ResolvedTypeReference {
    package func node<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> Node? {
        switch self {
        case .directTypeDescriptor(let descriptor):
            return try descriptor.map { try MetadataReader.demangleContext(for: $0, in: machO) }
        case .indirectTypeDescriptor(let descriptor):
            switch descriptor {
            case .symbol(let symbol):
                return try MetadataReader.demangleType(for: symbol, in: machO)
            case .element(let element):
                return try MetadataReader.demangleContext(for: element, in: machO)
            case nil:
                return nil
            }
        case .directObjCClassName(let objcClassName):
            guard let objcClassName, !objcClassName.isEmpty else { return nil }
            return Node(kind: .type, children: [
                Node(kind: .class, children: [
                    .create(kind: .module, text: objcModule),
                    .create(kind: .identifier, text: objcClassName),
                ])
            ])
        case .indirectObjCClass(let objcClass):
            switch objcClass {
            case .symbol(let symbol):
                return try MetadataReader.demangleType(for: symbol, in: machO)
            case .element(let element):
                guard let classDescriptor = try element.descriptor.resolve(in: machO) else { return nil }
                return try MetadataReader.demangleContext(for: .type(.class(classDescriptor)), in: machO)
            case nil:
                return nil
            }
        }
    }
    
    package func node() throws -> Node? {
        switch self {
        case .directTypeDescriptor(let descriptor):
            return try descriptor.map { try MetadataReader.demangleContext(for: $0) }
        case .indirectTypeDescriptor(let descriptor):
            switch descriptor {
            case .symbol(let symbol):
                return try MetadataReader.demangleType(for: symbol)
            case .element(let element):
                return try MetadataReader.demangleContext(for: element)
            case nil:
                return nil
            }
        case .directObjCClassName(let objcClassName):
            guard let objcClassName, !objcClassName.isEmpty else { return nil }
            return Node(kind: .type, children: [
                Node(kind: .class, children: [
                    .create(kind: .module, text: objcModule),
                    .create(kind: .identifier, text: objcClassName),
                ])
            ])
        case .indirectObjCClass(let objcClass):
            switch objcClass {
            case .symbol(let symbol):
                return try MetadataReader.demangleType(for: symbol)
            case .element(let element):
                guard let classDescriptor = try element.descriptor.resolve() else { return nil }
                return try MetadataReader.demangleContext(for: .type(.class(classDescriptor)))
            case nil:
                return nil
            }
        }
    }
}

extension ProtocolConformance {
    package func typeNode<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> Node? {
        return try typeReference.node(in: machO)
    }
    
    package func typeNode() throws -> Node? {
        return try typeReference.node()
    }

    package func protocolNode<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> Node? {
        switch `protocol` {
        case .symbol(let symbol):
            return try MetadataReader.demangleType(for: symbol, in: machO)
        case .element(let element):
            return try MetadataReader.demangleContext(for: .protocol(element), in: machO)
        case .none:
            return nil
        }
    }
    
    package func protocolNode() throws -> Node? {
        switch `protocol` {
        case .symbol(let symbol):
            return try MetadataReader.demangleType(for: symbol)
        case .element(let element):
            return try MetadataReader.demangleContext(for: .protocol(element))
        case .none:
            return nil
        }
    }
}
