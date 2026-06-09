import Foundation
import MachOSwiftSection
import MachOKit
import MemberwiseInit
import OrderedCollections
import SwiftDump
import Demangling
import Semantic
import SwiftStdlibToolbox
import Dependencies
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection

public final class TypeDefinition: Definition {
    public enum ParentContext {
        case `extension`(ExtensionContext)
        case type(TypeContextWrapper)
        case symbol(Symbol)
    }

    public let type: TypeContextWrapper

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

    public internal(set) weak var parent: TypeDefinition?

    public internal(set) var typeChildren: [TypeDefinition] = []

    public internal(set) var protocolChildren: [ProtocolDefinition] = []

    public internal(set) var parentContext: ParentContext? = nil

    public internal(set) var extensions: [ExtensionDefinition] = []

    public internal(set) var fields: [FieldDefinition] = []

    public internal(set) var variables: [VariableDefinition] = []

    public internal(set) var functions: [FunctionDefinition] = []

    public internal(set) var subscripts: [SubscriptDefinition] = []

    public internal(set) var staticVariables: [VariableDefinition] = []

    public internal(set) var staticFunctions: [FunctionDefinition] = []

    public internal(set) var staticSubscripts: [SubscriptDefinition] = []

    public internal(set) var allocators: [FunctionDefinition] = []

    public internal(set) var constructors: [FunctionDefinition] = []

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
    public internal(set) var deallocatorSymbol: DemangledSymbol? = nil

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
    public internal(set) var destructorSymbol: DemangledSymbol? = nil

    public var hasDeallocator: Bool { deallocatorSymbol != nil }

    public internal(set) var orderedMembers: [OrderedMember] = []

    public internal(set) var conformingProtocolNames: Set<String> = []

    public internal(set) var attributes: [SwiftAttribute] = []

    public private(set) var isIndexed: Bool = false

    /// Specialized metadata bound to this definition.
    ///
    /// `nil` for the canonical, unspecialized definition produced from a
    /// MachO image's section data. Non-nil only when the definition was
    /// produced via `specialize(with:in:)` — in that case the dumper
    /// receives this metadata directly and uses it for field offsets,
    /// type/enum layout, and value witness queries instead of trying to
    /// call the descriptor's metadata accessor.
    public internal(set) var metadata: MetadataWrapper? = nil

    /// Specialized children produced from this generic definition via
    /// `specialize(with:in:)`. Each entry is a sibling-shaped
    /// `TypeDefinition` that wraps the same `type` but carries a
    /// runtime-resolved metadata. Lives on the model rather than on the
    /// indexer so the indexer remains agnostic of user-driven
    /// specialization state.
    public private(set) var specializedChildren: [TypeDefinition] = []

    public var hasMembers: Bool {
        !fields.isEmpty || !variables.isEmpty || !functions.isEmpty ||
            !subscripts.isEmpty || !staticVariables.isEmpty || !staticFunctions.isEmpty || !staticSubscripts.isEmpty || !allocators.isEmpty || !constructors.isEmpty || hasDeallocator
    }

    /// Designated initializer. Internal so the canonical "derive typeName
    /// from `type.typeName(in:)`" path used by indexing cannot be bypassed
    /// from outside the package; `specialize(with:in:)` is the only
    /// in-package caller that injects a different `typeName`/`isSpecialized`
    /// pair.
    internal init(type: TypeContextWrapper, typeName: TypeName, isSpecialized: Bool) {
        self.type = type
        self.typeName = typeName
        self.isSpecialized = isSpecialized
    }

    public convenience init<MachO: MachOSwiftSectionRepresentableWithCache>(type: TypeContextWrapper, in machO: MachO) async throws {
        let typeName = try type.typeName(in: machO)
        self.init(type: type, typeName: typeName, isSpecialized: false)
    }

    /// Append a new specialized `TypeDefinition` derived from this
    /// definition's `type` and the metadata carried by
    /// `specializationResult`.
    ///
    /// Validation, all of which throws `SpecializationError` on failure:
    /// 1. The receiver's descriptor must be generic — specializing a
    ///    non-generic type does not make sense.
    /// 2. The `MetadataWrapper`'s case must be compatible with the
    ///    receiver's `type` case (struct↔struct, class↔class,
    ///    enum↔enum/optional). A mismatch typically means a
    ///    `SpecializationResult` produced for a different generic type
    ///    was handed in.
    /// 3. The metadata's resolved descriptor must be the same descriptor
    ///    as the receiver's `type`. This is the strongest guarantee that
    ///    the result was produced by specializing exactly this type.
    ///
    /// The two `machO` parameters serve different roles:
    /// - `machO` is used to construct the inner `TypeDefinition` and
    ///   re-derive its type name. It can be any reader (file or image).
    /// - `machOImage` is required because the result's metadata pointer
    ///   resolves through process memory only (the runtime's metadata
    ///   cache lives outside any MachO image); descriptor identity
    ///   validation needs the receiver's descriptor in its in-process
    ///   form, and that is what `asPointerWrapper(in:)` produces.
    @discardableResult
    public func specialize(
        with specializationResult: SpecializationResult,
        typeArgumentNodes: [Node]? = nil,
        in machO: MachOImage,
    ) async throws -> TypeDefinition {
        let specialized = try makeSpecializedDefinition(
            with: specializationResult,
            typeArgumentNodes: typeArgumentNodes,
            in: machO
        )
        specializedChildren.append(specialized)
        return specialized
    }

    @_spi(Support)
    @discardableResult
    public func specialize(
        with specializationResult: SpecializationResult,
        typeArgumentNodes: [Node]? = nil,
        derivingNestedSpecializationsWith specializer: GenericSpecializer<MachOImage>,
        selection: SpecializationSelection,
        typeArgumentNodesByParameter: [String: Node],
        in machO: MachOImage
    ) async throws -> TypeDefinition {
        let specialized = try makeSpecializedDefinition(
            with: specializationResult,
            typeArgumentNodes: typeArgumentNodes,
            in: machO
        )
        specialized.typeChildren = try await deriveNestedSpecializedTypeChildren(
            using: specializer,
            selection: selection,
            typeArgumentNodesByParameter: typeArgumentNodesByParameter,
            inheritedTypeArgumentNodes: typeArgumentNodes ?? [],
            in: machO,
            depth: 0
        )
        for child in specialized.typeChildren {
            child.parent = specialized
        }
        specializedChildren.append(specialized)
        return specialized
    }

    private func makeSpecializedDefinition(
        with specializationResult: SpecializationResult,
        typeArgumentNodes: [Node]?,
        in machO: MachOImage
    ) throws -> TypeDefinition {
        let metadata = try specializationResult.resolveMetadata()

        try validateSpecialization(metadata: metadata, in: machO)

        // Compute the final typeName up-front so it can flow through the
        // designated init: either the unbound form (`Box<A>`) when no type
        // arguments are supplied, or the bound form (`Box<Int>`) produced by
        // `boundGenericTypeName(...)`. The latter makes the specialized
        // definition print as `Box<Int>` rather than the placeholder
        // `Box<A>`, and gives it a unique mangled name per specialization
        // (via `mangleAsString(typeName.node)`).
        let unboundTypeName = try type.typeName(in: machO)
        let finalTypeName: TypeName
        if let typeArgumentNodes, !typeArgumentNodes.isEmpty {
            finalTypeName = Self.boundGenericTypeName(
                unboundTypeName: unboundTypeName,
                typeArgumentNodes: typeArgumentNodes
            )
        } else {
            finalTypeName = unboundTypeName
        }

        let specialized = TypeDefinition(type: type, typeName: finalTypeName, isSpecialized: true)
        specialized.metadata = metadata
        return specialized
    }

    private func deriveNestedSpecializedTypeChildren(
        using specializer: GenericSpecializer<MachOImage>,
        selection: SpecializationSelection,
        typeArgumentNodesByParameter: [String: Node],
        inheritedTypeArgumentNodes: [Node],
        in machO: MachOImage,
        depth: Int
    ) async throws -> [TypeDefinition] {
        guard depth < 16 else { return [] }

        var derivedChildren: [TypeDefinition] = []
        for child in typeChildren {
            guard child.type.typeContextDescriptorWrapper.typeContextDescriptor.layout.flags.isGeneric else {
                continue
            }

            let request = try specializer.makeRequest(for: child.type.typeContextDescriptorWrapper)
            var childArguments: [String: SpecializationSelection.Argument] = [:]
            var childArgumentNodes: [Node] = []
            var childNodesByParameter: [String: Node] = [:]
            var hasCompleteBinding = true

            for parameter in request.parameters {
                guard let argument = selection.arguments[parameter.name],
                      let node = typeArgumentNodesByParameter[parameter.name]
                else {
                    hasCompleteBinding = false
                    break
                }
                childArguments[parameter.name] = argument
                childArgumentNodes.append(node)
                childNodesByParameter[parameter.name] = node
            }

            guard hasCompleteBinding else {
                continue
            }

            let childSelection = SpecializationSelection(arguments: childArguments)
            let childResult = try specializer.specialize(request, with: childSelection)
            let effectiveChildArgumentNodes = childArgumentNodes.isEmpty
                ? inheritedTypeArgumentNodes
                : childArgumentNodes
            let childSpecialized = try child.makeSpecializedDefinition(
                with: childResult,
                typeArgumentNodes: effectiveChildArgumentNodes,
                in: machO
            )
            childSpecialized.typeChildren = try await child.deriveNestedSpecializedTypeChildren(
                using: specializer,
                selection: childSelection,
                typeArgumentNodesByParameter: childNodesByParameter,
                inheritedTypeArgumentNodes: effectiveChildArgumentNodes,
                in: machO,
                depth: depth + 1
            )
            for grandchild in childSpecialized.typeChildren {
                grandchild.parent = childSpecialized
            }
            derivedChildren.append(childSpecialized)
        }
        return derivedChildren
    }

    /// Build a bound-generic `TypeName` by wrapping the supplied unbound
    /// (`Type → Structure(...)` / `Class(...)` / `Enum(...)`) form with a
    /// `BoundGeneric{Class,Structure,Enum}` node carrying the concrete type
    /// argument list.
    ///
    /// Mirrors the shape Swift's demangler produces at
    /// `swift-demangling/.../Demangler.swift:1184` —
    /// `Node.create(kind: kind, children: [Node.create(kind: .type, child: n), args])` —
    /// so the result round-trips cleanly through `mangleAsString` /
    /// `Remangler.mangleBoundGenericStructure`. Both the unbound type and
    /// every TypeList entry are normalized to a `Type`-wrapped form because
    /// callers occasionally hand us bare `Structure(...)` nodes (the wrap is a
    /// no-op when the input is already `.type`).
    ///
    /// Default access (`internal`) so unit tests in `SwiftInterfaceTests` can
    /// exercise the substitution shape without spinning up a full MachO
    /// fixture.
    static func boundGenericTypeName(
        unboundTypeName: TypeName,
        typeArgumentNodes: [Node]
    ) -> TypeName {
        let unboundTypeNode: Node
        if unboundTypeName.node.kind == .type {
            unboundTypeNode = unboundTypeName.node
        } else {
            unboundTypeNode = Node.create(kind: .type, children: [unboundTypeName.node])
        }

        let normalizedArgumentNodes: [Node] = typeArgumentNodes.map { argumentNode in
            if argumentNode.kind == .type {
                return argumentNode
            } else {
                return Node.create(kind: .type, children: [argumentNode])
            }
        }

        let boundKind: Node.Kind
        switch unboundTypeName.kind {
        case .struct: boundKind = .boundGenericStructure
        case .class: boundKind = .boundGenericClass
        case .enum: boundKind = .boundGenericEnum
        }

        let typeList = Node.create(kind: .typeList, children: normalizedArgumentNodes)
        let boundNode = Node.create(kind: boundKind, children: [unboundTypeNode, typeList])
        let wrappedNode = Node.create(kind: .type, children: [boundNode])

        return TypeName(node: wrappedNode, kind: unboundTypeName.kind)
    }

    private func validateSpecialization(metadata: MetadataWrapper, in machO: MachOImage) throws {
        // 1. Receiver must be generic. A non-generic descriptor has a
        //    fixed metadata; specializing it is meaningless and would
        //    indicate the caller wired the wrong type.
        guard type.typeContextDescriptorWrapper.typeContextDescriptor.layout.flags.isGeneric else {
            throw SpecializationError.notGenericType(typeName: typeName.name)
        }

        // 2. The metadata case must align with the type case. Allow both
        //    `enum` and `optional` payloads for `.enum` types — Swift
        //    distinguishes these by metadata kind only, and either can be
        //    the legitimate output of specializing an enum.
        let isCompatibleKind: Bool
        switch type {
        case .struct: isCompatibleKind = metadata.isStruct
        case .enum: isCompatibleKind = metadata.isEnum || metadata.isOptional
        case .class: isCompatibleKind = metadata.isClass
        }
        guard isCompatibleKind else {
            throw SpecializationError.metadataKindMismatch(
                typeName: typeName.name,
                expected: type,
                actual: metadata
            )
        }

        // 3. Compare descriptor identity. The receiver's descriptor is
        //    re-resolved into its in-process form via `asPointerWrapper`
        //    so that the offsets being compared are both process-memory
        //    addresses. A mismatch means the result was specialized for
        //    a structurally similar but distinct type.
        let inProcessType = type.typeContextDescriptorWrapper.asPointerWrapper(in: machO)
        let expectedDescriptorOffset = inProcessType.typeContextDescriptor.offset
        let actualDescriptorOffset = try descriptorOffset(of: metadata)
        guard expectedDescriptorOffset == actualDescriptorOffset else {
            throw SpecializationError.descriptorMismatch(
                typeName: typeName.name,
                expectedOffset: expectedDescriptorOffset,
                actualOffset: actualDescriptorOffset
            )
        }
    }

    private func descriptorOffset(of metadata: MetadataWrapper) throws -> Int {
        switch metadata {
        case .struct(let structMetadata):
            return try structMetadata.descriptor().contextDescriptor.offset
        case .class(let classMetadata):
            return try required(classMetadata.descriptor()).offset
        case .enum(let enumMetadata), .optional(let enumMetadata), .errorObject(let enumMetadata):
            return try enumMetadata.descriptor().contextDescriptor.offset
        default:
            // Other metadata kinds don't carry a nominal-type descriptor in
            // the form we compare against here. Treating this as a hard
            // failure (rather than skipping the check silently) makes it
            // obvious if a new wrapper case is added without updating this
            // switch.
            throw SpecializationError.unsupportedMetadataKind(metadata: metadata)
        }
    }

    /// Errors raised by `specialize(with:in:image:)` when the supplied
    /// `SpecializationResult` cannot be reconciled with the receiver.
    public enum SpecializationError: LocalizedError {
        case notGenericType(typeName: String)
        case metadataKindMismatch(typeName: String, expected: TypeContextWrapper, actual: MetadataWrapper)
        case descriptorMismatch(typeName: String, expectedOffset: Int, actualOffset: Int)
        case unsupportedMetadataKind(metadata: MetadataWrapper)

        public var errorDescription: String? {
            switch self {
            case .notGenericType(let typeName):
                return "Cannot specialize non-generic type '\(typeName)'"
            case .metadataKindMismatch(let typeName, let expected, let actual):
                return "Specialization metadata for '\(typeName)' has incompatible kind: expected \(expected), got \(actual)"
            case .descriptorMismatch(let typeName, let expectedOffset, let actualOffset):
                return "Specialization metadata for '\(typeName)' references a different descriptor (expected offset 0x\(String(expectedOffset, radix: 16)), got 0x\(String(actualOffset, radix: 16)))"
            case .unsupportedMetadataKind(let metadata):
                return "Specialization metadata kind is not supported for descriptor identity validation: \(metadata)"
            }
        }
    }

    package func index<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) async throws {
        guard !isIndexed else { return }

        @Dependency(\.symbolIndexStore)
        var symbolIndexStore

        var fields: [FieldDefinition] = []
        let typeContextDescriptor = try required(type.contextDescriptorWrapper.typeContextDescriptor)
        let fieldDescriptor = try typeContextDescriptor.fieldDescriptor(in: machO)
        let records = try fieldDescriptor.records(in: machO)
        for record in records {
            let typeNode = try record.demangledTypeNode(in: machO)
            let name = try record.fieldName(in: machO)
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
            let field = FieldDefinition(name: name.stripLazyPrefix, typeNode: typeNode, flags: fieldFlags)
            fields.append(field)
        }

        self.fields = fields

        let fieldNames = Set(fields.map(\.name))

        var methodDescriptorLookup: [Node: MethodDescriptorWrapper] = [:]
        var vtableOffsetLookup: [Node: Int] = [:]
        // Fallback lookups keyed by implementation file offset (for methods where node-based matching fails)
        var implOffsetDescriptorLookup: [Int: MethodDescriptorWrapper] = [:]
        var implOffsetVTableSlotLookup: [Int: Int] = [:]
        if case .class(let cls) = type {
            var visitedNodes: OrderedSet<Node> = []
            let typeNode = try MetadataReader.demangleContext(for: .type(.class(cls.descriptor)), in: machO)
            let vtableBaseOffset = cls.vTableDescriptorHeader.map { Int($0.layout.vTableOffset) }

            // Build offset-based fallback lookups. Uniqueness must be checked against
            // ALL descriptor kinds (method + override + defaultOverride), because
            // trampolines/thunks/shared implementations can have multiple descriptors
            // pointing at the same impl address. If the impl is not globally unique,
            // we cannot use offset-based fallback — we would not know which descriptor
            // to associate the symbol with.
            var implOffsetCounts: [Int: Int] = [:]
            for descriptor in cls.methodDescriptors where !descriptor.implementation.isNull {
                let implOffset = descriptor.implementation.resolveDirectOffset(from: descriptor.offset(of: \.implementation))
                implOffsetCounts[implOffset, default: 0] += 1
            }
            for descriptor in cls.methodOverrideDescriptors where !descriptor.implementation.isNull {
                let implOffset = descriptor.implementation.resolveDirectOffset(from: descriptor.offset(of: \.implementation))
                implOffsetCounts[implOffset, default: 0] += 1
            }
            for descriptor in cls.methodDefaultOverrideDescriptors where !descriptor.implementation.isNull {
                let implOffset = descriptor.implementation.resolveDirectOffset(from: descriptor.offset(of: \.implementation))
                implOffsetCounts[implOffset, default: 0] += 1
            }
            for (index, descriptor) in cls.methodDescriptors.enumerated() where !descriptor.implementation.isNull {
                let implOffset = descriptor.implementation.resolveDirectOffset(from: descriptor.offset(of: \.implementation))
                // Only use offset-based fallback for globally unique implementation addresses
                if implOffsetCounts[implOffset] == 1 {
                    implOffsetDescriptorLookup[implOffset] = .method(descriptor)
                    if let vtableBaseOffset {
                        implOffsetVTableSlotLookup[implOffset] = vtableBaseOffset + index
                    }
                }
            }

            for (index, descriptor) in cls.methodDescriptors.enumerated() {
                guard let symbols = try descriptor.implementationSymbols(in: machO) else { continue }
                guard let overrideSymbol = try classDemangledSymbol(for: symbols, typeNode: typeNode, visitedNodes: visitedNodes, in: machO) else { continue }
                let node = overrideSymbol.demangledNode
                visitedNodes.append(node)
                methodDescriptorLookup[node] = .method(descriptor)
                if let vtableBaseOffset {
                    vtableOffsetLookup[node] = vtableBaseOffset + index
                }
            }
            var parentVTableCache = ParentClassVTableCache()

            for descriptor in cls.methodOverrideDescriptors {
                guard let symbols = try descriptor.implementationSymbols(in: machO) else { continue }
                guard let overrideSymbol = try classDemangledSymbol(for: symbols, typeNode: typeNode, visitedNodes: visitedNodes, in: machO) else { continue }
                let node = overrideSymbol.demangledNode
                visitedNodes.append(node)
                methodDescriptorLookup[node] = .methodOverride(descriptor)

                if let vtableSlot = try? parentVTableCache.slotIndex(for: descriptor, in: machO) {
                    vtableOffsetLookup[node] = vtableSlot
                }
            }
            for descriptor in cls.methodDefaultOverrideDescriptors {
                guard let symbols = try descriptor.implementationSymbols(in: machO) else { continue }
                guard let overrideSymbol = try classDemangledSymbol(for: symbols, typeNode: typeNode, visitedNodes: visitedNodes, in: machO) else { continue }
                let node = overrideSymbol.demangledNode
                visitedNodes.append(node)
                methodDescriptorLookup[node] = .methodDefaultOverride(descriptor)
            }
        }

        let name = typeName.name
        let node = typeName.node

        allocators = DefinitionBuilder.allocators(
            for: symbolIndexStore.memberSymbols(of: .allocator(inExtension: false), for: name, node: node, in: machO).map { .init(base: $0, offset: nil) },
            methodDescriptorLookup: methodDescriptorLookup,
            vtableOffsetLookup: vtableOffsetLookup,
            implOffsetDescriptorLookup: implOffsetDescriptorLookup,
            implOffsetVTableSlotLookup: implOffsetVTableSlotLookup
        )

        // See the property doc comments for the role each symbol plays.
        // The deallocator drives whether `deinit` is printed at all; the
        // destructor (only present on classes) is exposed as an extra
        // address comment.
        deallocatorSymbol = symbolIndexStore.memberSymbols(of: .deallocator, for: typeName.name, in: machO).first
        destructorSymbol = symbolIndexStore.memberSymbols(of: .destructor, for: typeName.name, in: machO).first

        variables = DefinitionBuilder.variables(
            for: symbolIndexStore.memberSymbols(of: .variable(inExtension: false, isStatic: false, isStorage: false), for: name, node: node, in: machO).map { .init(base: $0, offset: nil) },
            fieldNames: fieldNames,
            methodDescriptorLookup: methodDescriptorLookup,
            vtableOffsetLookup: vtableOffsetLookup,
            implOffsetDescriptorLookup: implOffsetDescriptorLookup,
            implOffsetVTableSlotLookup: implOffsetVTableSlotLookup,
            isGlobalOrStatic: false
        )

        staticVariables = DefinitionBuilder.variables(
            for: symbolIndexStore.memberSymbols(
                of: .variable(inExtension: false, isStatic: true, isStorage: false),
                .variable(inExtension: false, isStatic: true, isStorage: true),
                for: name,
                node: node,
                in: machO
            ).map { .init(base: $0, offset: nil) },
            methodDescriptorLookup: methodDescriptorLookup,
            vtableOffsetLookup: vtableOffsetLookup,
            implOffsetDescriptorLookup: implOffsetDescriptorLookup,
            implOffsetVTableSlotLookup: implOffsetVTableSlotLookup,
            isGlobalOrStatic: true
        )

        functions = DefinitionBuilder.functions(
            for: symbolIndexStore.memberSymbols(of: .function(inExtension: false, isStatic: false), for: name, node: node, in: machO).map { .init(base: $0, offset: nil) },
            methodDescriptorLookup: methodDescriptorLookup,
            vtableOffsetLookup: vtableOffsetLookup,
            implOffsetDescriptorLookup: implOffsetDescriptorLookup,
            implOffsetVTableSlotLookup: implOffsetVTableSlotLookup,
            isGlobalOrStatic: false
        )

        staticFunctions = DefinitionBuilder.functions(
            for: symbolIndexStore.memberSymbols(of: .function(inExtension: false, isStatic: true), for: name, node: node, in: machO).map { .init(base: $0, offset: nil) },
            methodDescriptorLookup: methodDescriptorLookup,
            vtableOffsetLookup: vtableOffsetLookup,
            implOffsetDescriptorLookup: implOffsetDescriptorLookup,
            implOffsetVTableSlotLookup: implOffsetVTableSlotLookup,
            isGlobalOrStatic: true
        )

        subscripts = DefinitionBuilder.subscripts(
            for: symbolIndexStore.memberSymbols(of: .subscript(inExtension: false, isStatic: false), for: name, node: node, in: machO).map { .init(base: $0, offset: nil) },
            methodDescriptorLookup: methodDescriptorLookup,
            vtableOffsetLookup: vtableOffsetLookup,
            implOffsetDescriptorLookup: implOffsetDescriptorLookup,
            implOffsetVTableSlotLookup: implOffsetVTableSlotLookup,
            isStatic: false
        )

        staticSubscripts = DefinitionBuilder.subscripts(
            for: symbolIndexStore.memberSymbols(of: .subscript(inExtension: false, isStatic: true), for: name, node: node, in: machO).map { .init(base: $0, offset: nil) },
            methodDescriptorLookup: methodDescriptorLookup,
            vtableOffsetLookup: vtableOffsetLookup,
            implOffsetDescriptorLookup: implOffsetDescriptorLookup,
            implOffsetVTableSlotLookup: implOffsetVTableSlotLookup,
            isStatic: true
        )

        // Cross-reference @objc and @nonobjc thunk symbols with built definitions
        applyThunkAttributes(symbolIndexStore: symbolIndexStore, typeName: name, in: machO)

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
        if case .class = type {
            orderedMembers = OrderedMember.classOrdered(allMembers)
        } else {
            orderedMembers = OrderedMember.offsetOrdered(allMembers)
        }

        isIndexed = true
    }

    /// Cross-references `@objc` / `@nonobjc` thunk attribute members (pre-extracted
    /// and bucketed by parent type name inside `SymbolIndexStore`) with the
    /// already-built member definitions of this type, appending the matching
    /// attribute to each affected member.
    private func applyThunkAttributes<MachO: MachORepresentableWithCache>(
        symbolIndexStore: SymbolIndexStore,
        typeName: String,
        in machO: MachO
    ) {
        let thunkKindsAndAttributes: [(Node.Kind, SwiftAttribute)] = [
            (.objCAttribute, .objc),
            (.nonObjCAttribute, .nonobjc),
            (.distributedThunk, .distributed),
        ]

        for (thunkKind, attribute) in thunkKindsAndAttributes {
            let members = symbolIndexStore.thunkAttributeMembers(of: thunkKind, for: typeName, in: machO)
            for member in members {
                if member.isStatic {
                    applyAttributeToFunction(name: member.memberName, attribute: attribute, in: &staticFunctions)
                    applyAttributeToVariable(name: member.memberName, attribute: attribute, in: &staticVariables)
                } else {
                    applyAttributeToFunction(name: member.memberName, attribute: attribute, in: &functions)
                    applyAttributeToVariable(name: member.memberName, attribute: attribute, in: &variables)
                    if member.isInit {
                        applyAttributeToAllocator(attribute: attribute, in: &allocators)
                    }
                }
            }
        }
    }

    private func applyAttributeToFunction(name: String, attribute: SwiftAttribute, in definitions: inout [FunctionDefinition]) {
        for definitionIndex in definitions.indices {
            if definitions[definitionIndex].name == name && !definitions[definitionIndex].attributes.contains(attribute) {
                definitions[definitionIndex].attributes.append(attribute)
            }
        }
    }

    private func applyAttributeToVariable(name: String, attribute: SwiftAttribute, in definitions: inout [VariableDefinition]) {
        for definitionIndex in definitions.indices {
            if definitions[definitionIndex].name == name && !definitions[definitionIndex].attributes.contains(attribute) {
                definitions[definitionIndex].attributes.append(attribute)
            }
        }
    }

    private func applyAttributeToAllocator(attribute: SwiftAttribute, in definitions: inout [FunctionDefinition]) {
        for definitionIndex in definitions.indices {
            if !definitions[definitionIndex].attributes.contains(attribute) {
                definitions[definitionIndex].attributes.append(attribute)
            }
        }
    }

    /// Drops body-side copies of members that Swift auto-synthesizes for
    /// `Equatable` / `Hashable` / `Codable` / `CaseIterable` / `RawRepresentable` /
    /// `CodingKey` conformances. These members are emitted twice in binary
    /// metadata — once as a direct entry on the nominal type (which ends up in
    /// this type's `functions` / `staticFunctions` / `variables`) and once as a
    /// witness thunk on the protocol conformance descriptor (which ends up in
    /// the generated conformance extension). The extension copy is the one
    /// Swift source conventionally shows for these protocols, so we drop the
    /// body-side copy.
    ///
    /// Detection is gated on the type actually conforming to the relevant
    /// protocol (via `conformingProtocolNames`), and on the member matching
    /// the canonical synthesized shape (name + label list). A user-written
    /// override with a compatible signature will also be dropped from the
    /// body, but the equivalent entry remains visible in the conformance
    /// extension, so nothing is hidden — the output is just no longer
    /// duplicated. See roadmap P1-10.
    private func deduplicateSynthesizedProtocolMembers() {
        // Precompute the short (unqualified) names of every protocol this
        // type conforms to, so downstream checks can ignore module qualifiers.
        var shortProtocolNames: Set<String> = []
        for protocolName in conformingProtocolNames {
            if let dotIndex = protocolName.lastIndex(of: ".") {
                shortProtocolNames.insert(String(protocolName[protocolName.index(after: dotIndex)...]))
            } else {
                shortProtocolNames.insert(protocolName)
            }
        }

        if shortProtocolNames.isEmpty { return }

        // Returns the argument label list of a member as an array of strings,
        // with "_" for unnamed parameters. Works on function / constructor /
        // allocator / getter nodes; returns an empty array if no labelList
        // node exists (which means the function either takes no parameters
        // or takes exclusively unnamed parameters — the demangler does not
        // always emit an explicit labelList for the all-unnamed case).
        func labels(of node: Node) -> [String] {
            guard let list = node.first(of: .labelList) else { return [] }
            return list.children.map { child in
                if child.kind == .firstElementMarker { return "_" }
                return child.text ?? "_"
            }
        }

        // Hashable implies Equatable, but Swift still emits both conformances,
        // so we check them independently.
        //
        // `==` is the Swift operator name and is uniquely reserved for
        // Equatable-shaped comparison at source level, so matching on name
        // alone is safe. The argument labels of `==` are always unnamed
        // (`_`, `_`) and the demangler elides the labelList in that case,
        // which is why we cannot gate on a `[_, _]` label shape here.
        if shortProtocolNames.contains("Equatable") || shortProtocolNames.contains("Hashable") {
            staticFunctions.removeAll { function in
                function.name == "=="
            }
        }

        if shortProtocolNames.contains("Hashable") {
            functions.removeAll { function in
                (function.name == "hash" && labels(of: function.node) == ["into"])
                    || (function.name == "_rawHashValue" && labels(of: function.node) == ["seed"])
            }
            variables.removeAll { variable in
                variable.name == "hashValue"
            }
        }

        if shortProtocolNames.contains("CaseIterable") {
            staticVariables.removeAll { variable in
                variable.name == "allCases"
            }
        }

        if shortProtocolNames.contains("RawRepresentable") {
            variables.removeAll { variable in
                variable.name == "rawValue"
            }
            // `init?(rawValue:)` can appear either as an allocator or a constructor
            // depending on whether the type has its metadata accessor.
            allocators.removeAll { function in
                labels(of: function.node) == ["rawValue"]
            }
            constructors.removeAll { function in
                labels(of: function.node) == ["rawValue"]
            }
        }

        if shortProtocolNames.contains("Encodable") || shortProtocolNames.contains("Codable") {
            functions.removeAll { function in
                function.name == "encode" && labels(of: function.node) == ["to"]
            }
        }

        if shortProtocolNames.contains("Decodable") || shortProtocolNames.contains("Codable") {
            allocators.removeAll { function in
                labels(of: function.node) == ["from"]
            }
            constructors.removeAll { function in
                labels(of: function.node) == ["from"]
            }
        }

        if shortProtocolNames.contains("CodingKey") {
            variables.removeAll { variable in
                variable.name == "stringValue" || variable.name == "intValue"
            }
            allocators.removeAll { function in
                labels(of: function.node) == ["stringValue"] || labels(of: function.node) == ["intValue"]
            }
            constructors.removeAll { function in
                labels(of: function.node) == ["stringValue"] || labels(of: function.node) == ["intValue"]
            }
        }
    }
}
