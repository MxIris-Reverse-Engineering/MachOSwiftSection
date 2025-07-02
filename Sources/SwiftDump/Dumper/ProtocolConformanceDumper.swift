import Foundation
import MachOKit
import MachOSwiftSection
import MachOMacro
import MachOFoundation
import Semantic
import Demangle
import Utilities
import OrderedCollections

struct ProtocolConformanceDumper: ConformedDumper {
    let protocolConformance: ProtocolConformance

    let options: DemangleOptions

    let machOFile: MachOFile

    var typeNameOptions: DemangleOptions { .interfaceType }

    var body: SemanticString {
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
                try conditionalRequirement.dump(using: options, in: machOFile)
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

                    if let symbols = try resilientWitness.implementationSymbols(in: machOFile), let validNode = try validNode(for: symbols, in: machOFile, typeName: typeNameString, visitedNode: visitedNodes) {
                        _ = visitedNodes.append(validNode)
                        validNode.printSemantic(using: options)
                    } else if let requirement = try resilientWitness.requirement(in: machOFile) {
                        switch requirement {
                        case .symbol(let symbol):
                            try MetadataReader.demangleSymbol(for: symbol, in: machOFile)?.printSemantic(using: options)
                        case .element(let element):
                            if let symbols = try Symbols.resolve(from: element.offset, in: machOFile), let validNode = try validNode(for: symbols, in: machOFile, typeName: typeNameString, visitedNode: visitedNodes) {
                                _ = visitedNodes.append(validNode)
                                validNode.printSemantic(using: options)
                            } else if let defaultImplementationSymbols = try element.defaultImplementationSymbols(in: machOFile), let validNode = try validNode(for: defaultImplementationSymbols, in: machOFile, typeName: typeNameString, visitedNode: visitedNodes) {
                                _ = visitedNodes.append(validNode)
                                validNode.printSemantic(using: options)
                            } else if !element.defaultImplementation.isNull {
                                FunctionDeclaration(addressString(of: element.defaultImplementation.resolveDirectOffset(from: element.offset(of: \.defaultImplementation)), in: machOFile).insertSubFunctionPrefix)
                            } else if !resilientWitness.implementation.isNull {
                                FunctionDeclaration(addressString(of: resilientWitness.implementation.resolveDirectOffset(from: resilientWitness.offset(of: \.implementation)), in: machOFile).insertSubFunctionPrefix)
                            } else {
                                Error("Symbol not found")
                            }
                        }
                    } else if !resilientWitness.implementation.isNull {
                        FunctionDeclaration(addressString(of: resilientWitness.implementation.resolveDirectOffset(from: resilientWitness.offset(of: \.implementation)), in: machOFile).insertSubFunctionPrefix)
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
    var typeName: SemanticString {
        get throws {
            switch protocolConformance.typeReference {
            case .directTypeDescriptor(let descriptor):
                try descriptor?.dumpName(using: typeNameOptions, in: machOFile).replacingTypeNameOrOtherToTypeDeclaration()
            case .indirectTypeDescriptor(let descriptor):
                switch descriptor {
                case .symbol(let unsolvedSymbol):
                    try MetadataReader.demangleType(for: unsolvedSymbol, in: machOFile)?.printSemantic(using: typeNameOptions).replacingTypeNameOrOtherToTypeDeclaration()
                case .element(let element):
                    try element.dumpName(using: typeNameOptions, in: machOFile).replacingTypeNameOrOtherToTypeDeclaration()
                case nil:
                    Standard("")
                }
            case .directObjCClassName(let objcClassName):
                TypeDeclaration(kind: .class, objcClassName.valueOrEmpty)
            case .indirectObjCClass(let objcClass):
                switch objcClass {
                case .symbol(let unsolvedSymbol):
                    try MetadataReader.demangleType(for: unsolvedSymbol, in: machOFile)?.printSemantic(using: typeNameOptions).replacingTypeNameOrOtherToTypeDeclaration()
                case .element(let element):
                    try MetadataReader.demangleContext(for: .type(.class(element.descriptor.resolve(in: machOFile))), in: machOFile).printSemantic(using: typeNameOptions).replacingTypeNameOrOtherToTypeDeclaration()
                case nil:
                    Standard("")
                }
            }
        }
    }

    @SemanticStringBuilder
    var protocolName: SemanticString {
        get throws {
            switch protocolConformance.`protocol` {
            case .symbol(let unsolvedSymbol):
                try MetadataReader.demangleType(for: unsolvedSymbol, in: machOFile)?.printSemantic(using: options)
            case .element(let element):
                try MetadataReader.demangleContext(for: .protocol(element), in: machOFile).printSemantic(using: options)
            case .none:
                Standard("")
            }
        }
    }

    private func validNode(for symbols: Symbols, in machOFile: MachOFile, typeName: String, visitedNode: borrowing OrderedSet<Node> = []) throws -> Node? {
        for symbol in symbols {
            if let node = try? MetadataReader.demangleSymbol(for: symbol, in: machOFile), let protocolConformanceNode = node.preorder().first(where: { $0.kind == .protocolConformance }), let symbolTypeName = protocolConformanceNode.children.at(0)?.print(using: .interfaceType), symbolTypeName == typeName {
                return node
            }
        }
        return nil
    }
}
