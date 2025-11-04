import MachOKit
import MachOSwiftSection
import Semantic
import Demangling

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
}
