import MachOKit
import MachOSwiftSection
import Semantic
import Demangling
@_spi(Internals) import SwiftInspection

extension ResilientSuperclass {
    package func dumpSuperclass(resolver: DemangleResolver, for kind: TypeReferenceKind, in context: some ReadingContext) async throws -> SemanticString? {
        switch resolver {
        case .options(let demangleOptions):
            return try dumpSuperclass(using: demangleOptions, for: kind, in: context)
        case .builder(let builder):
            return try await dumpSuperclassNode(for: kind, in: context).asyncMap { try await builder($0) }
        }
    }

    package func dumpSuperclass(using options: DemangleOptions, for kind: TypeReferenceKind, in context: some ReadingContext) throws -> SemanticString? {
        try dumpSuperclassNode(for: kind, in: context)?.printSemantic(using: options)
    }

    package func dumpSuperclassNode(for kind: TypeReferenceKind, in context: some ReadingContext) throws -> Node? {
        let typeReference = TypeReference.forKind(kind, at: layout.superclass.relativeOffset)
        let resolvedTypeReference = try typeReference.resolve(at: offset(of: \.superclass), in: context)
        return try resolvedTypeReference.node(in: context)
    }

    package func superclassResolvedTypeReference(for kind: TypeReferenceKind, in context: some ReadingContext) throws -> ResolvedTypeReference {
        let typeReference = TypeReference.forKind(kind, at: layout.superclass.relativeOffset)
        return try typeReference.resolve(at: offset(of: \.superclass), in: context)
    }
}

extension Class {
    package func superclassNode(in context: some ReadingContext) throws -> Node? {
        if let superclassTypeMangledName = try descriptor.superclassTypeMangledName(in: context) {
            return try SymbolicDemangler.demangleType(for: superclassTypeMangledName, in: context)
        } else if let resilientSuperclassReferenceKind = descriptor.resilientSuperclassReferenceKind, let resilientSuperclass {
            return try resilientSuperclass.dumpSuperclassNode(for: resilientSuperclassReferenceKind, in: context)
        } else {
            return nil
        }
    }
}
