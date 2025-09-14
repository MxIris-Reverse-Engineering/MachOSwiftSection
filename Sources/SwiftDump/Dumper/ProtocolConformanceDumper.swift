import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Demangle
import Utilities
import OrderedCollections

package struct ProtocolConformanceDumper<MachO: MachOSwiftSectionRepresentableWithCache>: ConformedDumper {
    private let protocolConformance: ProtocolConformance

    private let configuration: DumperConfiguration

    private let machO: MachO

    private var typeNameOptions: DemangleOptions { .interfaceType }

    package init(_ dumped: ProtocolConformance, using configuration: DumperConfiguration, in machO: MachO) {
        self.protocolConformance = dumped
        self.configuration = configuration
        self.machO = machO
    }

    private var demangleResolver: DemangleResolver {
        configuration.demangleResolver
    }

    package var declaration: SemanticString {
        get throws {
            Keyword(.extension)

            Space()

            try typeName

            Standard(":")

            Space()

            try protocolName

            if !protocolConformance.conditionalRequirements.isEmpty {
                Space()
                Keyword(.where)
                Space()
            }

            for conditionalRequirement in protocolConformance.conditionalRequirements {
                try conditionalRequirement.dump(resolver: demangleResolver, in: machO)
            }
        }
    }

    package var body: SemanticString {
        get throws {
            try declaration

            let typeNameString = try typeName.string

            if protocolConformance.resilientWitnesses.isEmpty {
                Space()
                Standard("{}")
            } else {
                Space()
                Standard("{")

                var visitedNodes: OrderedSet<Node> = []

                for resilientWitness in protocolConformance.resilientWitnesses {
                    BreakLine()

                    Indent(level: 1)

                    if let symbols = try resilientWitness.implementationSymbols(in: machO), let node = try _node(for: symbols, typeName: typeNameString, visitedNodes: visitedNodes) {
                        _ = visitedNodes.append(node)
                        try demangleResolver.resolve(for: node)
                    } else if let requirement = try resilientWitness.requirement(in: machO) {
                        switch requirement {
                        case .symbol(let symbol):
                            try MetadataReader.demangleSymbol(for: symbol, in: machO).map { try demangleResolver.resolve(for: $0) }
                        case .element(let element):
                            if let symbols = try Symbols.resolve(from: element.offset, in: machO), let node = try _node(for: symbols, typeName: typeNameString, visitedNodes: visitedNodes) {
                                _ = visitedNodes.append(node)
                                try demangleResolver.resolve(for: node)
                            } else if let defaultImplementationSymbols = try element.defaultImplementationSymbols(in: machO), let node = try _node(for: defaultImplementationSymbols, typeName: typeNameString, visitedNodes: visitedNodes) {
                                _ = visitedNodes.append(node)
                                try demangleResolver.resolve(for: node)
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
        get throws {
            switch protocolConformance.typeReference {
            case .directTypeDescriptor(let descriptor):
                try descriptor?.dumpName(using: typeNameOptions, in: machO).replacingTypeNameOrOtherToTypeDeclaration()
            case .indirectTypeDescriptor(let descriptor):
                switch descriptor {
                case .symbol(let unsolvedSymbol):
                    try MetadataReader.demangleType(for: unsolvedSymbol, in: machO)?.printSemantic(using: typeNameOptions).replacingTypeNameOrOtherToTypeDeclaration()
                case .element(let element):
                    try element.dumpName(using: typeNameOptions, in: machO).replacingTypeNameOrOtherToTypeDeclaration()
                case nil:
                    Standard("")
                }
            case .directObjCClassName(let objcClassName):
                TypeDeclaration(kind: .class, objcClassName.valueOrEmpty)
            case .indirectObjCClass(let objcClass):
                switch objcClass {
                case .symbol(let unsolvedSymbol):
                    try MetadataReader.demangleType(for: unsolvedSymbol, in: machO)?.printSemantic(using: typeNameOptions).replacingTypeNameOrOtherToTypeDeclaration()
                case .element(let element):
                    try MetadataReader.demangleContext(for: .type(.class(element.descriptor.resolve(in: machO))), in: machO).printSemantic(using: typeNameOptions).replacingTypeNameOrOtherToTypeDeclaration()
                case nil:
                    Standard("")
                }
            }
        }
    }

    @SemanticStringBuilder
    package var protocolName: SemanticString {
        get throws {
            switch protocolConformance.`protocol` {
            case .symbol(let symbol):
                try MetadataReader.demangleSymbol(for: symbol, in: machO)?.first(of: .type).map { try demangleResolver.resolve(for: $0) }
            case .element(let element):
                try demangleResolver.resolve(for: MetadataReader.demangleContext(for: .protocol(element), in: machO))
            case .none:
                Standard("")
            }
        }
    }

    private func _node(for symbols: Symbols, typeName: String, visitedNodes: borrowing OrderedSet<Node> = []) throws -> Node? {
        for symbol in symbols {
            if let node = try? MetadataReader.demangleSymbol(for: symbol, in: machO), let protocolConformanceNode = node.preorder().first(where: { $0.kind == .protocolConformance }), let symbolTypeName = protocolConformanceNode.children.at(0)?.print(using: .interfaceType), symbolTypeName == typeName || PrimitiveTypeMappingCache.shared.entry(in: machO)?.primitiveType(for: typeName) == symbolTypeName, !visitedNodes.contains(node) {
                return node
            }
        }
        return nil
    }
}
