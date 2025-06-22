import MachOKit
import MachOMacro
import MachOSwiftSection
import Semantic

extension ResilientSuperclass {
    @MachOImageGenerator
    package func dumpSuperclass(using options: DemangleOptions, for kind: TypeReferenceKind, in machOFile: MachOFile) throws -> SemanticString? {
        let typeReference = TypeReference.forKind(kind, at: layout.superclass.relativeOffset)
        let resolvedTypeReference = try typeReference.resolve(at: offset(of: \.superclass), in: machOFile)
        switch resolvedTypeReference {
        case .directTypeDescriptor(let contextDescriptorWrapper):
            return try contextDescriptorWrapper?.dumpName(using: options, in: machOFile)
        case .indirectTypeDescriptor(let resolvableElement):
            switch resolvableElement {
            case .symbol(let unsolvedSymbol):
                return try MetadataReader.demangleSymbol(for: unsolvedSymbol, in: machOFile).printSemantic(using: options)
            case .element(let element):
                return try element.dumpName(using: options, in: machOFile)
            case nil:
                return nil
            }
        case .directObjCClassName(let string):
            return string.map { SemanticString(components: TypeName(kind: .class, $0)) } 
        case .indirectObjCClass(let resolvableElement):
            switch resolvableElement {
            case .symbol(let unsolvedSymbol):
                return try MetadataReader.demangleSymbol(for: unsolvedSymbol, in: machOFile).printSemantic(using: options)
            case .element(let element):
                return try MetadataReader.demangleContext(for: .type(.class(element.descriptor.resolve(in: machOFile))), in: machOFile).printSemantic(using: options)
            case nil:
                return nil
            }
        }
    }
}
