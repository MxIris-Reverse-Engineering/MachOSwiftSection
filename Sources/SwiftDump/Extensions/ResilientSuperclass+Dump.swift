import MachOKit
import MachOSwiftSection
import Semantic
import Demangling
@_spi(Internals) import SwiftInspection

extension ResilientSuperclass {
    package func dumpSuperclass<MachO: MachOSwiftSectionRepresentableWithCache>(resolver: DemangleResolver, for kind: TypeReferenceKind, in machO: MachO) async throws -> SemanticString? {
        switch resolver {
        case .options(let demangleOptions):
            return try dumpSuperclass(using: demangleOptions, for: kind, in: machO)
        case .builder(let builder):
            return try await dumpSuperclassNode(for: kind, in: machO).asyncMap { try await builder($0) }
        }
    }

    package func dumpSuperclass<MachO: MachOSwiftSectionRepresentableWithCache>(using options: DemangleOptions, for kind: TypeReferenceKind, in machO: MachO) throws -> SemanticString? {
        try dumpSuperclassNode(for: kind, in: machO)?.printSemantic(using: options)
    }

    package func dumpSuperclassNode<MachO: MachOSwiftSectionRepresentableWithCache>(for kind: TypeReferenceKind, in machO: MachO) throws -> Node? {
        let typeReference = TypeReference.forKind(kind, at: layout.superclass.relativeOffset)
        let resolvedTypeReference = try typeReference.resolve(at: offset(of: \.superclass), in: machO)
        return try resolvedTypeReference.node(in: machO)
    }

    package func superclassResolvedTypeReference<MachO: MachOSwiftSectionRepresentableWithCache>(for kind: TypeReferenceKind, in machO: MachO) throws -> ResolvedTypeReference {
        let typeReference = TypeReference.forKind(kind, at: layout.superclass.relativeOffset)
        return try typeReference.resolve(at: offset(of: \.superclass), in: machO)
    }
}

extension Class {
    package func superclassNode(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> Node? {
        if let superclassTypeMangledName = try descriptor.superclassTypeMangledName(in: machO) {
            return try MetadataReader.demangleType(for: superclassTypeMangledName, in: machO)
        } else if let resilientSuperclassReferenceKind = descriptor.resilientSuperclassReferenceKind, let resilientSuperclass {
            return try resilientSuperclass.dumpSuperclassNode(for: resilientSuperclassReferenceKind, in: machO)
        } else {
            return nil
        }
    }
}
