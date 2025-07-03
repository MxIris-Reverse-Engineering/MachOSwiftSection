import Foundation
import MachOKit
import MachOSwiftSection
import MachOMacro
import Semantic
import MachOFoundation
import Utilities
import Demangle
import OrderedCollections

extension MachOSwiftSection.`Protocol`: NamedDumpable {
    public func dumpName<MachO: MachORepresentableWithCache & MachOReadable>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        try MetadataReader.demangleContext(for: .protocol(descriptor), in: machO).printSemantic(using: options).replacingTypeNameOrOtherToTypeDeclaration()
    }

    @SemanticStringBuilder
    public func dump<MachO: MachORepresentableWithCache & MachOReadable>(using options: DemangleOptions, in machO: MachO) throws -> SemanticString {
        Keyword(.protocol)

        Space()

        try dumpName(using: options, in: machO)

        if numberOfRequirementsInSignature > 0 {
            Space()
            Keyword(.where)
            Space()

            for (offset, requirement) in requirementInSignatures.offsetEnumerated() {
                try requirement.dump(using: options, in: machO)
                if !offset.isEnd {
                    Standard(",")
                    Space()
                }
            }
        }
        Space()
        Standard("{")

        let associatedTypes = try descriptor.associatedTypes(in: machO)

        if !associatedTypes.isEmpty {
            for (offset, associatedType) in associatedTypes.offsetEnumerated() {
                BreakLine()
                Indent(level: 1)
                Keyword(.associatedtype)
                Space()
                TypeDeclaration(kind: .other, associatedType)
                if offset.isEnd {
                    BreakLine()
                }
            }
        }

        var defaultImplementations: OrderedSet<Node> = []
        
        for (offset, requirement) in requirements.offsetEnumerated() {
            BreakLine()
            Indent(level: 1)
            if let symbols = try Symbols.resolve(from: requirement.offset, in: machO), let validNode = try validNode(for: symbols, in: machO) {
                validNode.printSemantic(using: options)
            } else {
                InlineComment("[Stripped Symbol]")
            }
            
            if let symbols = try requirement.defaultImplementationSymbols(in: machO), let defaultImplementation = try validNode(for: symbols, in: machO, visitedNode: defaultImplementations) {
                _ = defaultImplementations.append(defaultImplementation)
            }
            
            if offset.isEnd {
                BreakLine()
            }
        }
        
        for (offset, defaultImplementation) in defaultImplementations.offsetEnumerated() {
         
            if offset.isStart {
                BreakLine()
                Indent(level: 1)
                InlineComment("[Default Implementation]")
            }
            
            BreakLine()
            Indent(level: 1)
            defaultImplementation.printSemantic(using: options)
            
            if offset.isEnd {
                BreakLine()
            }
        }
        Standard("}")
    }
    
    private func validNode<MachO: MachORepresentableWithCache & MachOReadable>(for symbols: Symbols, in machO: MachO, visitedNode: borrowing OrderedSet<Node> = []) throws -> Node? {
        for symbol in symbols {
            if let node = try? MetadataReader.demangleSymbol(for: symbol, in: machO), let protocolNode = node.preorder().first(where: { $0.kind == .protocol }), protocolNode.print(using: .interface) == (try dumpName(using: .interfaceType, in: machO)).string, !visitedNode.contains(node) {
                return node
            }
        }
        return nil
    }
}
