import Foundation
import SwiftDeclaration
import MachOSwiftSection
import MachOKit
import Demangling
import FoundationToolbox
import AssociatedObject
@_spi(Internals) import SwiftInspection

/// Runtime generic-specialization behavior grafted onto the base
/// `TypeDefinition` model.
///
/// `TypeDefinition` itself (in `SwiftDeclaration`) only retains `isSpecialized`
/// — the flag that says *whether* a definition is a specialization — plus the
/// runtime `metadata` it carries. Everything that *produces* specializations
/// lives here in `SwiftSpecialization`, so the base model stays free of the
/// runtime metadata machinery. The accumulated `specializedChildren` are held
/// via an associated object because a cross-module extension cannot add stored
/// instance properties to a type it does not own.
extension TypeDefinition {
    /// Associated-object backing for `specializedChildren`. Mutated only
    /// within this file (the `specialize(...)` family appends to it).
    @AssociatedObject(.retain(.nonatomic))
    private var _specializedChildren: [TypeDefinition] = []

    /// Specialized children produced by **directly** calling
    /// `specialize(with:in:)` (or the `derivingNestedSpecializationsWith`
    /// overload) on this generic definition. Each entry is a sibling-shaped
    /// `TypeDefinition` that wraps the same `type` but carries a
    /// runtime-resolved metadata. Held as an associated object on the model
    /// rather than on the indexer so the indexer remains agnostic of
    /// user-driven specialization state.
    ///
    /// **Asymmetry to watch for** — `specialize(...derivingNestedSpecializationsWith:...)`
    /// auto-derives nested specialized children for the receiver's
    /// `typeChildren` and attaches them to `specialized.typeChildren`, but
    /// **does not** append them to the *generic nested child's*
    /// `specializedChildren`. The reasoning:
    ///
    /// 1. `specializedChildren` is the canonical inventory of
    ///    *user-initiated* specializations of a given generic definition.
    ///    Outer-driven derivation is a side effect of a user request on the
    ///    outer type; folding those into the nested type's
    ///    `specializedChildren` would mix two intent levels and break the
    ///    "manual specializations live exactly where the user put them"
    ///    contract that `GenericTypeNameSubstitutionTests
    ///    .outerSpecializationDerivesNestedChildSpecializationsWithoutMovingExistingChildSpecializations`
    ///    pins.
    /// 2. The same derived `Value<Int>` is reachable from the outer entry
    ///    via `outerDef.specializedChildren.flatMap(\.typeChildren)`, so no
    ///    information is lost — only the entry point differs.
    ///
    /// Callers that need "every `TypeDefinition` instance specialized to
    /// the same generic type" must walk both:
    ///
    /// ```swift
    /// let manual    = nestedDef.specializedChildren
    /// let viaOuter  = outerDef.specializedChildren.flatMap { outerInstance in
    ///     outerInstance.typeChildren.filter { $0.type === nestedDef.type }
    /// }
    /// ```
    ///
    /// **No deduplication** — calling `specialize(...)` twice on the same
    /// generic definition with identical selections produces two distinct
    /// `TypeDefinition` entries here (and, for the deriving overload, two
    /// independent subtrees in `outerSpecialized.typeChildren`). Equality
    /// of `metadata` does not imply identity of the wrapping
    /// `TypeDefinition`.
    public var specializedChildren: [TypeDefinition] { _specializedChildren }

    /// Maximum recursion depth that `deriveNestedSpecializedTypeChildren`
    /// will descend before bailing out. Swift's source-level nesting rarely
    /// exceeds 3-4 layers in practice, so 16 is a deliberately generous
    /// bound that catches runaway recursion (pathological self-referencing
    /// descriptors, mutually-recursive nested types) without ever clipping
    /// legitimate nesting. Hitting it is a diagnostic event, not a normal
    /// outcome: the `logger` below (subsystem
    /// `com.machoswiftsection.swift-interface`, category
    /// `TypeDefinition.nestedSpecialization`) carries the warning emitted
    /// when the guard trips.
    ///
    /// SPI-exposed so the regression test that pins this invariant can
    /// read it without `@testable`.
    @_spi(Support)
    public static let nestedSpecializationDepthLimit = 16

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
    ///
    /// This overload specializes **only the receiver**. The returned
    /// definition's `typeChildren` is left empty — callers that want the
    /// nested types specialized too must either call this overload again
    /// per nested child, or use
    /// `specialize(with:typeArgumentNodes:derivingNestedSpecializationsWith:selection:typeArgumentNodesByParameter:in:)`,
    /// which auto-derives nested specialized children from the same outer
    /// binding.
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
        _specializedChildren.append(specialized)
        return specialized
    }

    /// Specialize the receiver **and** derive specialized nested children
    /// for every member of `typeChildren` that can be bound from
    /// `selection`. Returns the outer specialized definition; derived
    /// nested children are attached to its `typeChildren`.
    ///
    /// Effect on each property:
    /// - `self.specializedChildren` — appends the outer specialized
    ///   instance (same as the basic `specialize(with:in:)` overload).
    /// - `outerSpecialized.typeChildren` — assigned (not appended) to the
    ///   list of derived nested specialized children. Each derived child's
    ///   `parent` is set to `outerSpecialized`.
    /// - **No change** to any generic nested child's `specializedChildren`.
    ///   Derived nested children are reachable only via
    ///   `outerSpecialized.typeChildren` — folding them into the canonical
    ///   nested generic def's `specializedChildren` would break the
    ///   "manual specializations live exactly where the user put them"
    ///   contract. See the `specializedChildren` doc for the cross-cutting
    ///   discussion and the recommended dual-walk for callers that need
    ///   the full inventory.
    ///
    /// Derivation is **best-effort**: a single nested child whose own
    /// `specialize` throws (missing PWT, descriptor mismatch, layout
    /// constraint rejection, …) is silently dropped from the derived
    /// subtree; the rest still arrive. Nested children that introduce
    /// their own generic parameters not covered by `selection` are also
    /// skipped (the outer binding alone can't construct their key
    /// arguments). The recursion is bounded by
    /// `nestedSpecializationDepthLimit`; hitting it logs an `os_log`
    /// warning under the `com.machoswiftsection.swift-interface` subsystem
    /// and truncates the subtree.
    @_spi(Support)
    @discardableResult
    public func specialize(
        with specializationResult: SpecializationResult,
        typeArgumentNodes: [Node]? = nil,
        derivingNestedSpecializationsWith specializer: some NestedSpecializing,
        selection: SpecializationSelection,
        typeArgumentNodesByParameter: [String: Node],
        in machO: MachOImage
    ) async throws -> TypeDefinition {
        let specialized = try makeSpecializedDefinition(
            with: specializationResult,
            typeArgumentNodes: typeArgumentNodes,
            in: machO
        )
        specialized.typeChildren = await deriveNestedSpecializedTypeChildren(
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
        _specializedChildren.append(specialized)
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
        using specializer: some NestedSpecializing,
        selection: SpecializationSelection,
        typeArgumentNodesByParameter: [String: Node],
        inheritedTypeArgumentNodes: [Node],
        in machO: MachOImage,
        depth: Int
    ) async -> [TypeDefinition] {
        guard depth < Self.nestedSpecializationDepthLimit else {
            #log(.info, "deriveNestedSpecializedTypeChildren reached nested specialization depth limit \(Self.nestedSpecializationDepthLimit, privacy: .public) — truncating subtree at \(self.typeName.name, privacy: .public)")
            return []
        }

        var derivedChildren: [TypeDefinition] = []
        for child in typeChildren {
            guard child.type.typeContextDescriptorWrapper.typeContextDescriptor.layout.flags.isGeneric else {
                continue
            }

            // Best-effort: a single nested child whose specialization
            // fails (missing PWT, descriptor identity mismatch, malformed
            // metadata accessor argument shape, …) must not abort the
            // whole outer derivation. The outer specialized definition is
            // still returned with whatever siblings *did* succeed, so a
            // partial sidebar tree beats a missing one.
            do {
                let request = try specializer.makeRequest(for: child.type.typeContextDescriptorWrapper, candidateOptions: .default)
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
                let childResult = try specializer.specialize(request, with: childSelection, metadataRequest: .completeAndBlocking)
                let effectiveChildArgumentNodes = childArgumentNodes.isEmpty
                    ? inheritedTypeArgumentNodes
                    : childArgumentNodes
                let childSpecialized = try child.makeSpecializedDefinition(
                    with: childResult,
                    typeArgumentNodes: effectiveChildArgumentNodes,
                    in: machO
                )
                childSpecialized.typeChildren = await child.deriveNestedSpecializedTypeChildren(
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
            } catch {
                continue
            }
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
    /// `package` access so unit tests in `SwiftSpecializationTests` can
    /// exercise the substitution shape without spinning up a full MachO
    /// fixture.
    package static func boundGenericTypeName(
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
}

/// Provides the `os.Logger` / `os_log` backing for the nested-specialization
/// depth-limit diagnostic. `@Loggable` on a protocol synthesizes the
/// `logger`/`_osLog` members — including the `#available(macOS 11.0, …)`
/// fallback to `os_log` on older systems — so the `#log` site inside
/// `deriveNestedSpecializedTypeChildren` resolves through `TypeDefinition`'s
/// conformance below. Carried here, in `SwiftSpecialization`, rather than via
/// an `@Loggable` on the base `TypeDefinition` class so the base model stays
/// free of the specialization-only logging scaffolding.
@Loggable(.internal, subsystem: "com.machoswiftsection.swift-interface", category: "TypeDefinition.nestedSpecialization")
protocol NestedSpecializationLogging {}

extension TypeDefinition: NestedSpecializationLogging {}
