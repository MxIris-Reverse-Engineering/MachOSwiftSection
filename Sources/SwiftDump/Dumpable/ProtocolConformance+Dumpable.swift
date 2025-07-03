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
    @SemanticStringBuilder
    public func dumpTypeName<MachO: MachORepresentableWithCache & MachOReadable>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        switch typeReference {
        case .directTypeDescriptor(let descriptor):
            try descriptor?.dumpName(using: options, in: machO).replacingTypeNameOrOtherToTypeDeclaration()
        case .indirectTypeDescriptor(let descriptor):
            switch descriptor {
            case .symbol(let unsolvedSymbol):
                try MetadataReader.demangleType(for: unsolvedSymbol, in: machO)?.printSemantic(using: options).replacingTypeNameOrOtherToTypeDeclaration()
            case .element(let element):
                try element.dumpName(using: options, in: machO).replacingTypeNameOrOtherToTypeDeclaration()
            case nil:
                Standard("")
            }
        case .directObjCClassName(let objcClassName):
            TypeDeclaration(kind: .class, objcClassName.valueOrEmpty)
        case .indirectObjCClass(let objcClass):
            switch objcClass {
            case .symbol(let unsolvedSymbol):
                try MetadataReader.demangleType(for: unsolvedSymbol, in: machO)?.printSemantic(using: options).replacingTypeNameOrOtherToTypeDeclaration()
            case .element(let element):
                try MetadataReader.demangleContext(for: .type(.class(element.descriptor.resolve(in: machO))), in: machO).printSemantic(using: options).replacingTypeNameOrOtherToTypeDeclaration()
            case nil:
                Standard("")
            }
        }
    }

    @SemanticStringBuilder
    public func dumpProtocolName<MachO: MachORepresentableWithCache & MachOReadable>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        switch `protocol` {
        case .symbol(let unsolvedSymbol):
            try MetadataReader.demangleType(for: unsolvedSymbol, in: machO)?.printSemantic(using: options)
        case .element(let element):
            try MetadataReader.demangleContext(for: .protocol(element), in: machO).printSemantic(using: options)
        case .none:
            Standard("")
        }
    }

    @SemanticStringBuilder
    public func dump<MachO: MachORepresentableWithCache & MachOReadable>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        Keyword(.extension)

        Space()

        let typeName = try dumpTypeName(using: options, in: machO)

        typeName

        let interfaceTypeName = try dumpTypeName(using: .interfaceType, in: machO).string

        Standard(":")

        Space()

        try dumpProtocolName(using: options, in: machO)

        if !conditionalRequirements.isEmpty {
            Space()
            Keyword(.where)
            Space()
        }

        for conditionalRequirement in conditionalRequirements {
            try conditionalRequirement.dump(using: options, in: machO)
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

                if let symbols = try resilientWitness.implementationSymbols(in: machO), let validNode = try validNode(for: symbols, in: machO, typeName: interfaceTypeName, visitedNode: visitedNodes) {
                    _ = visitedNodes.append(validNode)
                    validNode.printSemantic(using: options)
                } else if let requirement = try resilientWitness.requirement(in: machO) {
                    switch requirement {
                    case .symbol(let symbol):
                        try MetadataReader.demangleSymbol(for: symbol, in: machO)?.printSemantic(using: options)
                    case .element(let element):
                        if let symbols = try Symbols.resolve(from: element.offset, in: machO), let validNode = try validNode(for: symbols, in: machO, typeName: interfaceTypeName, visitedNode: visitedNodes) {
                            _ = visitedNodes.append(validNode)
                            validNode.printSemantic(using: options)
                        } else if let defaultImplementationSymbols = try element.defaultImplementationSymbols(in: machO), let validNode = try validNode(for: defaultImplementationSymbols, in: machO, typeName: interfaceTypeName, visitedNode: visitedNodes) {
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

    private func validNode<MachO: MachORepresentableWithCache & MachOReadable>(for symbols: Symbols, in machO: MachO, typeName: String, visitedNode: borrowing OrderedSet<Node> = []) throws -> Node? {
        for symbol in symbols {
            if let node = try? MetadataReader.demangleSymbol(for: symbol, in: machO), let protocolConformanceNode = node.preorder().first(where: { $0.kind == .protocolConformance }), let symbolTypeName = protocolConformanceNode.children.at(0)?.print(using: .interfaceType), symbolTypeName == typeName {
                return node
            }
        }
        return nil
    }
}


