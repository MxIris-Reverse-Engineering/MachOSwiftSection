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
    @MachOImageGenerator
    public func dumpName(using options: DemangleOptions, in machOFile: MachOFile) throws -> SemanticString {
        try MetadataReader.demangleContext(for: .protocol(descriptor), in: machOFile).printSemantic(using: options).replacingTypeNameOrOtherToTypeDeclaration()
    }

    @MachOImageGenerator
    @SemanticStringBuilder
    public func dump(using options: DemangleOptions, in machOFile: MachOFile) throws -> SemanticString {
        Keyword(.protocol)

        Space()

        try dumpName(using: options, in: machOFile)

        if numberOfRequirementsInSignature > 0 {
            Space()
            Keyword(.where)
            Space()

            for (offset, requirement) in requirementInSignatures.offsetEnumerated() {
                try requirement.dump(using: options, in: machOFile)
                if !offset.isEnd {
                    Standard(",")
                    Space()
                }
            }
        }
        Space()
        Standard("{")

        let associatedTypes = try descriptor.associatedTypes(in: machOFile)

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
            if let symbols = try Symbols.resolve(from: requirement.offset, in: machOFile), let validNode = try validNode(for: symbols, in: machOFile) {
                validNode.printSemantic(using: options)
            } else {
                InlineComment("[Stripped Symbol]")
            }
            
            if let symbols = try requirement.defaultImplementationSymbols(in: machOFile), let defaultImplementation = try validNode(for: symbols, in: machOFile, visitedNode: defaultImplementations) {
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
    
    @MachOImageGenerator
    private func validNode(for symbols: Symbols, in machOFile: MachOFile, visitedNode: borrowing OrderedSet<Node> = []) throws -> Node? {
        for symbol in symbols {
            if let node = try? MetadataReader.demangleSymbol(for: symbol, in: machOFile), let protocolNode = node.first(where: { $0.kind == .protocol }), protocolNode.print(using: .interface) == (try dumpName(using: .interfaceType, in: machOFile)).string, !visitedNode.contains(node) {
                return node
            }
        }
        return nil
    }
}
