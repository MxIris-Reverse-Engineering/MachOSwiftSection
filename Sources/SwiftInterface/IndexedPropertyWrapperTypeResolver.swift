import Demangling
import MachOFoundation
@_spi(Internals) import MachOSymbols
import MachOSwiftSection
import SwiftAttributeInference
import SwiftDeclaration
@_spi(Support) import SwiftIndexing
@_spi(Support) import SwiftPrinting

/// Answers the printer's "is this type a property wrapper" question from the
/// indexer's own type definitions and the attribute inferrer, so the
/// interface can leave out the `_x` / `$x` members the compiler synthesizes
/// for a wrapped property. Only a wrapper defined in the image being printed
/// can be recognized (that is where the `wrappedValue` evidence lives); a
/// wrapper from another module answers `false` and its synthesized members
/// keep rendering — an honest "unknown", not a guess.
struct IndexedPropertyWrapperTypeResolver<MachO: MachOSwiftSectionRepresentableWithCache>: PropertyWrapperTypeResolving {
    let indexer: SwiftDeclarationIndexer<MachO>
    let machO: MachO

    func isPropertyWrapperType(_ nominalTypeNode: Node) -> Bool {
        // `kind` takes no part in `TypeName` equality, so any value serves
        // the lookup; the node is interned through the shared cache, never
        // with a bare `NodeReference(interning:)`.
        let typeName = TypeName(node: InternedNodeReferenceCache.shared.reference(interning: nominalTypeNode, in: machO), kind: .struct)
        guard let definition = indexer.allTypeDefinitions[typeName], definition.isIndexed else { return false }
        return TypeAttributeInferrer().infer(for: definition).contains(.propertyWrapper)
    }
}
