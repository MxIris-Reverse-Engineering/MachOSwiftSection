@_spi(Internals) import Demangling
import Dependencies
import MachOSwiftSection
import SwiftDeclarationRendering
@_spi(Internals) import MachOSymbols

/// Wrapped-property recovery, the last step of `TypeDefinition.index(in:)`.
///
/// For every stored field `_x` whose type is a property wrapper, the
/// definition gains a `WrappedPropertyDefinition` (see that type for what
/// it carries). A field is a wrapper's storage when its nominal type has
/// `wrappedValue` accessors: first looked for in this image's own symbol
/// index (which also knows an internal wrapper), then in the export tries
/// the image's `PropertyWrapperTypeCatalog` can reach (a wrapper from
/// another image). A field whose type is not a wrapper — a hand-written
/// `_manual` behind a computed `manual` — is left alone: `Int` has no
/// `wrappedValue`.
extension TypeDefinition {
    package func recoverWrappedProperties(in machO: some MachOSwiftSectionRepresentableWithCache) {
        @Dependency(\.symbolIndexStore)
        var symbolIndexStore
        let catalog = PropertyWrapperTypeCatalogStore.shared.catalog(for: machO)
        var recovered: [WrappedPropertyDefinition] = []
        for field in fields where !field.flags.contains(.isArtificial) && field.name.hasPrefix("_") && field.name.count > 1 {
            let propertyName = String(field.name.dropFirst())
            let fieldTypeNode = field.typeNode.materialize()
            guard let wrapperNominalTypeNode = WrappedPropertyRecovery.nominalTypeNode(ofFieldType: fieldTypeNode) else { continue }
            let wrapperTypeName = TypeName(
                node: InternedNodeReferenceCache.shared.reference(interning: wrapperNominalTypeNode, in: machO),
                kind: wrapperNominalTypeNode.typeKind ?? .struct
            )
            let ownImageEvidence = WrappedPropertyRecovery.evidence(
                fromWrappedValueSymbols: symbolIndexStore.memberSymbols(
                    of: .variable(inExtension: false, isStatic: false, isStorage: false),
                    .variable(inExtension: false, isStatic: false, isStorage: true),
                    .variable(inExtension: true, isStatic: false, isStorage: false),
                    for: wrapperTypeName.name,
                    node: wrapperTypeName.node,
                    in: machO
                )
            )
            guard let evidence = ownImageEvidence ?? catalog.evidence(forWrapperCandidate: wrapperNominalTypeNode) else { continue }

            let declaredMember = variables.first { $0.name == propertyName }
            let origin: WrappedPropertyDefinition.Origin
            let declaredTypeNode: Node?
            if let declaredMember {
                origin = .declaredMember
                declaredTypeNode = WrappedPropertyRecovery.declaredTypeNode(of: declaredMember)
            } else {
                // The accessors are stripped: the declaration has to be
                // rebuilt from the wrapper's own `wrappedValue` type with the
                // field's generic arguments substituted. A wrapper whose
                // `wrappedValue` type the substitution cannot express is not
                // guessed at; `_x` then stays a stored field.
                guard let wrappedValueTypeNode = evidence.wrappedValueTypeNode,
                      let substitutedTypeNode = WrappedPropertyRecovery.substitutingGenericArguments(ofBoundType: fieldTypeNode, into: wrappedValueTypeNode)
                else { continue }
                origin = .synthesized(
                    declaredTypeNode: InternedNodeReferenceCache.shared.reference(interning: substitutedTypeNode, in: machO),
                    hasSetter: evidence.hasSetter
                )
                declaredTypeNode = substitutedTypeNode
            }
            let attributeTypeNode = WrappedPropertyRecovery.attributeTypeNode(
                fieldTypeNode: fieldTypeNode,
                wrapperNominalTypeNode: wrapperNominalTypeNode,
                wrappedPropertyTypeNode: declaredTypeNode
            )
            recovered.append(WrappedPropertyDefinition(
                name: propertyName,
                backingFieldName: field.name,
                projectionName: "$" + propertyName,
                attributeTypeNode: InternedNodeReferenceCache.shared.reference(interning: attributeTypeNode, in: machO),
                origin: origin
            ))
        }
        wrappedProperties = recovered
    }
}
