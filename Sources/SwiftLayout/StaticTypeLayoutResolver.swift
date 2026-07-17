import MachOSwiftSection
@_spi(Internals) import SwiftInspection
import Demangling

/// Resolves a Swift type (given by its mangled name or demangled `Node`) to its
/// `StaticTypeLayout`, recursing into struct/tuple fields and stopping class
/// references at a single pointer.
///
/// Dispatch is by `Node.Kind`. Results are memoized per fully-qualified name,
/// and an in-progress set guards against cycles (which can only occur through a
/// class reference — and those are not recursed — so the guard is a backstop).
///
/// The resolver carries an `ImageReference` ("the image the current type is
/// defined in") so that, in a later phase, a field whose type lives in another
/// image can switch context without changing this code.
final class StaticTypeLayoutResolver<MachO: MachOSwiftSectionRepresentableWithCache> {
    let imageUniverse: ImageUniverse<MachO>
    private var memoizationCache: [String: StaticTypeLayout] = [:]
    private var inProgressKeys: Set<String> = []

    init(imageUniverse: ImageUniverse<MachO>) {
        self.imageUniverse = imageUniverse
    }

    /// Resolves the layout of a field given its mangled type name.
    func layout(
        forMangledTypeName mangledTypeName: MangledName,
        in originImage: ImageReference<MachO>
    ) throws -> StaticTypeLayout {
        let typeNode: Node
        do {
            typeNode = try MetadataReader.demangleType(for: mangledTypeName, in: originImage.machO)
        } catch {
            throw LayoutResolutionError.unknown(.demangleFailure)
        }
        return try layout(forTypeNode: typeNode, in: originImage)
    }

    /// Resolves the layout of a (possibly `.type`-wrapped) demangled type node.
    func layout(
        forTypeNode typeNode: Node,
        in originImage: ImageReference<MachO>
    ) throws -> StaticTypeLayout {
        let node = unwrappedType(typeNode)
        switch node.kind {
        case .builtinTypeName:
            return try builtinLayout(forNode: node, in: originImage)
        case .builtinFixedArray:
            guard let countNode = node.firstChild, let elementTypeNode = node.children.at(1) else {
                throw LayoutResolutionError.unknown(.unsupportedTypeKind(nodeKindName: "builtinFixedArray(malformed)"))
            }
            return try fixedArrayLayout(countNode: countNode, elementTypeNode: elementTypeNode, in: originImage)
        case .class, .boundGenericClass:
            // A class field is a single reference; do not recurse (this is also
            // what breaks any potential layout cycle).
            return .pointerSized
        case .structure, .boundGenericStructure:
            return try structureLayout(forNode: node, in: originImage)
        case .enum, .boundGenericEnum:
            return try enumLayout(forNode: node, in: originImage)
        case .tuple:
            return try tupleLayout(forNode: node, in: originImage)
        case .functionType:
            // A thick function value is a (function pointer, context pointer)
            // pair: two words, not bitwise-takable (the context is retained).
            return StaticTypeLayout(size: 16, stride: 16, alignmentMask: 7, extraInhabitantCount: 0, isBitwiseTakable: false)
        case .cFunctionPointer, .objCBlock, .escapingObjCBlock:
            // A C function pointer (`@convention(c)`/`@convention(thin)`) and an
            // Objective-C block (`@convention(block)`) are a single word — unlike
            // the thick Swift `.functionType` (function + context = 16 bytes).
            // Modelled as one pointer; a block's reference-counted nature is not
            // reflected in `isBitwiseTakable`, but size/stride/alignment — all
            // field-offset computation needs — are exact.
            return .pointerSized
        case .weak, .unowned, .unmanaged:
            // Reference-storage qualifiers wrap a class reference; the storage
            // itself is one machine word.
            return .pointerSized
        case .metatype:
            return try metatypeLayout(forNode: node)
        case .protocolList, .protocolListWithAnyObject, .protocolListWithClass:
            return try existentialLayout(forNode: node, in: originImage)
        case .symbolicExtendedExistentialType:
            return try extendedExistentialLayout(forNode: node, in: originImage)
        case .existentialMetatype:
            return try existentialMetatypeLayout(forNode: node, in: originImage)
        case .dependentGenericParamType:
            throw LayoutResolutionError.unknown(.genericParameterUnsubstituted)
        case .dependentMemberType:
            return try dependentMemberTypeLayout(forNode: node, in: originImage)
        default:
            throw LayoutResolutionError.unknown(.unsupportedTypeKind(nodeKindName: String(describing: node.kind)))
        }
    }

    func unwrappedType(_ node: Node) -> Node {
        if node.kind == .type, let inner = node.firstChild { return inner }
        return node
    }

    /// The layout of a metatype value, decided by the instance type's kind —
    /// and, crucially, the *syntactic* kind in the field record, which
    /// substitution deliberately leaves intact (see
    /// `GenericArgumentEnvironment.substitute`).
    ///
    /// A metatype is **thin** (zero-sized, no runtime storage) only when its
    /// instance is a statically-known concrete value type
    /// (struct/enum/tuple/builtin) — IRGen references its metadata directly,
    /// with no field storage. A metatype is **thick** (a single metadata
    /// pointer, `PointerPointerBox` with the heap-object extra-inhabitant count
    /// = `.pointerSized`) when its instance is a class (dynamic type carried at
    /// runtime) **or** a generic parameter / dependent member (an archetype
    /// whose metadata is only known once substituted). The archetype case is
    /// fixed across every instantiation — `T.Type` occupies 8 bytes in
    /// `Foo<Int>` and `Foo<Int8>` alike (empirically verified) — so a field
    /// typed by an unsubstituted parameter's metatype resolves exactly even
    /// unspecialized.
    private func metatypeLayout(forNode node: Node) throws -> StaticTypeLayout {
        guard let instanceType = node.firstChild else {
            throw LayoutResolutionError.unknown(.unsupportedTypeKind(nodeKindName: "metatype(no-instance)"))
        }
        let instance = unwrappedType(instanceType)
        switch instance.kind {
        case .class, .boundGenericClass,
             .dependentGenericParamType, .dependentMemberType:
            return .pointerSized
        case .structure, .boundGenericStructure,
             .enum, .boundGenericEnum,
             .tuple, .builtinTypeName, .builtinFixedArray:
            return .empty
        default:
            throw LayoutResolutionError.unknown(.unsupportedTypeKind(nodeKindName: "metatype(\(instance.kind))"))
        }
    }

    // MARK: - Builtin

    private func builtinLayout(forNode node: Node, in originImage: ImageReference<MachO>) throws -> StaticTypeLayout {
        if let builtinName = node.text {
            if let known = KnownLayoutTable.layout(forFullyQualifiedTypeName: builtinName) { return known }
            if let fromImage = originImage.builtinLayoutIndex.layout(forTypeName: builtinName) { return fromImage }
            if let primitive = Self.builtinPrimitiveLayout(forName: builtinName) { return primitive }
        }
        throw LayoutResolutionError.unknown(.unsupportedTypeKind(nodeKindName: "builtin:\(node.text ?? "?")"))
    }

    /// Fallback layouts for the compiler's builtin primitives, used when the
    /// image emits no `BuiltinTypeDescriptor` for them.
    private static func builtinPrimitiveLayout(forName builtinName: String) -> StaticTypeLayout? {
        switch builtinName {
        case "Builtin.NativeObject",
             "Builtin.RawPointer",
             "Builtin.RawUnsafeContinuation",
             "Builtin.BridgeObject",
             "Builtin.UnknownObject",
             "Builtin.Word":
            return .pointerSized
        case "Builtin.Int1", "Builtin.Int8":
            return .fixedWidthScalar(byteCount: 1)
        case "Builtin.Int16":
            return .fixedWidthScalar(byteCount: 2)
        case "Builtin.Int32", "Builtin.FPIEEE32":
            return .fixedWidthScalar(byteCount: 4)
        case "Builtin.Int64", "Builtin.FPIEEE64":
            return .fixedWidthScalar(byteCount: 8)
        case "Builtin.Int128":
            return .fixedWidthScalar(byteCount: 16)
        case "Builtin.DefaultActorStorage":
            // A default actor's opaque inline storage: NumWords_DefaultActor (12)
            // machine words, aligned to twice the pointer alignment (16). Ported
            // from the runtime reflection lowering's
            // `getDefaultActorStorageTypeInfo()`; this image emits no builtin
            // descriptor for it, so it is answered here.
            let defaultActorWordCount = 12
            let size = 8 * defaultActorWordCount
            return StaticTypeLayout(
                size: size,
                stride: size,
                alignmentMask: 15,
                extraInhabitantCount: 0,
                isBitwiseTakable: true
            )
        default:
            return nil
        }
    }

    // MARK: - Fixed array

    /// The layout of `Builtin.FixedArray<count, Element>` (and of
    /// `Swift.InlineArray`, which wraps it as its only stored field). Ported
    /// from the runtime's `swift_getFixedArrayTypeMetadata` /
    /// `FixedArrayCacheEntry::tryInitialize` and cross-checked against IRGen's
    /// `convertBuiltinFixedArrayType` and RemoteInspection's `ArrayTypeInfo`: a
    /// zero or negative count is the empty layout; otherwise
    /// `size == stride == element.stride × count` (no tail-padding
    /// reclamation, even for a count of 1), alignment and bitwise-takability
    /// follow the element, and extra inhabitants come from the first element.
    private func fixedArrayLayout(
        countNode: Node,
        elementTypeNode: Node,
        in originImage: ImageReference<MachO>
    ) throws -> StaticTypeLayout {
        let count = unwrappedType(countNode)
        switch count.kind {
        case .negativeInteger:
            return .empty
        case .integer:
            guard let rawCount = count.index, let elementCount = Int(exactly: rawCount) else {
                throw LayoutResolutionError.unknown(.unsupportedTypeKind(nodeKindName: "fixedArrayCount(no-value)"))
            }
            guard elementCount > 0 else { return .empty }
            let elementLayout = try layout(forTypeNode: elementTypeNode, in: originImage)
            let (byteCount, didOverflow) = elementLayout.stride.multipliedReportingOverflow(by: elementCount)
            guard !didOverflow else {
                throw LayoutResolutionError.unknown(.unsupportedTypeKind(nodeKindName: "fixedArrayCount(overflow)"))
            }
            return StaticTypeLayout(
                size: byteCount,
                stride: byteCount,
                alignmentMask: elementLayout.alignmentMask,
                extraInhabitantCount: elementLayout.extraInhabitantCount,
                isBitwiseTakable: elementLayout.isBitwiseTakable
            )
        case .dependentGenericParamType:
            throw LayoutResolutionError.unknown(.genericParameterUnsubstituted)
        default:
            throw LayoutResolutionError.unknown(.unsupportedTypeKind(nodeKindName: "fixedArrayCount(\(count.kind))"))
        }
    }

    // MARK: - Structure

    private func structureLayout(forNode node: Node, in originImage: ImageReference<MachO>) throws -> StaticTypeLayout {
        guard let qualifiedTypeName = NodeTypeNaming.nominalQualifiedName(of: node) else {
            throw LayoutResolutionError.unknown(.demangleFailure)
        }
        // A frozen stdlib type whose layout is argument-independent (Array,
        // UnsafePointer, …) resolves by its bare name through the frozen table.
        // Checked first so a generic instantiation cache key (below) never
        // bypasses it and tries to expand the stdlib type's internal storage
        // structurally — which would fail or compute garbage.
        if let known = KnownLayoutTable.layout(forFullyQualifiedTypeName: qualifiedTypeName) {
            return known
        }
        // `Swift.InlineArray<count, Element>` is guaranteed layout-identical to
        // its only stored field, `Builtin.FixedArray<count, Element>`. Computed
        // directly so single-image scopes work (its descriptor lives in the
        // standard library, like `Optional`'s); a dependency closure that can
        // reach the stdlib would resolve it structurally to the same result.
        if qualifiedTypeName == "Swift.InlineArray",
           node.kind == .boundGenericStructure,
           let typeList = node.children.first(where: { $0.kind == .typeList }),
           let countNode = typeList.firstChild,
           let elementTypeNode = typeList.children.at(1) {
            return try fixedArrayLayout(countNode: countNode, elementTypeNode: elementTypeNode, in: originImage)
        }
        // For a concrete generic instantiation (`Foo<Int>`, or a nested
        // `Parent<Int>.Inner` whose arguments ride the parent chain) capture
        // the per-level arguments; the base descriptor's field records
        // reference these by `dependentGenericParamType` and are substituted
        // during field reading. A plain non-instantiated `.structure` node
        // yields `.empty`. Built before the builtin check so an instantiated
        // node (whose layout is argument-dependent) can never match the
        // generic-argument-free builtin key.
        let environment = GenericArgumentEnvironment.make(forInstantiatedTypeNode: node)
        // An imported C value type (e.g. `__C.CGRect`) has no Swift type
        // descriptor, but the using image carries its whole-type layout in a
        // `__swift5_builtin` descriptor. Restricted to non-instantiated
        // structures — the builtin key is generic-argument-free. Normal Swift
        // structs emit no builtin descriptor and fall through to the
        // structural path below.
        if node.kind == .structure, environment.isEmpty,
           let builtinLayout = originImage.builtinLayoutIndex.layout(forTypeName: qualifiedTypeName) {
            return builtinLayout
        }
        let compute: () throws -> StaticTypeLayout = {
            guard let resolved = self.imageUniverse.resolveType(byQualifiedTypeName: qualifiedTypeName) else {
                throw LayoutResolutionError.unknown(.typeDescriptorNotFound(qualifiedTypeName: qualifiedTypeName))
            }
            guard let structDescriptor = resolved.descriptor.struct else {
                throw LayoutResolutionError.unknown(.unsupportedTypeKind(nodeKindName: "non-struct:\(qualifiedTypeName)"))
            }
            return try self.computeStructLayout(structDescriptor, in: resolved.image, environment: environment).asStaticTypeLayout()
        }
        if environment.isEmpty {
            return try memoizedNominalLayout(forQualifiedTypeName: qualifiedTypeName, compute: compute)
        }
        return try memoizedInstantiationLayout(
            forInstantiationKey: Self.instantiationKey(of: node, qualifiedTypeName: qualifiedTypeName),
            compute: compute
        )
    }

    /// Resolves a nominal type's layout through the frozen table, the memo
    /// cache, and the in-progress (cycle) guard, invoking `compute` only on a
    /// genuine cache miss. Shared by struct and enum resolution.
    func memoizedNominalLayout(
        forQualifiedTypeName qualifiedTypeName: String,
        compute: () throws -> StaticTypeLayout
    ) throws -> StaticTypeLayout {
        // Frozen stdlib types (Int/String/Array/…) short-circuit before any
        // descriptor recursion — critical for the reference-backed containers.
        if let known = KnownLayoutTable.layout(forFullyQualifiedTypeName: qualifiedTypeName) { return known }
        if let cached = memoizationCache[qualifiedTypeName] { return cached }
        guard !inProgressKeys.contains(qualifiedTypeName) else {
            throw LayoutResolutionError.unknown(.cyclicLayout)
        }
        inProgressKeys.insert(qualifiedTypeName)
        defer { inProgressKeys.remove(qualifiedTypeName) }
        let layout = try compute()
        memoizationCache[qualifiedTypeName] = layout
        return layout
    }

    /// Memoizes a *generic instantiation* keyed by its remangled name, so
    /// `Foo<Int>` and `Foo<String>` are distinct cache and cycle-guard entries.
    /// Unlike `memoizedNominalLayout`, it skips the frozen-table probe — that
    /// table is keyed by bare names only, never by instantiation keys.
    ///
    /// The cycle guard keys by instantiation, so a pathological self-embedding
    /// value-type generic would recurse (a distinct key per level) rather than
    /// trip `cyclicLayout`; a well-formed binary cannot contain an
    /// infinitely-sized value type (the compiler rejects it), so this is safe.
    func memoizedInstantiationLayout(
        forInstantiationKey key: String,
        compute: () throws -> StaticTypeLayout
    ) throws -> StaticTypeLayout {
        if let cached = memoizationCache[key] { return cached }
        guard !inProgressKeys.contains(key) else {
            throw LayoutResolutionError.unknown(.cyclicLayout)
        }
        inProgressKeys.insert(key)
        defer { inProgressKeys.remove(key) }
        let layout = try compute()
        memoizationCache[key] = layout
        return layout
    }

    /// A stable, instantiation-unique cache key for a bound-generic node: its
    /// remangled name (the inverse of demangling, canonical per instantiation),
    /// falling back to a structural description if remangling fails.
    static func instantiationKey(of node: Node, qualifiedTypeName: String) -> String {
        if let mangled = try? mangleAsString(node) { return mangled }
        return qualifiedTypeName + "|" + String(describing: node)
    }

    /// Resolves a field/payload type from its mangled name, first substituting
    /// the enclosing type's generic arguments (`dependentGenericParamType` →
    /// concrete) so a field typed `A` in `Foo<Int>` resolves as `Int`.
    func layout(
        forMangledTypeName mangledTypeName: MangledName,
        in originImage: ImageReference<MachO>,
        environment: GenericArgumentEnvironment
    ) throws -> StaticTypeLayout {
        let typeNode: Node
        do {
            typeNode = try MetadataReader.demangleType(for: mangledTypeName, in: originImage.machO)
        } catch {
            throw LayoutResolutionError.unknown(.demangleFailure)
        }
        return try layout(forTypeNode: environment.substituting(in: typeNode), in: originImage)
    }

    /// Computes the full aggregate layout (field offsets + size/stride) of a
    /// struct from its field descriptor. Also the entry point used by the
    /// top-level calculator. `environment` substitutes generic arguments when
    /// the struct is reached as a concrete bound-generic instantiation.
    func computeStructLayout(
        _ descriptor: StructDescriptor,
        in image: ImageReference<MachO>,
        environment: GenericArgumentEnvironment = .empty
    ) throws -> AggregateLayout {
        // Class-bound parameters lay out as one object reference even without
        // a substitution (relevant when a bare generic reference reaches the
        // whole-type path with no argument list).
        let environment = environment.augmented(
            withRequirementFacts: ClassBoundGenericParameterAnalysis.layoutFacts(of: descriptor, in: image, imageUniverse: imageUniverse)
        )
        let fieldLayouts = try fieldLayouts(ofFieldDescriptorOwner: descriptor, in: image, environment: environment)
        return BasicLayout.compute(startOffset: 0, startAlignmentMask: 0, fieldLayouts: fieldLayouts)
    }

    // MARK: - Class

    /// Computes the full aggregate layout of a class, starting the accumulator
    /// at the superclass instance size (16 for a root class) and recursing
    /// through Swift superclasses.
    func computeClassLayout(
        _ descriptor: ClassDescriptor,
        in image: ImageReference<MachO>,
        environment: GenericArgumentEnvironment = .empty
    ) throws -> AggregateLayout {
        // Class-bound parameters lay out as one object reference even without
        // a substitution — applied before the superclass computation so
        // `class Sub<Element: AnyObject>: Base<Element>` resolves its start.
        let environment = environment.augmented(
            withRequirementFacts: ClassBoundGenericParameterAnalysis.layoutFacts(of: descriptor, in: image, imageUniverse: imageUniverse)
        )
        let start = try superclassStartLayout(of: descriptor, in: image, environment: environment)
        let fieldLayouts = try fieldLayouts(ofFieldDescriptorOwner: descriptor, in: image, environment: environment)
        return BasicLayout.compute(
            startOffset: start.instanceSize,
            startAlignmentMask: start.alignmentMask,
            fieldLayouts: fieldLayouts
        )
    }

    func superclassStartLayout(
        of descriptor: ClassDescriptor,
        in image: ImageReference<MachO>,
        environment: GenericArgumentEnvironment = .empty
    ) throws -> (instanceSize: Int, alignmentMask: Int) {
        guard
            let superclassMangledName = try descriptor.superclassTypeMangledName(in: image.machO),
            !superclassMangledName.isEmpty
        else {
            // Root class: sizeof(HeapObject) == isa + refcount == 16, 8-aligned.
            return (16, 7)
        }
        let demangledSuperclassNode: Node
        do {
            demangledSuperclassNode = try MetadataReader.demangleType(for: superclassMangledName, in: image.machO)
        } catch {
            throw LayoutResolutionError.unknown(.demangleFailure)
        }
        // Substitute this class's generic arguments into the superclass
        // reference first, so `class Sub<T>: Base<T>` instantiated as `Sub<Int>`
        // resolves its superclass as `Base<Int>` (and then binds Base's own
        // parameter to `Int` below).
        let superclassNode = environment.substituting(in: demangledSuperclassNode)
        // An Objective-C ancestor (e.g. `NSObject`) has no Swift descriptor; its
        // mangled name demangles to `__C.<Name>`. Start this class's own fields
        // at the ObjC class's instance size, read from the ObjC class index.
        // Checked *before* the Swift lookup below, which would otherwise fold the
        // entire dependency closure on a name it can never define.
        if let objCClassBareName = NodeTypeNaming.objCClassBareName(of: superclassNode) {
            guard let objCStartLayout = imageUniverse.resolveObjCClassInstanceSize(byBareName: objCClassBareName) else {
                throw LayoutResolutionError.unknown(.objCAncestorUnresolved(className: objCClassBareName))
            }
            return objCStartLayout
        }
        guard
            let qualifiedTypeName = NodeTypeNaming.nominalQualifiedName(of: superclassNode),
            let resolved = imageUniverse.resolveType(byQualifiedTypeName: qualifiedTypeName),
            let superclassDescriptor = resolved.descriptor.class
        else {
            // A cross-module resilient Swift superclass not reachable in the
            // current scope (resolved by the dependency closure).
            throw LayoutResolutionError.unknown(.resilientFieldUnresolved)
        }
        // The superclass's own generic arguments come from the (substituted)
        // superclass node: `Base<Int>` binds Base's parameters to `Int`.
        let superclassEnvironment = GenericArgumentEnvironment.make(forInstantiatedTypeNode: superclassNode)
        let superclassAggregate = try computeClassLayout(superclassDescriptor, in: resolved.image, environment: superclassEnvironment)
        // A subclass starts where the superclass instance ends (its size, not
        // its stride: classes carry no trailing value padding).
        return (superclassAggregate.size, superclassAggregate.alignmentMask)
    }

    // MARK: - Tuple

    private func tupleLayout(forNode node: Node, in originImage: ImageReference<MachO>) throws -> StaticTypeLayout {
        var elementLayouts: [StaticTypeLayout] = []
        for element in node.children {
            guard let elementTypeNode = element.first(of: .type) else { continue }
            // A pack expansion that survived substitution means its count was
            // never concretely bound (a bare generic context, a depth > 0
            // parameter): the tuple's very arity is unknown.
            if elementTypeNode.firstChild?.kind == .packExpansion {
                throw LayoutResolutionError.unknown(.genericParameterUnsubstituted)
            }
            elementLayouts.append(try layout(forTypeNode: elementTypeNode, in: originImage))
        }
        // A tuple takes its extra inhabitants from the element with the most
        // (runtime `swift_getTupleTypeMetadata`); size/stride/alignment fold
        // through `performBasicLayout` as for any aggregate.
        let extraInhabitantCount = elementLayouts.map(\.extraInhabitantCount).max() ?? 0
        return BasicLayout.compute(startOffset: 0, startAlignmentMask: 0, fieldLayouts: elementLayouts)
            .asStaticTypeLayout(extraInhabitantCount: extraInhabitantCount)
    }

    // MARK: - Shared field reading

    /// Reads a struct/class field descriptor and resolves every field's layout
    /// in declaration order.
    private func fieldLayouts(
        ofFieldDescriptorOwner descriptor: some TypeContextDescriptorProtocol,
        in image: ImageReference<MachO>,
        environment: GenericArgumentEnvironment = .empty
    ) throws -> [StaticTypeLayout] {
        let fieldDescriptor = try descriptor.fieldDescriptor(in: image.machO)
        let records = try fieldDescriptor.records(in: image.machO)
        var fieldLayouts: [StaticTypeLayout] = []
        fieldLayouts.reserveCapacity(records.count)
        for record in records {
            let mangledTypeName = try record.mangledTypeName(in: image.machO)
            fieldLayouts.append(try layout(forMangledTypeName: mangledTypeName, in: image, environment: environment))
        }
        return fieldLayouts
    }
}
