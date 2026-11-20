import Demangling
import MachOSwiftSection
@_spi(Internals) import SwiftSymbols
@_spi(Internals) import SwiftInspection
import Semantic
import SwiftDeclarationRendering
extension FieldRecord {
    package func demangledTypeNode(in context: some ReadingContext) throws -> Node {
        try SymbolicDemangler.demangleType(for: mangledTypeName(in: context), in: context)
    }

    package func demangledTypeName(in context: some ReadingContext) throws -> SemanticString {
        try demangledTypeNode(in: context).printSemantic(using: .interfaceTypeBuilderOnly)
    }
}
