import Demangling
import MachOSwiftSection
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection
import Semantic
extension FieldRecord {
    package func demangledTypeNode(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> Node {
        try SymbolicDemangler.demangleType(for: mangledTypeName(in: machO.context), in: machO)
    }

    package func demangledTypeName(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> SemanticString {
        try demangledTypeNode(in: machO).printSemantic(using: .interfaceTypeBuilderOnly)
    }
    
    package func demangledTypeNode() throws -> Node {
        try SymbolicDemangler.demangleType(for: mangledTypeName(in: .inProcess))
    }

    package func demangledTypeName() throws -> SemanticString {
        try demangledTypeNode().printSemantic(using: .interfaceTypeBuilderOnly)
    }
}
