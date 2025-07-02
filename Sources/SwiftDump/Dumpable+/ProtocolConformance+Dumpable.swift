import Foundation
import MachOKit
import MachOSwiftSection
import MachOMacro
import MachOFoundation
import Semantic
import Demangle
import Utilities
import OrderedCollections

extension ProtocolConformance: ConformedDumpable {
    @MachOImageGenerator
    @SemanticStringBuilder
    public func dumpTypeName(using options: DemangleOptions, in machOFile: MachOFile) throws -> SemanticString {
        switch typeReference {
        case .directTypeDescriptor(let descriptor):
            try descriptor?.dumpName(using: options, in: machOFile).replacingTypeNameOrOtherToTypeDeclaration()
        case .indirectTypeDescriptor(let descriptor):
            switch descriptor {
            case .symbol(let unsolvedSymbol):
                try MetadataReader.demangleType(for: unsolvedSymbol, in: machOFile)?.printSemantic(using: options).replacingTypeNameOrOtherToTypeDeclaration()
            case .element(let element):
                try element.dumpName(using: options, in: machOFile).replacingTypeNameOrOtherToTypeDeclaration()
            case nil:
                Standard("")
            }
        case .directObjCClassName(let objcClassName):
            TypeDeclaration(kind: .class, objcClassName.valueOrEmpty)
        case .indirectObjCClass(let objcClass):
            switch objcClass {
            case .symbol(let unsolvedSymbol):
                try MetadataReader.demangleType(for: unsolvedSymbol, in: machOFile)?.printSemantic(using: options).replacingTypeNameOrOtherToTypeDeclaration()
            case .element(let element):
                try MetadataReader.demangleContext(for: .type(.class(element.descriptor.resolve(in: machOFile))), in: machOFile).printSemantic(using: options).replacingTypeNameOrOtherToTypeDeclaration()
            case nil:
                Standard("")
            }
        }
    }

    @MachOImageGenerator
    @SemanticStringBuilder
    public func dumpProtocolName(using options: DemangleOptions, in machOFile: MachOFile) throws -> SemanticString {
        switch `protocol` {
        case .symbol(let unsolvedSymbol):
            try MetadataReader.demangleType(for: unsolvedSymbol, in: machOFile)?.printSemantic(using: options)
        case .element(let element):
            try MetadataReader.demangleContext(for: .protocol(element), in: machOFile).printSemantic(using: options)
        case .none:
            Standard("")
        }
    }

    @MachOImageGenerator
    @SemanticStringBuilder
    public func dump(using options: DemangleOptions, in machOFile: MachOFile) throws -> SemanticString {
        Keyword(.extension)

        Space()

        let typeName = try dumpTypeName(using: options, in: machOFile)
        
        typeName
        
        let interfaceTypeName = try dumpTypeName(using: .interfaceType, in: machOFile).string
        
        Standard(":")

        Space()

        try dumpProtocolName(using: options, in: machOFile)

        if !conditionalRequirements.isEmpty {
            Space()
            Keyword(.where)
            Space()
        }

        for conditionalRequirement in conditionalRequirements {
            try conditionalRequirement.dump(using: options, in: machOFile)
        }

        if resilientWitnesses.isEmpty {
            Space()
            Standard("{}")
        } else {
            Space()
            Standard("{")

            var visitedNodes: OrderedSet<Node> = []
            
            for resilientWitness in resilientWitnesses {
                BreakLine()

                Indent(level: 1)

                if let symbols = try resilientWitness.implementationSymbols(in: machOFile), let validNode = try validNode(for: symbols, in: machOFile, typeName: interfaceTypeName, visitedNode: visitedNodes) {
                    _ = visitedNodes.append(validNode)
                    validNode.printSemantic(using: options)
                } else if let requirement = try resilientWitness.requirement(in: machOFile) {
                    switch requirement {
                    case .symbol(let symbol):
                        try MetadataReader.demangleSymbol(for: symbol, in: machOFile)?.printSemantic(using: options)
                    case .element(let element):
                        if let symbols = try Symbols.resolve(from: element.offset, in: machOFile), let validNode = try validNode(for: symbols, in: machOFile, typeName: interfaceTypeName, visitedNode: visitedNodes) {
                            _ = visitedNodes.append(validNode)
                            validNode.printSemantic(using: options)
                        } else if let defaultImplementationSymbols = try element.defaultImplementationSymbols(in: machOFile), let validNode = try validNode(for: defaultImplementationSymbols, in: machOFile, typeName: interfaceTypeName, visitedNode: visitedNodes) {
                            _ = visitedNodes.append(validNode)
                            validNode.printSemantic(using: options)
                        } else if !element.defaultImplementation.isNull {
                            FunctionDeclaration(addressString(of: element.defaultImplementation.resolveDirectOffset(from: element.offset(of: \.defaultImplementation)), in: machOFile).insertSubFunctionPrefix)
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
    
    @MachOImageGenerator
    private func validNode(for symbols: Symbols, in machOFile: MachOFile, typeName: String, visitedNode: borrowing OrderedSet<Node> = []) throws -> Node? {
        for symbol in symbols {
            if let node = try? MetadataReader.demangleSymbol(for: symbol, in: machOFile), let protocolConformanceNode = node.first(where: { $0.kind == .protocolConformance }), protocolConformanceNode.children.at(0)?.print(using: .interfaceType) == typeName {
                return node
            }
        }
        return nil
    }
}

extension SemanticString {
    func replacingTypeNameOrOtherToTypeDeclaration() -> SemanticString {
        replacing { 
            switch $0 {
            case .type(let type, .name):
                return .type(type, .declaration)
            case .other:
                return .type(.other, .declaration)
            default:
                return $0
            }
        }
    }
}
