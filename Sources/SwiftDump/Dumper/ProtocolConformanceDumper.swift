import Foundation
import MachOKit
import MachOSwiftSection
import Semantic
import Demangling
import Utilities
import OrderedCollections
@_spi(Internals) import SwiftInspection
import SwiftDeclarationRendering

package struct ProtocolConformanceDumper<MachO: FieldLayoutRenderable>: ConformedDumper {
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

            try await fullTypeName

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
                if configuration.printConformancePWTAddress, let proto = dumped.protocol?.resolved {
                    Standard("{")
                    let protocolModel = try Protocol(descriptor: proto, in: machO)
                    if !protocolModel.requirements.isEmpty, let witnessTablePattern = dumped.witnessTablePattern {
                        BreakLine()
                        for (requirementIndex, requirement) in protocolModel.requirements.enumerated() {
                            if requirementIndex > 0 {
                                BreakLine()
                            }
                            let slotOffset = witnessTablePattern.offset + MemoryLayout<StoredPointer>.size * (requirementIndex + 1)
                            let requirementName = try await _requirementName(for: requirement)
                            let requirementFlags = requirement.layout.flags
                            configuration.memberAddressComment(offset: slotOffset, addressString: machO.addressString(forOffset: slotOffset), label: "Protocol Witness Table[\(requirementIndex)]")
                            configuration.indentString
                            Comment("Kind: \(requirementFlags.kind.description), isAsync: \(requirementFlags.isAsync), isInstance: \(requirementFlags.isInstance)")
                            BreakLine()
                            if let requirementName {
                                configuration.indentString
                                requirementName
                                BreakLine()
                            }
                        }
                    }
                    Standard("}")
                } else {
                    Standard("{}")
                }
            } else {
                Space()
                Standard("{")

                var visitedNodes: OrderedSet<NodeReference> = []

                for resilientWitness in dumped.resilientWitnesses {
                    BreakLine()

                    if configuration.printMemberAddress {
                        configuration.memberAddressComment(offset: resilientWitness.implementationOffset, addressString: resilientWitness.implementationAddress(in: machO))
                    }
                    
                    Indent(level: 1)

                    if let symbols = try resilientWitness.implementationSymbols(in: machO), let node = Self.demangledSymbol(for: symbols, typeName: typeNameString, visitedNodes: visitedNodes, in: machO)?.demangledNode {
                        _ = visitedNodes.append(node)
                        try await demangleResolver.resolve(for: node.materialize())
                    } else if let requirement = try resilientWitness.requirement(in: machO) {

                        switch requirement {
                        case .symbol(let symbol):
                            try await MetadataReader.demangleSymbol(for: symbol, in: machO).asyncMap { try await demangleResolver.resolve(for: $0) }
                        case .element(let element):
                            if let symbols = try await Symbols.resolve(from: element.offset, in: machO), let node = Self.demangledSymbol(for: symbols, typeName: typeNameString, visitedNodes: visitedNodes, in: machO)?.demangledNode {
                                _ = visitedNodes.append(node)
                                try await demangleResolver.resolve(for: node.materialize())
                            } else if let defaultImplementationSymbols = try element.defaultImplementationSymbols(in: machO), let node = Self.demangledSymbol(for: defaultImplementationSymbols, typeName: typeNameString, visitedNodes: visitedNodes, in: machO)?.demangledNode {
                                _ = visitedNodes.append(node)
                                try await demangleResolver.resolve(for: node.materialize())
                            } else if !element.defaultImplementation.isNull {
                                FunctionDeclaration(machO.addressString(forOffset: element.defaultImplementation.resolveDirectOffset(from: element.offset(of: \.defaultImplementation))).insertSubFunctionPrefix)
                            } else if !resilientWitness.implementation.isNull {
//                                do {
//                                try demangleResolver.resolve(for: MetadataReader.demangle(for: MangledName.resolve(from: resilientWitness.implementation.resolveDirectOffset(from: resilientWitness.offset(of: \.implementation)) - 1, in: machO), in: machO))
//                                } catch {
                                FunctionDeclaration(machO.addressString(forOffset: resilientWitness.implementation.resolveDirectOffset(from: resilientWitness.offset(of: \.implementation))).insertSubFunctionPrefix)
//                                }
                            } else {
                                Error("Symbol not found")
                            }
                        }
                    } else if !resilientWitness.implementation.isNull {
                        FunctionDeclaration(machO.addressString(forOffset: resilientWitness.implementation.resolveDirectOffset(from: resilientWitness.offset(of: \.implementation))).insertSubFunctionPrefix)
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
            try await typeName(isFull: false)
        }
    }
    
    @SemanticStringBuilder
    package var fullTypeName: SemanticString {
        get async throws {
            try await typeName(isFull: true)
        }
    }
    
    @SemanticStringBuilder
    private func typeName(isFull: Bool) async throws -> SemanticString {
        try dumped.typeNode(in: machO)?.printSemantic(using: isFull ? demangleResolver.options ?? typeNameOptions : typeNameOptions).replacingTypeNameOrOtherToTypeDeclaration()
    }

    @SemanticStringBuilder
    package var protocolName: SemanticString {
        get async throws {
            try await dumped.protocolNode(in: machO).asyncMap { try await demangleResolver.resolve(for: $0) }
        }
    }

    private func _requirementName(for requirement: ProtocolRequirement) async throws -> String? {
        guard let symbols = try await Symbols.resolve(from: requirement.offset, in: machO) else { return nil }
        for symbol in symbols {
            if let node = try? MetadataReader.demangleSymbol(for: symbol, in: machO) {
                return await node.print(using: typeNameOptions)
            }
        }
        return nil
    }
    
    package static func demangledSymbol(for symbols: Symbols, typeName: String, visitedNodes: borrowing OrderedSet<NodeReference> = [], in machO: MachO) -> DemangledSymbol? {
        for symbol in symbols {
            if let node = MetadataReader.demangleSymbolReference(for: symbol, in: machO), let targetNode = node.first(of: .protocolConformance), let symbolTypeName = targetNode.children.at(0)?.print(using: .interfaceType), symbolTypeName == typeName || PrimitiveTypeMappingCache.shared.storage(in: machO)?.primitiveType(for: typeName) == symbolTypeName, !visitedNodes.contains(node) {
                return .init(symbol: symbol, demangledNode: node)
            }
        }
        return nil
    }
}

