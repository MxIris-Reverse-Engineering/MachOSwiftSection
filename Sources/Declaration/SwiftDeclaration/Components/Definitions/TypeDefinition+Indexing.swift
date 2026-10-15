import Demangling
import Dependencies
import MachOSwiftSection
import SwiftDeclarationRendering
import SwiftStdlibToolbox
import SwiftThunkAnalysis
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection

extension TypeDefinition: OnceIndexedDefinition {
    /// Fills the definition from the image: fields, members, the facts that
    /// are only recoverable by cross-referencing several symbol kinds, and
    /// the member order. Idempotent — a second call on an indexed definition
    /// returns immediately — and safe to call from several tasks at once:
    /// the first runs the pass, the others wait for it (`DefinitionIndexing`).
    package func index(in machO: some MachOSwiftSectionRepresentableWithCache) throws {
        try DefinitionIndexing.index(self) {
            try runIndexingPass(in: machO)
        }
    }

    /// The pass `index(in:)` runs once. Synchronous on purpose, and it must
    /// never index another definition: `DefinitionIndexing` blocks the
    /// callers that arrive while it runs.
    ///
    /// The step order below is load-bearing and each step documents what it
    /// depends on; the two that are easiest to break are `final` recovery
    /// (needs the `@objc` evidence `applyThunkAttributes` attaches, and must
    /// precede `orderedMembers`, which copies the member values) and
    /// wrapped-property recovery (needs both the folded fields and the member
    /// variables).
    private func runIndexingPass(in machO: some MachOSwiftSectionRepresentableWithCache) throws {
        @Dependency(\.symbolIndexStore)
        var symbolIndexStore

        var indexedFields = try indexedFieldDefinitions(in: machO)
        let fieldNames = Set(indexedFields.map(\.name))
        let dispatchLookups = try classDispatchLookups(in: machO)

        let storedPropertyAccessorsByFieldName = indexMembers(
            fieldNames: fieldNames,
            dispatchLookups: dispatchLookups,
            symbolIndexStore: symbolIndexStore,
            in: machO
        )
        foldStoredPropertyAccessors(storedPropertyAccessorsByFieldName, into: &indexedFields)

        // Cross-reference @objc and @nonobjc thunk symbols with built definitions
        applyThunkAttributes(symbolIndexStore: symbolIndexStore, typeName: typeName.name, typeNode: typeName.node, in: machO)

        // The ObjC runtime name the source chose, if it chose one (evolution
        // proposal `objc-custom-class-name`): no symbol carries it, the class
        // metadata keyed by this descriptor does.
        if case .class(let classDescriptor) = typeContextDescriptorWrapper {
            customObjCClassName = SwiftClassObjectIndex.shared.customObjCClassName(forClassDescriptorOffset: classDescriptor.offset, in: machO)
        }

        // The class's own ObjC method table tied to its members (evolution
        // proposals `objc-ancestor-override-recovery` and
        // `objc-member-selector-recovery`): `@objc` on every member the table
        // knows — the thunk-symbol evidence above is stripped from OS
        // frameworks, and the `final` recovery below excludes `@objc`
        // members without a descriptor as `@objc dynamic`, so this MUST run
        // before it — plus `override` where an ancestor implements the
        // selector and the explicit selector where the compiler would have
        // derived another.
        applyObjCMembers(in: machO)

        if dispatchLookups.canRecoverFinalMembers {
            recoverFinalMembers(fields: &indexedFields, symbolIndexStore: symbolIndexStore, in: machO)
        }
        // Assigned only here, once the accessor groups have been folded in and
        // the `final` verdicts recorded.
        fields = indexedFields

        // P1-10: drop body-side copies of auto-synthesized Equatable / Hashable /
        // Codable / CaseIterable / RawRepresentable / CodingKey members. The
        // canonical copy remains on the conformance extension, avoiding the
        // "same member printed twice with different addresses" duplication.
        // This must run *after* applyThunkAttributes so that any user-declared
        // override flagged with an attribute is dropped alongside its body
        // entry; the extension copy (which carries the same attribute after
        // its own indexing pass) is the surviving one.
        deduplicateSynthesizedProtocolMembers()

        // Build ordered members list
        let allMembers = OrderedMember.allMembers(from: self)
        if case .class = typeContextDescriptorWrapper {
            orderedMembers = OrderedMember.classOrdered(allMembers)
        } else {
            orderedMembers = OrderedMember.offsetOrdered(allMembers)
        }

        // Needs the fields and the member variables above: which `_x` is a
        // wrapper's storage, and whether `x` still has accessors of its own.
        recoverWrappedProperties(in: machO)
    }

    /// The type's stored fields, read from its field descriptor. Carries no
    /// accessor facts yet — `foldStoredPropertyAccessors(_:into:)` adds those
    /// once the members are built.
    func indexedFieldDefinitions(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> [FieldDefinition] {
        let typeContextDescriptor = typeContextDescriptorWrapper.typeContextDescriptor
        let fieldDescriptor = try typeContextDescriptor.fieldDescriptor(in: machO.context)
        let records = try fieldDescriptor.records(in: machO.context)
        // Field type trees intern into the image's shared store
        // (`InternedNodeReferenceCache`), so common subtrees (module
        // references, stdlib types) deduplicate across the whole image —
        // the per-type builder+freeze store this replaced could only
        // deduplicate within one type.
        // A field whose type is a kind-9 accessor reference (its mangling
        // needs a runtime the deployment target predates — a `~Copyable`
        // generic, say) is read offline through the same thunk reader the
        // opaque-type path uses; the thunk's arguments are this type's own
        // generic arguments.
        let ownerGenericContext = try typeContextDescriptor.genericContext(in: machO.context)
        let accessorThunkOwnerLayout = AccessorThunkOwnerLayout(
            genericContext: ownerGenericContext,
            depthLayout: ownerGenericContext.map { GenericParameterDepthLayout.make(for: $0, ownedBy: typeContextDescriptor, in: machO.context) } ?? GenericParameterDepthLayout(parameterCountsByDepth: [])
        )
        var indexedFields: [FieldDefinition] = []
        for record in records {
            let typeNode = try record.demangledTypeNode(in: machO.context)
                .resolvingAccessorFunctionReferences(in: machO, ownerLayout: accessorThunkOwnerLayout)
            let name = try record.fieldName(in: machO.context)
            var fieldFlags = FieldFlags()
            if name.hasLazyPrefix {
                fieldFlags.insert(.isLazy)
            }
            if typeNode.contains(.weak) {
                fieldFlags.insert(.isWeak)
            }
            if typeNode.contains(.unmanaged) {
                fieldFlags.insert(.isUnownedUnsafe)
            } else if typeNode.contains(.unowned) {
                fieldFlags.insert(.isUnowned)
            }
            if record.flags.contains(.isVariadic) {
                fieldFlags.insert(.isVariable)
            }
            if record.flags.contains(.isIndirectCase) {
                fieldFlags.insert(.isIndirectCase)
            }
            if record.flags.contains(.isArtificial) {
                fieldFlags.insert(.isArtificial)
            }
            if try !record.mangledTypeName(in: machO.context).isEmpty {
                fieldFlags.insert(.hasMangledTypeName)
            }
            indexedFields.append(FieldDefinition(name: name.stripLazyPrefix, typeNode: InternedNodeReferenceCache.shared.reference(interning: typeNode, in: machO), flags: fieldFlags))
        }
        return indexedFields
    }

    /// Folds the stored-property accessor groups — suppressed from
    /// `variables` so the property still renders once, from the field
    /// descriptor — back onto their fields: the resolved method descriptors
    /// carry the dispatch facts (vtable slots, `final`), and a lazy field's
    /// getter carries the caller-facing type its storage record hides.
    func foldStoredPropertyAccessors(_ accessorsByFieldName: [String: [Accessor]], into fields: inout [FieldDefinition]) {
        for index in fields.indices {
            guard let accessors = accessorsByFieldName[fields[index].name] else { continue }
            fields[index].accessors = accessors
            if fields[index].flags.contains(.isLazy),
               let getterNode = accessors.first(where: { $0.kind == .getter })?.symbol.demangledNode,
               let accessorTypeNode = getterNode.first(of: .variable)?.children.first(of: .type) {
                fields[index].accessorTypeNode = accessorTypeNode
            }
        }
    }
}
