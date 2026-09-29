import Demangling
import MachOSwiftSection
import SwiftDeclaration
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection

/// The layout a `@_rawLayout` struct records outside its field descriptor.
///
/// Only the `like:` spelling leaves a field record (the artificial
/// `_rawLayout` of Swift 6.4). `@_rawLayout(size:alignment:)` and a
/// non-generic `@_rawLayout(likeArrayOf:count:)` leave nothing there — but
/// every fixed-size raw-layout struct gets a `__swift5_builtin` descriptor
/// (IRGen emits one for `@_alignment` and `@_rawLayout` alike, so remote
/// mirrors can treat the type as opaque), and that descriptor is where the
/// interface recovers `@_rawLayout(size:alignment:)` from. A generic
/// `likeArrayOf:` struct has neither record and prints no attribute: its
/// size depends on the arguments and the binary records nothing about it.
struct RawLayoutBuiltinStorage: Sendable, Hashable {
    let size: Int
    let alignment: Int
}

extension SwiftDeclarationPrinter {
    /// The recorded raw-layout storage of `typeDefinition`, or `nil` when
    /// the definition is not a fixed-size raw-layout struct: it must be a
    /// non-generic struct with no field records at all (a stored property
    /// rules `@_rawLayout` out, and the `like:` spelling is answered by its
    /// artificial record instead) whose `__swift5_builtin` descriptor records
    /// a non-zero size — an `@_alignment` empty struct records zero.
    func rawLayoutBuiltinStorage(of typeDefinition: TypeDefinition) -> RawLayoutBuiltinStorage? {
        guard case .struct(let structDescriptor) = typeDefinition.typeContextDescriptorWrapper,
              !structDescriptor.flags.isGeneric,
              typeDefinition.fields.isEmpty
        else { return nil }
        return rawLayoutBuiltinStorageByTypeName()[typeDefinition.typeName]
    }

    /// Every plain (non-instantiated) struct reference in the image's
    /// `__swift5_builtin` section with a non-zero recorded size, keyed the way
    /// the definitions are (`TypeName` equality is structural on the node, so
    /// the descriptor's symbolic reference and the indexer's name meet). A
    /// missing section is the normal state of most images and yields an
    /// empty map; so does any descriptor whose type reference does not
    /// demangle.
    func computeRawLayoutBuiltinStorageByTypeName() -> [SwiftDeclaration.TypeName: RawLayoutBuiltinStorage] {
        guard let builtinTypeDescriptors = try? machO.swift.builtinTypeDescriptors else { return [:] }
        var storageByTypeName: [SwiftDeclaration.TypeName: RawLayoutBuiltinStorage] = [:]
        for descriptor in builtinTypeDescriptors {
            guard descriptor.layout.size > 0,
                  let mangledTypeName = try? descriptor.typeName(in: machO),
                  let typeNode = try? SymbolicDemangler.demangleType(for: mangledTypeName, in: machO),
                  typeNode.kind == .type,
                  typeNode.firstChild?.kind == .structure
            else { continue }
            // `kind` takes no part in `TypeName` equality; the node is interned
            // through the shared cache, never with a bare `NodeReference(interning:)`.
            let typeName = SwiftDeclaration.TypeName(node: InternedNodeReferenceCache.shared.reference(interning: typeNode, in: machO), kind: .struct)
            if storageByTypeName[typeName] == nil {
                storageByTypeName[typeName] = RawLayoutBuiltinStorage(size: Int(descriptor.layout.size), alignment: descriptor.alignment)
            }
        }
        return storageByTypeName
    }
}
