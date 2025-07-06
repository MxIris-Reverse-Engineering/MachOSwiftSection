import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Demangle
import Utilities
import OrderedCollections

package struct ProtocolConformanceDumper<MachO: MachOSwiftSectionRepresentableWithCache>: ConformedDumper {
    let protocolConformance: ProtocolConformance

    let options: DemangleOptions

    let machO: MachO

    var typeNameOptions: DemangleOptions { .interfaceType }

    package var body: SemanticString {
        get throws {
            Keyword(.extension)

            Space()

            let typeName = try self.typeName

            let typeNameString = typeName.string

            typeName

            Standard(":")

            Space()

            try protocolName

            if !protocolConformance.conditionalRequirements.isEmpty {
                Space()
                Keyword(.where)
                Space()
            }

            for conditionalRequirement in protocolConformance.conditionalRequirements {
                try conditionalRequirement.dump(using: options, in: machO)
            }

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

                    if let symbols = try resilientWitness.implementationSymbols(in: machO), let validNode = try validNode(for: symbols, typeName: typeNameString, visitedNode: visitedNodes) {
                        _ = visitedNodes.append(validNode)
                        validNode.printSemantic(using: options)
                    } else if let requirement = try resilientWitness.requirement(in: machO) {
                        switch requirement {
                        case .symbol(let symbol):
                            try MetadataReader.demangleSymbol(for: symbol, in: machO)?.printSemantic(using: options)
                        case .element(let element):
                            if let symbols = try Symbols.resolve(from: element.offset, in: machO), let validNode = try validNode(for: symbols, typeName: typeNameString, visitedNode: visitedNodes) {
                                _ = visitedNodes.append(validNode)
                                validNode.printSemantic(using: options)
                            } else if let defaultImplementationSymbols = try element.defaultImplementationSymbols(in: machO), let validNode = try validNode(for: defaultImplementationSymbols, typeName: typeNameString, visitedNode: visitedNodes) {
                                _ = visitedNodes.append(validNode)
                                validNode.printSemantic(using: options)
                            } else if !element.defaultImplementation.isNull {
                                FunctionDeclaration(addressString(of: element.defaultImplementation.resolveDirectOffset(from: element.offset(of: \.defaultImplementation)), in: machO).insertSubFunctionPrefix)
                            } else if !resilientWitness.implementation.isNull {
                                FunctionDeclaration(addressString(of: resilientWitness.implementation.resolveDirectOffset(from: resilientWitness.offset(of: \.implementation)), in: machO).insertSubFunctionPrefix)
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
            case .symbol(let unsolvedSymbol):
                try MetadataReader.demangleType(for: unsolvedSymbol, in: machO)?.printSemantic(using: options)
            case .element(let element):
                try MetadataReader.demangleContext(for: .protocol(element), in: machO).printSemantic(using: options)
            case .none:
                Standard("")
            }
        }
    }

    private func validNode(for symbols: Symbols, typeName: String, visitedNode: borrowing OrderedSet<Node> = []) throws -> Node? {
        for symbol in symbols {
            if let node = try? MetadataReader.demangleSymbol(for: symbol, in: machO), let protocolConformanceNode = node.preorder().first(where: { $0.kind == .protocolConformance }), let symbolTypeName = protocolConformanceNode.children.at(0)?.print(using: .interfaceType), symbolTypeName == typeName || PrimitiveTypeMappingCache.shared.entry(in: machO)?.primitiveType(for: typeName) == symbolTypeName {
                return node
            }
        }
        return nil
    }
}

extension ProtocolConformance: ConformedDumpable {
    public func dumpTypeName<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try ProtocolConformanceDumper(protocolConformance: self, options: options, machO: machO).typeName
    }

    public func dumpProtocolName<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try ProtocolConformanceDumper(protocolConformance: self, options: options, machO: machO).protocolName
    }

    public func dump<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try ProtocolConformanceDumper(protocolConformance: self, options: options, machO: machO).body
    }
}
