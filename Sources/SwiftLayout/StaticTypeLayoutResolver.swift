import MachOSwiftSection
@_spi(Internals) import SwiftInspection
import Demangling

/// Resolves a Swift type (given by its mangled name or demangled `Node`) to its
/// `TypeLayoutInfo`, recursing into struct/tuple fields and stopping class
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
    private var memoizationCache: [String: TypeLayoutInfo] = [:]
    private var inProgressKeys: Set<String> = []

    init(imageUniverse: ImageUniverse<MachO>) {
        self.imageUniverse = imageUniverse
    }

    /// Resolves the layout of a field given its mangled type name.
    func layout(
        forMangledTypeName mangledTypeName: MangledName,
        in originImage: ImageReference<MachO>
    ) throws -> TypeLayoutInfo {
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
    ) throws -> TypeLayoutInfo {
        let node = unwrappedType(typeNode)
        switch node.kind {
        case .builtinTypeName:
            return try builtinLayout(forNode: node, in: originImage)
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
            return TypeLayoutInfo(size: 16, stride: 16, alignmentMask: 7, extraInhabitantCount: 0, isBitwiseTakable: false)
        case .weak, .unowned, .unmanaged:
            // Reference-storage qualifiers wrap a class reference; the storage
            // itself is one machine word.
            return .pointerSized
        case .metatype:
            return try metatypeLayout(forNode: node)
        case .protocolList, .protocolListWithAnyObject, .protocolListWithClass:
            return try existentialLayout(forNode: node, in: originImage)
        case .existentialMetatype:
            return try existentialMetatypeLayout(forNode: node, in: originImage)
        case .dependentGenericParamType:
            throw LayoutResolutionError.unknown(.genericParameterUnsubstituted)
        default:
            throw LayoutResolutionError.unknown(.unsupportedTypeKind(nodeKindName: String(describing: node.kind)))
        }
    }

    private func unwrappedType(_ node: Node) -> Node {
        if node.kind == .type, let inner = node.firstChild { return inner }
        return node
    }

    /// The layout of a metatype value. The metatype of a concrete value type
    /// (struct/enum/tuple/builtin) is thin — zero-sized, since the type is
    /// statically known; the metatype of a class is thick — a single metadata
    /// pointer.
    private func metatypeLayout(forNode node: Node) throws -> TypeLayoutInfo {
        guard let instanceType = node.firstChild else {
            throw LayoutResolutionError.unknown(.unsupportedTypeKind(nodeKindName: "metatype(no-instance)"))
        }
        let instance = unwrappedType(instanceType)
        switch instance.kind {
        case .class, .boundGenericClass:
            return .pointerSized
        case .structure, .boundGenericStructure,
             .enum, .boundGenericEnum,
             .tuple, .builtinTypeName:
            return .empty
        default:
            throw LayoutResolutionError.unknown(.unsupportedTypeKind(nodeKindName: "metatype(\(instance.kind))"))
        }
    }

    // MARK: - Builtin

    private func builtinLayout(forNode node: Node, in originImage: ImageReference<MachO>) throws -> TypeLayoutInfo {
        if let builtinName = node.text {
            if let known = KnownLayoutTable.layout(forFullyQualifiedTypeName: builtinName) { return known }
            if let fromImage = originImage.builtinLayoutIndex.layout(forTypeName: builtinName) { return fromImage }
            if let primitive = Self.builtinPrimitiveLayout(forName: builtinName) { return primitive }
        }
        throw LayoutResolutionError.unknown(.unsupportedTypeKind(nodeKindName: "builtin:\(node.text ?? "?")"))
    }

    /// Fallback layouts for the compiler's builtin primitives, used when the
    /// image emits no `BuiltinTypeDescriptor` for them.
    private static func builtinPrimitiveLayout(forName builtinName: String) -> TypeLayoutInfo? {
        switch builtinName {
        case "Builtin.NativeObject",
             "Builtin.RawPointer",
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
            return TypeLayoutInfo(
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

    // MARK: - Structure

    private func structureLayout(forNode node: Node, in originImage: ImageReference<MachO>) throws -> TypeLayoutInfo {
        guard let qualifiedTypeName = NodeTypeNaming.nominalQualifiedName(of: node) else {
            throw LayoutResolutionError.unknown(.demangleFailure)
        }
        return try memoizedNominalLayout(forQualifiedTypeName: qualifiedTypeName) {
            guard let resolved = imageUniverse.resolveType(byQualifiedTypeName: qualifiedTypeName) else {
                throw LayoutResolutionError.unknown(.typeDescriptorNotFound(qualifiedTypeName: qualifiedTypeName))
            }
            guard let structDescriptor = resolved.descriptor.struct else {
                throw LayoutResolutionError.unknown(.unsupportedTypeKind(nodeKindName: "non-struct:\(qualifiedTypeName)"))
            }
            return try computeStructLayout(structDescriptor, in: resolved.image).typeLayoutInfo()
        }
    }

    /// Resolves a nominal type's layout through the frozen table, the memo
    /// cache, and the in-progress (cycle) guard, invoking `compute` only on a
    /// genuine cache miss. Shared by struct and enum resolution.
    func memoizedNominalLayout(
        forQualifiedTypeName qualifiedTypeName: String,
        compute: () throws -> TypeLayoutInfo
    ) throws -> TypeLayoutInfo {
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

    /// Computes the full aggregate layout (field offsets + size/stride) of a
    /// struct from its field descriptor. Also the entry point used by the
    /// top-level calculator.
    func computeStructLayout(_ descriptor: StructDescriptor, in image: ImageReference<MachO>) throws -> AggregateLayout {
        let fieldLayouts = try fieldLayouts(ofFieldDescriptorOwner: descriptor, in: image)
        return BasicLayout.compute(startOffset: 0, startAlignmentMask: 0, fieldLayouts: fieldLayouts)
    }

    // MARK: - Class

    /// Computes the full aggregate layout of a class, starting the accumulator
    /// at the superclass instance size (16 for a root class) and recursing
    /// through Swift superclasses.
    func computeClassLayout(_ descriptor: ClassDescriptor, in image: ImageReference<MachO>) throws -> AggregateLayout {
        let start = try superclassStartLayout(of: descriptor, in: image)
        let fieldLayouts = try fieldLayouts(ofFieldDescriptorOwner: descriptor, in: image)
        return BasicLayout.compute(
            startOffset: start.instanceSize,
            startAlignmentMask: start.alignmentMask,
            fieldLayouts: fieldLayouts
        )
    }

    func superclassStartLayout(
        of descriptor: ClassDescriptor,
        in image: ImageReference<MachO>
    ) throws -> (instanceSize: Int, alignmentMask: Int) {
        guard
            let superclassMangledName = try descriptor.superclassTypeMangledName(in: image.machO),
            !superclassMangledName.isEmpty
        else {
            // Root class: sizeof(HeapObject) == isa + refcount == 16, 8-aligned.
            return (16, 7)
        }
        let superclassNode: Node
        do {
            superclassNode = try MetadataReader.demangleType(for: superclassMangledName, in: image.machO)
        } catch {
            throw LayoutResolutionError.unknown(.demangleFailure)
        }
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
        let superclassAggregate = try computeClassLayout(superclassDescriptor, in: resolved.image)
        // A subclass starts where the superclass instance ends (its size, not
        // its stride: classes carry no trailing value padding).
        return (superclassAggregate.size, superclassAggregate.alignmentMask)
    }

    // MARK: - Tuple

    private func tupleLayout(forNode node: Node, in originImage: ImageReference<MachO>) throws -> TypeLayoutInfo {
        var elementLayouts: [TypeLayoutInfo] = []
        for element in node.children {
            guard let elementTypeNode = element.first(of: .type) else { continue }
            elementLayouts.append(try layout(forTypeNode: elementTypeNode, in: originImage))
        }
        return BasicLayout.compute(startOffset: 0, startAlignmentMask: 0, fieldLayouts: elementLayouts).typeLayoutInfo()
    }

    // MARK: - Shared field reading

    /// Reads a struct/class field descriptor and resolves every field's layout
    /// in declaration order.
    private func fieldLayouts(
        ofFieldDescriptorOwner descriptor: some TypeContextDescriptorProtocol,
        in image: ImageReference<MachO>
    ) throws -> [TypeLayoutInfo] {
        let fieldDescriptor = try descriptor.fieldDescriptor(in: image.machO)
        let records = try fieldDescriptor.records(in: image.machO)
        var fieldLayouts: [TypeLayoutInfo] = []
        fieldLayouts.reserveCapacity(records.count)
        for record in records {
            let mangledTypeName = try record.mangledTypeName(in: image.machO)
            fieldLayouts.append(try layout(forMangledTypeName: mangledTypeName, in: image))
        }
        return fieldLayouts
    }
}
