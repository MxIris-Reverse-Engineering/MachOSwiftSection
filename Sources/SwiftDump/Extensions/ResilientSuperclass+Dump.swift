import MachOKit
import MachOSwiftSection
import Semantic
import Demangle

extension ResilientSuperclass {
    
    package func dumpSuperclass<MachO: MachOSwiftSectionRepresentableWithCache>(resolver: DemangleResolver, for kind: TypeReferenceKind, in machO: MachO) throws -> SemanticString? {
        switch resolver {
        case .options(let demangleOptions):
            return try dumpSuperclass(using: demangleOptions, for: kind, in: machO)
        case .builder(let builder):
            return try dumpSuperclassNode(for: kind, in: machO).map { try builder($0) }
        }
    }
    
    package func dumpSuperclass<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, for kind: TypeReferenceKind, in machO: MachO) throws -> SemanticString? {
        try dumpSuperclassNode(for: kind, in: machO)?.printSemantic(using: options)
    }
    
    package func dumpSuperclassNode<MachO: MachOSwiftSectionRepresentableWithCache>(for kind: TypeReferenceKind, in machO: MachO) throws -> Node? {
        let typeReference = TypeReference.forKind(kind, at: layout.superclass.relativeOffset)
        let resolvedTypeReference = try typeReference.resolve(at: offset(of: \.superclass), in: machO)
        switch resolvedTypeReference {
        case .directTypeDescriptor(let contextDescriptorWrapper):
            return try contextDescriptorWrapper?.dumpNameNode(in: machO)
        case .indirectTypeDescriptor(let resolvableElement):
            switch resolvableElement {
            case .symbol(let unsolvedSymbol):
                return try MetadataReader.demangleSymbol(for: unsolvedSymbol, in: machO)
            case .element(let element):
                return try element.dumpNameNode(in: machO)
            case nil:
                return nil
            }
        case .directObjCClassName(let string):
            guard let string else { return nil }
            return Node(kind: .global) {
                Node(kind: .type) {
                    Node(kind: .class) {
                        Node(kind: .module, contents: .name(objcModule))
                        Node(kind: .identifier, contents: .name(string))
                    }
                }
            }
        case .indirectObjCClass(let resolvableElement):
            switch resolvableElement {
            case .symbol(let unsolvedSymbol):
                return try MetadataReader.demangleSymbol(for: unsolvedSymbol, in: machO)
            case .element(let element):
                return try MetadataReader.demangleContext(for: .type(.class(element.descriptor.resolve(in: machO))), in: machO)
            case nil:
                return nil
            }
        }
    }
    
}
