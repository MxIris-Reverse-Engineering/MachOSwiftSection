import MachOSwiftSection
@_spi(Internals) import MachOSymbols

public final class TypeDefinition: Definition {
    /// The type's context descriptor reference (evolution proposal 0002).
    /// This is the only Mach-O parse product the definition retains: the
    /// full `TypeContextWrapper` (trailing objects included) is rebuilt on
    /// demand via `materializedTypeContext(in:)` by the few operations that
    /// need it, instead of living on every definition for its lifetime.
    public let typeContextDescriptorWrapper: TypeContextDescriptorWrapper

    /// Injected at construction time. Ordinary indexing-derived definitions
    /// receive the unbound form computed from `type.typeName(in:)`;
    /// `specialize(with:in:)` derives a bound form via
    /// `boundGenericTypeName(...)` (`Box<A>` → `Box<Int>`) and feeds it to
    /// the designated init, so the property is always immutable post-init.
    public let typeName: TypeName

    /// `true` when this definition was produced via `specialize(with:in:)` —
    /// i.e. it carries a runtime-resolved `metadata` and a bound-generic
    /// `typeName`. `false` for the canonical, unspecialized definitions
    /// produced from a MachO image's section data. Always known at
    /// construction time, so callers can branch on the type kind without
    /// inspecting the optional `metadata` field.
    public let isSpecialized: Bool

    /// Whether this type's nominal type descriptor is in the image's export
    /// trie, resolved once at construction (see ``ExportStatus``). Available
    /// the moment `SwiftDeclarationIndexer.prepare()` returns — the verdict
    /// needs only the descriptor's offset and the name node, never
    /// `index(in:)`'s products — so a host listing types can annotate every
    /// row before any of them is indexed. A specialized definition inherits
    /// the value of the generic definition it was derived from: same
    /// descriptor, same fact.
    ///
    /// Resolving it queries the image's symbol index, so constructing a
    /// definition through `init(type:in:)` for an image whose index has not
    /// been built yet builds it (`SymbolIndexStore.storage(in:)` is
    /// get-or-build). Through `SwiftDeclarationIndexer.prepare()` — the
    /// normal path — the index is already up by the time definitions are
    /// constructed, which is why the whole sweep costs well under 1% of
    /// preparation.
    public let exportStatus: ExportStatus

    public package(set) weak var parent: TypeDefinition?

    /// Nested type definitions whose containing context is `self`.
    ///
    /// Semantics depend on `isSpecialized`:
    /// - **Generic / canonical definition** (`isSpecialized == false`):
    ///   populated by `SwiftDeclarationIndexer` from the MachO image's
    ///   nesting topology, holds the unbound nested types.
    /// - **Specialized definition** (`isSpecialized == true`): replaced
    ///   wholesale by `deriveNestedSpecializedTypeChildren` to hold the
    ///   *derived* specialized nested children (siblings produced from the
    ///   generic child's descriptor + the outer binding). Nested children
    ///   that the deriver cannot bind (introduce their own generic
    ///   parameters, throw on inner `specialize`, hit the depth limit, …)
    ///   are silently dropped — the field is best-effort by design.
    ///
    /// Generic and specialized definitions hold **different** `TypeDefinition`
    /// instances here; a derived nested child is never the same object as
    /// the canonical generic child living in the generic parent's
    /// `typeChildren`. The `parent` back-pointer of each entry reflects
    /// this: derived nested children point at their derived (specialized)
    /// parent, never at the generic parent.
    public package(set) var typeChildren: [TypeDefinition] = []

    public package(set) var protocolChildren: [ProtocolDefinition] = []

    public package(set) var extensions: [ExtensionDefinition] = []

    public package(set) var fields: [FieldDefinition] = []

    /// The properties declared with a property wrapper, recovered at index
    /// time from their compiler-synthesized storage (`_x`) and projection
    /// (`$x`) — which stay in `fields` / `variables` as the binary has them.
    /// See `WrappedPropertyDefinition`.
    public package(set) var wrappedProperties: [WrappedPropertyDefinition] = []

    public package(set) var variables: [VariableDefinition] = []

    public package(set) var functions: [FunctionDefinition] = []

    public package(set) var subscripts: [SubscriptDefinition] = []

    public package(set) var staticVariables: [VariableDefinition] = []

    public package(set) var staticFunctions: [FunctionDefinition] = []

    public package(set) var staticSubscripts: [SubscriptDefinition] = []

    public package(set) var allocators: [FunctionDefinition] = []

    public package(set) var constructors: [FunctionDefinition] = []

    /// The deallocator symbol (`fD`) that backs the dump's `deinit` line.
    ///
    /// - On classes, this is `__deallocating_deinit`: the ARC tear-down
    ///   thunk that calls the user's `deinit` body and frees the storage.
    /// - On `~Copyable` structs/enums, this is the user's `deinit` body
    ///   itself (value types have no separate destructor slot, so the
    ///   compiler reuses the deallocator slot for the user code; the
    ///   demangler prints it as plain `deinit`).
    /// - Regular (copyable) structs/enums have no deallocator, so this is
    ///   nil and `deinit` is suppressed in the dump.
    public package(set) var deallocatorSymbol: DemangledSymbol? = nil

    /// The destructor symbol (`fd`) on classes — the actual Swift `deinit`
    /// body the user wrote (or a shared empty implementation when there is
    /// none). It is reached at runtime via the deallocator above.
    ///
    /// Only emitted for classes; absent for actors and value types, so
    /// look-ups return nil for those. We do not use this symbol to decide
    /// whether to print the `deinit` keyword — the deallocator is a more
    /// uniform anchor — but its address is exposed alongside the
    /// deallocator address so reverse engineers can jump directly to the
    /// user code.
    public package(set) var destructorSymbol: DemangledSymbol? = nil

    public var hasDeallocator: Bool { deallocatorSymbol != nil }

    public package(set) var orderedMembers: [OrderedMember] = []

    public package(set) var conformingProtocolNames: Set<String> = []

    public package(set) var attributes: [SwiftAttribute] = []

    /// Whether `index(in:)` has completed a pass over this definition.
    ///
    /// The setter is `internal`, not `private`, only because the indexing
    /// pass lives in `TypeDefinition+Indexing.swift`: nothing outside this
    /// target may flip it, and inside it only that pass's tail does.
    public internal(set) var isIndexed: Bool = false

    /// Specialized metadata bound to this definition.
    ///
    /// `nil` for the canonical, unspecialized definition produced from a
    /// MachO image's section data. Non-nil only when the definition was
    /// produced via `specialize(with:in:)` — in that case the dumper
    /// receives this metadata directly and uses it for field offsets,
    /// type/enum layout, and value witness queries instead of trying to
    /// call the descriptor's metadata accessor.
    public package(set) var metadata: MetadataWrapper? = nil

    public var hasMembers: Bool {
        !fields.isEmpty || !variables.isEmpty || !functions.isEmpty ||
            !subscripts.isEmpty || !staticVariables.isEmpty || !staticFunctions.isEmpty || !staticSubscripts.isEmpty || !allocators.isEmpty || !constructors.isEmpty || hasDeallocator
    }

    /// Designated initializer. `package`-scoped so the canonical "derive
    /// typeName from `type.typeName(in:)`" path used by indexing cannot be
    /// bypassed from outside the package; the `specialize(with:in:)` family
    /// (the `SwiftSpecialization` extension) is the only in-package caller
    /// that injects a different `typeName`/`isSpecialized` pair.
    ///
    /// The initializer still receives the full wrapper — every construction
    /// path holds one anyway (indexing needs it for `typeName(in:)`) — but
    /// only its descriptor reference is retained, so the caller's parsed
    /// wrapper is released as soon as construction returns.
    package init(type: TypeContextWrapper, typeName: TypeName, isSpecialized: Bool, exportStatus: ExportStatus) {
        self.typeContextDescriptorWrapper = type.typeContextDescriptorWrapper
        self.typeName = typeName
        self.isSpecialized = isSpecialized
        self.exportStatus = exportStatus
    }

    /// Test/tooling surface: constructs a definition around a RAW descriptor
    /// reference, no parsed wrapper required — error-contract tests use it to
    /// build a definition whose indexing/materialization deterministically
    /// fails (a real descriptor layout re-wrapped at an out-of-bounds
    /// offset).
    /// `exportStatus` defaults to the no-verdict case because a definition
    /// built this way has no trustworthy descriptor to rule on.
    package init(
        typeContextDescriptorWrapper: TypeContextDescriptorWrapper,
        typeName: TypeName,
        isSpecialized: Bool,
        exportStatus: ExportStatus = .descriptorSymbolNameUnresolvable
    ) {
        self.typeContextDescriptorWrapper = typeContextDescriptorWrapper
        self.typeName = typeName
        self.isSpecialized = isSpecialized
        self.exportStatus = exportStatus
    }

    public convenience init(type: TypeContextWrapper, in machO: some MachOSwiftSectionRepresentableWithCache) async throws {
        let typeName = try type.typeName(in: machO)
        let exportStatus = ExportStatus.resolve(
            forNominalTypeDescriptorAt: type.typeContextDescriptorWrapper.typeContextDescriptor.offset,
            typeNameNode: typeName.node,
            in: machO
        )
        self.init(type: type, typeName: typeName, isSpecialized: false, exportStatus: exportStatus)
    }
    /// Rebuilds the full `TypeContextWrapper` — trailing objects included —
    /// from the retained descriptor, exactly the parse the model-build sweep
    /// performed once already.
    ///
    /// Materialization discipline (evolution proposal 0002): call at most
    /// once per operation (index it / print it / specialize it) and thread
    /// the result through as a local variable. The result is deliberately
    /// not cached — retaining it on the definition would re-accumulate, in
    /// browse order, the memory the descriptor slimming reclaimed.
    public func materializedTypeContext(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> TypeContextWrapper {
        try TypeContextWrapper.forTypeContextDescriptorWrapper(typeContextDescriptorWrapper, in: machO)
    }
}
