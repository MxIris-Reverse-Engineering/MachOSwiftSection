@_spi(Support) import SwiftIndexing
import SwiftDeclaration
import Foundation
import MachOSwiftSection
import MachOKit
import Demangling
import OrderedCollections
@_spi(Internals) import SwiftInspection

// MARK: - GenericSpecializer

/// Specializer for generic Swift types.
///
/// Provides an interactive API for specializing generic types:
/// 1. Call `makeRequest(for:)` to get parameters and candidate types.
/// 2. User selects concrete types for each parameter.
/// 3. Call `specialize(_:with:)` to execute specialization.
///
/// **MachO mode requirement.** `specialize(_:with:)`,
/// `runtimePreflight(selection:for:)`, and `resolveAssociatedTypeWitnesses`
/// are only available when `MachO == MachOImage` — they invoke runtime
/// metadata accessors (`swift_getGenericMetadata`,
/// `swift_conformsToProtocol`, `swift_getAssociatedTypeWitness`) which
/// require the type's image to be currently loaded into the running
/// process. `makeRequest(for:)` and `validate(selection:for:)` work for
/// any `MachO` — non-image specializers can still inspect parameters,
/// requirements, and candidate lists; they just cannot resolve metadata.
@_spi(Support)
public final class GenericSpecializer<MachO: MachOSwiftSectionRepresentableWithCache>: @unchecked Sendable {

    /// The MachO file/image containing the types
    public let machO: MachO

    /// Provider for type conformance information
    public let conformanceProvider: any ConformanceProvider

    /// Indexer for accessing protocol definitions (needed for associated type resolution).
    ///
    /// Internal visibility — `.boundGeneric` recursion in
    /// `makeInnerContext` forwards this into an inner specializer via
    /// `init(machO:conformanceProvider:indexer:)`. Do not access from
    /// outside the module; the property is not part of the SPI surface.
    let indexer: SwiftDeclarationIndexer<MachO>?

    /// Soft guard against runaway recursion from `Argument.boundGeneric`
    /// chains. Defaults to 16 — Swift's own tooling rarely produces
    /// well-formed generic nestings beyond a handful of levels, so this
    /// is a generous ceiling. Exceeding it produces
    /// `SpecializerError.specializationFailed(reason:)` instead of
    /// running into stack-bound limits.
    public var maxBindingDepth: Int = 16

    /// Initialize with an indexer (recommended)
    public init(indexer: SwiftDeclarationIndexer<MachO>) {
        self.machO = indexer.machO
        self.conformanceProvider = IndexerConformanceProvider(indexer: indexer)
        self.indexer = indexer
    }

    /// Initialize with MachO and custom conformance provider
    public init(machO: MachO, conformanceProvider: any ConformanceProvider, indexer: SwiftDeclarationIndexer<MachO>? = nil) {
        self.machO = machO
        self.conformanceProvider = conformanceProvider
        self.indexer = indexer
    }
}

// MARK: - Request Creation

@_spi(Support)
extension GenericSpecializer {

    /// Create a specialization request for a generic type
    ///
    /// - Parameters:
    ///   - type: The generic type descriptor.
    ///   - candidateOptions: Filter knobs for the per-parameter candidate
    ///     lists (e.g. `.excludeGenerics` to drop candidates whose own
    ///     descriptor is generic).
    /// - Returns: A request containing parameters, requirements, and candidate types
    /// - Throws: If the type is not generic or cannot be analyzed
    public func makeRequest(
        for type: TypeContextDescriptorWrapper,
        candidateOptions: SpecializationRequest.CandidateOptions = .default
    ) throws -> SpecializationRequest {
        let genericContext = try genericContext(for: type)

        // Reject TypePack / Value generic parameters up front — we do not
        // implement variadic generics or value generics yet, and silently
        // skipping them in `buildParameters` would surface as a metadata-
        // accessor argument-count mismatch deep inside `specialize()`.
        if let unsupportedParameter = genericContext.parameters.first(where: { $0.kind == .typePack || $0.kind == .value }) {
            throw SpecializerError.unsupportedGenericParameter(parameterKind: unsupportedParameter.kind)
        }

        // Build parameters from generic context
        let parameters = try buildParameters(from: genericContext, for: type, candidateOptions: candidateOptions)

        // Build associated type requirements
        let associatedTypeRequirements = try buildAssociatedTypeRequirements(from: genericContext, for: type)

        return SpecializationRequest(
            typeDescriptor: type,
            parameters: parameters,
            associatedTypeRequirements: associatedTypeRequirements,
            keyArgumentCount: Int(genericContext.header.numKeyArguments)
        )
    }

    /// Get generic context for a type descriptor
    private func genericContext(for type: TypeContextDescriptorWrapper) throws -> GenericContext {
        guard let genericContext = try type.genericContext(in: machO) else {
            throw SpecializerError.notGenericType(type: type)
        }
        return genericContext
    }

    /// All requirements visible to the specializer.
    ///
    /// `genericContext.requirements` is already cumulative — Swift's
    /// `sig->getRequirementsWithInverses` covers every requirement in scope,
    /// including those inherited from parent generic contexts (see
    /// `swift/lib/IRGen/GenMeta.cpp:7342`). Re-flattening `allRequirements`
    /// here would reintroduce the cumulative parent levels and double-count
    /// inherited requirements at depth ≥ 2.
    ///
    /// Conditional requirements live in their own section (see
    /// `addConditionalInvertedProtocols` at `GenMeta.cpp:1381`) and describe
    /// the `where` clauses of `extension X: Copyable / Escapable` style
    /// conformances. The section is written via
    /// `addGenericRequirements(genericSig, conformance->getConditionalRequirements(), inverses)`,
    /// so it can carry both:
    ///   - `.protocol` records — but `inverse_cannot_be_conditional_on_requirement`
    ///     (`DiagnosticsSema.def:8200`, enforced at `TypeCheckInvertible.cpp:198`)
    ///     restricts these to direct-GP `: thisInvertibleProtocol`, i.e. only
    ///     marker invertibles (`Copyable` / `Escapable` / `BitwiseCopyable`)
    ///     with `hasKeyArgument == false`.
    ///   - `.invertedProtocols` records — for any inverses in the conditional
    ///     context.
    /// `collectInvertibleProtocols` is the only consumer that cares about the
    /// `.invertedProtocols` half. The other consumers
    /// (`collectRequirements`, `buildAssociatedTypeRequirements`,
    /// `resolveAssociatedTypeWitnesses`) ignore `.invertedProtocols` by kind
    /// and additionally drop marker `.protocol` records via the
    /// `hasKeyArgument` filter (`collectRequirements` line 266–269 / the
    /// `flags.contains(.hasKeyArgument)` guard in
    /// `resolveAssociatedTypeWitnesses`), so merging conditional records here
    /// is free of side effects on PWT counts.
    private static func mergedRequirements(
        from genericContext: GenericContext
    ) -> [GenericRequirementDescriptor] {
        genericContext.requirements
            + genericContext.conditionalInvertibleProtocolsRequirements
    }

    /// Per-level "newly introduced" parameter counts.
    ///
    /// `parentParameters[i]` stores the *cumulative* count visible at depth
    /// `i` (Swift emits the full canonical parameter list at every nested
    /// scope). Differencing successive entries yields the count of
    /// parameters added at each depth; `currentParameters` already contains
    /// only the new entries at the innermost scope.
    private static func perLevelNewParameterCounts(
        of genericContext: GenericContext
    ) -> [Int] {
        var counts: [Int] = []
        var previous = 0
        for parentCumulative in genericContext.parentParameters {
            counts.append(parentCumulative.count - previous)
            previous = parentCumulative.count
        }
        counts.append(genericContext.currentParameters.count)
        return counts
    }

    /// Pick out the `~Copyable` / `~Escapable` declaration for the generic
    /// parameter at the given flat ordinal, unioning if multiple
    /// `invertedProtocols` requirements target the same parameter.
    /// Returns `nil` when no requirement targets this parameter.
    ///
    /// `flatIndex` is the parameter's absolute position in the cumulative
    /// `genericContext.parameters` array — exactly the value
    /// `sig->getGenericParamOrdinal(genericParam)` writes into the binary
    /// (see `swift/lib/IRGen/GenMeta.cpp:7499`).
    ///
    /// Aggregation is union, matching IRGen's `suppressed[index].insert(...)`.
    private static func collectInvertibleProtocols(
        flatIndex: Int,
        in genericContext: GenericContext
    ) -> InvertibleProtocolSet? {
        let target = UInt16(flatIndex)
        var result: InvertibleProtocolSet?
        for descriptor in mergedRequirements(from: genericContext)
        where descriptor.layout.flags.kind == .invertedProtocols {
            guard case .invertedProtocols(let inverted) = descriptor.content else { continue }
            guard inverted.genericParamIndex == target else { continue }

            if let existing = result {
                result = existing.union(inverted.protocols)
            } else {
                result = inverted.protocols
            }
        }
        return result
    }

    /// Build parameter list from generic context.
    ///
    /// Walks the cumulative `parameters` array level by level using the
    /// per-depth "newly introduced" counts, so each parameter receives the
    /// `(depth, indexInLevel)` pair that matches the demangler's canonical
    /// names (`A`, `B`, `A1`, `B1`, `A2`, …). The flat ordinal of each
    /// parameter — the value Swift writes into `InvertedProtocols.genericParamIndex`
    /// — equals the offset into the cumulative array.
    private func buildParameters(
        from genericContext: GenericContext,
        for type: TypeContextDescriptorWrapper,
        candidateOptions: SpecializationRequest.CandidateOptions
    ) throws -> [SpecializationRequest.Parameter] {
        var parameters: [SpecializationRequest.Parameter] = []

        let cumulativeParameters = genericContext.parameters
        let perLevelNewCounts = Self.perLevelNewParameterCounts(of: genericContext)
        let mergedRequirements = Self.mergedRequirements(from: genericContext)

        var paramOffset = 0
        for (depth, newCount) in perLevelNewCounts.enumerated() {
            for indexInLevel in 0..<newCount {
                let flatIndex = paramOffset + indexInLevel
                let param = cumulativeParameters[flatIndex]

                // Skip non-key parameters (type packs, values, etc.)
                guard param.hasKeyArgument, param.kind == .type else { continue }

                // Get parameter name based on depth and per-level index
                // (e.g., A, B, A1, B1, A2...).
                let paramName = genericParameterName(depth: depth.cast(), index: indexInLevel.cast())

                // Collect requirements for this parameter (ordered for PWT passing)
                let requirements = try collectRequirements(
                    for: paramName,
                    from: mergedRequirements
                )

                // Find candidate types that satisfy all protocol requirements
                let protocolRequirements = requirements.compactMap { requirement -> ProtocolName? in
                    if case .protocol(let info) = requirement {
                        return info.protocolName
                    }
                    return nil
                }

                // Pull the baseClass requirement (at most one per GP — Swift
                // does not allow more than one inheritance constraint) and
                // turn its demangled RHS into a `TypeName` so the provider
                // can return base-class + subclass list. sameType is
                // intentionally *not* converted into a candidate filter:
                // its candidate set is genuinely user-determined and can
                // span any type, the validate / preflight pass enforces
                // consistency.
                let baseClassConstraint = Self.baseClassConstraintTypeName(in: requirements)

                let candidates = findCandidates(
                    satisfying: protocolRequirements,
                    boundedBy: baseClassConstraint,
                    options: candidateOptions
                )

                let invertibleProtocols = Self.collectInvertibleProtocols(
                    flatIndex: flatIndex,
                    in: genericContext
                )

                parameters.append(SpecializationRequest.Parameter(
                    name: paramName,
                    index: indexInLevel,
                    depth: depth,
                    requirements: requirements,
                    candidates: candidates,
                    invertibleProtocols: invertibleProtocols
                ))
            }
            paramOffset += newCount
        }

        return parameters
    }

    /// Collect requirements for a specific parameter (ordered for PWT passing)
    private func collectRequirements(
        for paramName: String,
        from genericRequirements: [GenericRequirementDescriptor]
    ) throws -> [SpecializationRequest.Requirement] {
        var requirements: [SpecializationRequest.Requirement] = []

        for genericRequirement in genericRequirements {
            // Get the mangled param name and demangle it
            let mangledParamName = try genericRequirement.paramMangledName(in: machO)
            let paramNode = try MetadataReader.demangleType(for: mangledParamName, in: machO)

            // The requirement applies to this parameter only if its LHS is the
            // generic parameter directly (not an associated-type reference like A.Element).
            guard let directParamName = Self.directGenericParamName(of: paramNode),
                  directParamName == paramName else {
                continue
            }

            // ObjC-only protocol requirements have no key argument and no PWT;
            // skip them. Other kinds (layout/sameType/baseClass) have no key
            // argument either but should still be exposed for validation.
            if genericRequirement.flags.kind == .protocol,
               !genericRequirement.flags.contains(.hasKeyArgument) {
                continue
            }

            if let requirement = try buildRequirement(from: genericRequirement) {
                requirements.append(requirement)
            }
        }

        return requirements
    }

    /// Returns the parameter name when `paramNode` describes a direct generic
    /// parameter (e.g. `A`). Returns `nil` when the node is an associated-type
    /// reference such as `A.Element` or `A.Element.Element`.
    static func directGenericParamName(of paramNode: Node) -> String? {
        let typeNode = (paramNode.kind == .type) ? paramNode.firstChild : paramNode
        guard let typeNode, typeNode.kind == .dependentGenericParamType else { return nil }
        return typeNode.text
    }

    /// Parsed associated-type access path extracted from a demangled requirement
    /// LHS. The chain `A.Element.Element` produces `baseParamName == "A"` and
    /// `steps == [(Element, Sequence), (Element, Sequence)]` in source order.
    struct AssociatedPathInfo {
        let baseParamName: String
        let steps: [Step]

        struct Step {
            let name: String
            /// `Type` node wrapping the protocol that owns this associated type.
            let protocolNode: Node
        }
    }

    /// Walk a demangled `LHS` node and split it into the root generic parameter
    /// name plus the ordered chain of associated-type accesses. Returns `nil`
    /// when the structure does not match an `A` or `A.X.Y...` reference.
    ///
    /// The protocol child of each `DependentAssociatedTypeRef` may be one of
    /// three Demangler-emitted shapes (see
    /// `swift/lib/Demangling/Demangler.cpp:2832-2845` `popAssocTypeName`):
    ///   - `.type` (resolver wrapped a context tree — the common case);
    ///   - `.protocolSymbolicReference` (resolver returned `nil` for a Swift
    ///     protocol — image not loaded, recursion limit, etc.);
    ///   - `.objectiveCProtocolSymbolicReference` (same but for an Obj-C
    ///     protocol).
    /// We accept all three. Downstream resolution (`resolveAssociatedTypeStep`)
    /// may still fail when looking the protocol up in the indexer, but the
    /// parsing layer should not silently drop a structurally valid LHS.
    static func extractAssociatedPath(of paramNode: Node) -> AssociatedPathInfo? {
        var current: Node = paramNode
        if current.kind == .type, let inner = current.firstChild {
            current = inner
        }

        // The OUTERMOST DependentMemberType represents the LAST step; we
        // traverse outer→inner pushing each step, then reverse to get source order.
        var stepsOuterToInner: [AssociatedPathInfo.Step] = []

        while current.kind == .dependentMemberType {
            guard current.numberOfChildren >= 2 else { return nil }
            let baseTypeWrapper = current.children[0]
            let assocRef = current.children[1]
            guard assocRef.kind == .dependentAssociatedTypeRef,
                  assocRef.numberOfChildren >= 2,
                  let nameChild = assocRef.firstChild,
                  case .text(let stepName) = nameChild.contents else {
                return nil
            }
            let protocolNode = assocRef.children[1]
            switch protocolNode.kind {
            case .type,
                 .protocolSymbolicReference,
                 .objectiveCProtocolSymbolicReference:
                break
            default:
                return nil
            }
            stepsOuterToInner.append(.init(name: stepName, protocolNode: protocolNode))

            guard baseTypeWrapper.kind == .type, let baseInner = baseTypeWrapper.firstChild else {
                return nil
            }
            current = baseInner
        }

        guard current.kind == .dependentGenericParamType, let baseName = current.text else {
            return nil
        }
        return .init(baseParamName: baseName, steps: Array(stepsOuterToInner.reversed()))
    }

    /// Build a requirement from a requirement descriptor
    private func buildRequirement(from genericRequirement: GenericRequirementDescriptor) throws -> SpecializationRequest.Requirement? {
        let flags = genericRequirement.layout.flags

        switch flags.kind {
        case .protocol:
            let resolvedContent = try genericRequirement.resolvedContent(in: machO)
            guard case .protocol(let protocolRef) = resolvedContent,
                  let resolved = protocolRef.resolved else {
                return nil
            }

            // Try to get protocol name
            let protocolName: ProtocolName
            if let swiftProto = resolved.swift {
                let proto = try MachOSwiftSection.`Protocol`(descriptor: swiftProto, in: machO)
                protocolName = try proto.protocolName(in: machO)
            } else {
                return nil
            }

            return .protocol(SpecializationRequest.ProtocolRequirementInfo(
                protocolName: protocolName,
                requiresWitnessTable: flags.contains(.hasKeyArgument)
            ))

        case .sameType:
            let mangledTypeName = try genericRequirement.type(in: machO)
            let demangledTypeNode = try MetadataReader.demangleType(for: mangledTypeName, in: machO)
            return .sameType(demangledTypeNode: demangledTypeNode, mangledName: mangledTypeName)

        case .baseClass:
            let mangledTypeName = try genericRequirement.type(in: machO)
            let demangledTypeNode = try MetadataReader.demangleType(for: mangledTypeName, in: machO)
            return .baseClass(demangledTypeNode: demangledTypeNode, mangledName: mangledTypeName)

        case .layout:
            let resolvedContent = try genericRequirement.resolvedContent(in: machO)
            guard case .layout(let layoutKind) = resolvedContent else {
                return nil
            }
            switch layoutKind {
            case .class:
                return .layout(.class)
            }

        case .sameConformance:
            // Derived from SameType / BaseClass; compiler forces hasKeyArgument=false,
            // so it never participates in metadata accessor key arguments.
            return nil

        case .sameShape:
            // Pack-shape constraint between two TypePacks. Relevant only to variadic
            // generics, which are out of scope for this specializer.
            return nil

        case .invertedProtocols:
            // Capability declaration (~Copyable / ~Escapable) — surfaced on
            // Parameter.invertibleProtocols rather than as a Requirement, because
            // it relaxes rather than constrains the parameter.
            return nil
        }
    }

    /// Build associated type requirements (ordered for PWT passing).
    ///
    /// Multiple constraints on the same `A.X.Y...` path are aggregated into
    /// one `AssociatedTypeRequirement` whose `requirements` array preserves
    /// canonical (binary) order. Aggregating by `(parameterName, path)`
    /// matches the field's declared semantics — `requirements: [Requirement]`
    /// is plural for a reason — and keeps consumers from having to re-group
    /// duplicates themselves.
    private func buildAssociatedTypeRequirements(
        from genericContext: GenericContext,
        for type: TypeContextDescriptorWrapper
    ) throws -> [SpecializationRequest.AssociatedTypeRequirement] {
        var entriesByKey: [AssociatedTypeRequirementKey: [SpecializationRequest.Requirement]] = [:]
        var orderedKeys: [AssociatedTypeRequirementKey] = []
        let genericRequirements = Self.mergedRequirements(from: genericContext)

        for genericRequirement in genericRequirements {
            let mangledParamName = try genericRequirement.paramMangledName(in: machO)
            let paramNode = try MetadataReader.demangleType(for: mangledParamName, in: machO)

            // Only handle dependent-member chains here; direct GP requirements
            // are collected per parameter in `collectRequirements`.
            guard let pathInfo = Self.extractAssociatedPath(of: paramNode), !pathInfo.steps.isEmpty else {
                continue
            }

            guard let requirement = try buildRequirement(from: genericRequirement) else {
                continue
            }

            let key = AssociatedTypeRequirementKey(
                parameterName: pathInfo.baseParamName,
                path: pathInfo.steps.map(\.name)
            )
            if entriesByKey[key] == nil {
                orderedKeys.append(key)
            }
            entriesByKey[key, default: []].append(requirement)
        }

        return orderedKeys.map { key in
            SpecializationRequest.AssociatedTypeRequirement(
                parameterName: key.parameterName,
                path: key.path,
                requirements: entriesByKey[key] ?? []
            )
        }
    }

    /// Aggregation key for `buildAssociatedTypeRequirements` — a generic
    /// type can't host a nested struct directly inside a method body, so
    /// the key lives at extension scope.
    ///
    /// **Why no protocol identity in the key.** It would be tempting to
    /// also include each step's `protocolNode` in the key — guarding
    /// against the case where two unrelated protocols both declare the
    /// same-named associated type (`P.Element` vs `Q.Element`) and a
    /// generic parameter conforms to both. That case is **structurally
    /// impossible in a well-formed binary**: the Swift compiler's
    /// RequirementMachine runs a deterministic minimization pass
    /// (`swift/lib/AST/RequirementMachine/MinimalConformances.cpp` +
    /// `HomotopyReduction.cpp`, invoked from `getMinimalGenericSignature`)
    /// before any descriptor is emitted, and that pass collapses every
    /// `A.[P:Element]` / `A.[Q:Element]` reference to a single canonical
    /// rooted form. The choice is fixed by `compareDependentTypesRec`
    /// (`swift/lib/AST/GenericSignature.cpp:846`) — empirically the
    /// lexicographically earlier protocol — and is part of type
    /// checking, not an opt-in optimization.
    ///
    /// `dualProtocolSameNamedAssociatedTypeIsCanonicalized` in the
    /// test suite exists as a belt-and-suspenders pin on this upstream
    /// invariant. So long as that test stands, dropping `protocolNode`
    /// from the aggregation key is safe — a future code reader noticing
    /// the omission can stop here rather than re-investigating.
    private struct AssociatedTypeRequirementKey: Hashable {
        let parameterName: String
        let path: [String]
    }

    /// Find candidate types that satisfy all protocol constraints,
    /// optionally narrowed to a base-class subtree.
    ///
    /// Generic candidates are included by default but flagged via
    /// `Candidate.isGeneric`; selecting one via `Argument.candidate` would
    /// throw `candidateRequiresNestedSpecialization` from `specialize`. Pass
    /// `candidateOptions: .excludeGenerics` to skip them up front when the
    /// caller wants a "directly-specializable" list.
    ///
    /// `boundedBy` carries the demangled RHS of a `<T: BaseClass>`
    /// requirement. When supplied **and** the conformance provider can
    /// answer `subclasses(of:)` (e.g. `IndexerConformanceProvider`), the
    /// candidate list is intersected with `BaseClass + every subclass`,
    /// stripping out unrelated types up front. If the provider returns an
    /// empty subclass list we treat that as "unknown" (rather than "no
    /// matches") and fall back to the protocol-only set, so providers
    /// without class-hierarchy data degrade gracefully instead of
    /// disappearing the candidates entirely.
    private func findCandidates(
        satisfying protocols: [ProtocolName],
        boundedBy baseClass: TypeName? = nil,
        options: SpecializationRequest.CandidateOptions = .default
    ) -> [SpecializationRequest.Candidate] {
        let protocolFiltered: [TypeName]
        if protocols.isEmpty {
            protocolFiltered = conformanceProvider.allTypeNames
        } else {
            protocolFiltered = conformanceProvider.types(conformingToAll: protocols)
        }

        let typeNames: [TypeName]
        if let baseClass {
            let subclassList = conformanceProvider.subclasses(of: baseClass)
            if subclassList.isEmpty {
                // Provider has no class-hierarchy info — keep the
                // pre-baseClass behaviour (do not narrow).
                typeNames = protocolFiltered
            } else {
                let allowed = Set(subclassList)
                typeNames = protocolFiltered.filter { allowed.contains($0) }
            }
        } else {
            typeNames = protocolFiltered
        }

        return typeNames.compactMap { typeName -> SpecializationRequest.Candidate? in
            guard let typeDefinition = conformanceProvider.typeDefinition(for: typeName) else {
                return nil
            }
            let isGeneric = typeDefinition.type.typeContextDescriptorWrapper.typeContextDescriptor.layout.flags.isGeneric
            if options.contains(.excludeGenerics), isGeneric {
                return nil
            }
            let imagePath = conformanceProvider.imagePath(for: typeName) ?? ""
            return SpecializationRequest.Candidate(
                typeName: typeName,
                source: .image(imagePath),
                isGeneric: isGeneric
            )
        }
    }

    /// Returns the demangled RHS of the (at most one) `.baseClass`
    /// requirement on a parameter, packaged as a `TypeName` ready for
    /// `ConformanceProvider.subclasses(of:)`. Returns nil when the
    /// parameter has no baseClass constraint.
    ///
    /// `kind` is hardcoded to `.class` rather than derived from
    /// `Node.typeKind`. The latter scans the entire subtree and matches
    /// the *first* of `.enum`/`.structure`/`.class` it finds, which means
    /// a class nested inside a struct (`Outer.InnerClass`) is mis-tagged
    /// as `.struct`. baseClass requirements only ever resolve to a class
    /// at the binary level (Swift rejects `<T: SomeStruct>` in Sema), so
    /// we can safely commit to the correct kind without inspecting the
    /// node — and dodging `Node.typeKind` makes nested class hierarchies
    /// (like the test fixtures) work.
    static func baseClassConstraintTypeName(
        in requirements: [SpecializationRequest.Requirement]
    ) -> TypeName? {
        for requirement in requirements {
            guard case .baseClass(let demangledNode, _) = requirement else { continue }
            let typeNode = demangledNode.first(of: .type) ?? demangledNode
            return TypeName(node: typeNode, kind: .class)
        }
        return nil
    }

    /// Look up a candidate's `TypeContextDescriptorWrapper` and the image
    /// that hosts it. Used by both the bare `.candidate` resolution path
    /// (non-generic accessor call) and the `.boundGeneric` recursion path
    /// (descriptor feeds an inner `makeRequest`). Throws
    /// `SpecializerError.candidateResolutionFailed` when the indexer is
    /// missing or doesn't know about the type.
    func resolveCandidateDescriptor(
        _ candidate: SpecializationRequest.Candidate
    ) throws -> (descriptor: TypeContextDescriptorWrapper, machO: MachO) {
        guard let indexer else {
            throw SpecializerError.candidateResolutionFailed(
                candidate: candidate,
                reason: "Indexer not available for candidate resolution"
            )
        }
        guard let typeDefinitionEntry = indexer.allAllTypeDefinitions[candidate.typeName] else {
            throw SpecializerError.candidateResolutionFailed(
                candidate: candidate,
                reason: "Type not found in indexer"
            )
        }
        return (typeDefinitionEntry.value.type.typeContextDescriptorWrapper, typeDefinitionEntry.machO)
    }

    /// Build the descriptor + inner specializer pair that drives
    /// `.boundGeneric` recursion. The inner specializer is bound to the
    /// candidate's defining image (so `makeRequest`'s `genericContext(in:)`
    /// resolves descriptor offsets against the right Mach-O) and shares
    /// the outer's conformance provider, indexer, and `maxBindingDepth`.
    func makeInnerContext(
        for candidate: SpecializationRequest.Candidate
    ) throws -> (descriptor: TypeContextDescriptorWrapper, specializer: GenericSpecializer<MachO>) {
        let (descriptor, innerMachO) = try resolveCandidateDescriptor(candidate)
        let innerSpecializer = GenericSpecializer(
            machO: innerMachO,
            conformanceProvider: conformanceProvider,
            indexer: indexer
        )
        innerSpecializer.maxBindingDepth = maxBindingDepth
        return (descriptor, innerSpecializer)
    }
}

// MARK: - Validation

@_spi(Support)
extension GenericSpecializer {

    /// Validate a selection against a request — *static* checks only.
    ///
    /// Reports the cheap, runtime-free issues:
    ///   - missing parameter arguments (error)
    ///   - extra arguments not declared by the request (warning)
    ///
    /// Deliberately does *not* preempt `Argument.candidate` selections
    /// flagged `isGeneric`: the existing `specialize` contract is to
    /// throw a typed `SpecializerError.candidateRequiresNestedSpecialization`
    /// at the candidate-resolution site, and downstream callers depend
    /// on that error path. Use the request's `Candidate.isGeneric` flag
    /// or the `excludeGenerics` candidate option if you want to filter
    /// these earlier.
    ///
    /// For deeper protocol-conformance / layout checks against the
    /// concrete metadata, call `runtimePreflight(selection:for:)` (only
    /// available when `MachO == MachOImage`). `specialize` automatically
    /// folds both validations together.
    public func validate(selection: SpecializationSelection, for request: SpecializationRequest) -> SpecializationValidation {
        internalValidate(selection: selection, for: request, parameterPathPrefix: "", depth: 0)
    }

    /// Depth + dotted-path-aware validate. Public `validate` enters with
    /// an empty prefix and `depth = 0`; `.boundGeneric` recursion forwards
    /// a `<outer>` prefix and `depth + 1` so nested errors / warnings are
    /// reported at their flat dotted parameter paths and the recursion is
    /// bounded by `maxBindingDepth`.
    func internalValidate(
        selection: SpecializationSelection,
        for request: SpecializationRequest,
        parameterPathPrefix: String,
        depth: Int
    ) -> SpecializationValidation {
        let builder = SpecializationValidation.builder()

        for parameter in request.parameters {
            guard selection.hasArgument(for: parameter.name) else {
                builder.addError(.missingArgument(parameterName: Self.joinedPath(parameterPathPrefix, parameter.name)))
                continue
            }
        }

        let associatedTypePaths = Set(request.associatedTypeRequirements.map(\.fullPath))

        for paramName in selection.selectedParameterNames {
            if request.parameters.contains(where: { $0.name == paramName }) {
                continue
            }
            // Distinguish "user typed an associated-type access path" from
            // "user typed a wrong/typo'd key": the former is a structurally
            // recognizable mistake (associated types are derived during
            // specialization) and deserves a more actionable warning.
            if associatedTypePaths.contains(paramName) {
                builder.addWarning(.associatedTypePathInSelection(path: Self.joinedPath(parameterPathPrefix, paramName)))
            } else {
                builder.addWarning(.extraArgument(parameterName: Self.joinedPath(parameterPathPrefix, paramName)))
            }
        }

        // Recurse into `.boundGeneric` selections so inner-request errors
        // surface with dotted parameter paths against the same builder.
        for parameter in request.parameters {
            guard let argument = selection[parameter.name],
                  case .boundGeneric(let baseCandidate, let innerArguments) = argument else {
                continue
            }
            let outerPath = Self.joinedPath(parameterPathPrefix, parameter.name)
            if depth >= maxBindingDepth {
                builder.addError(.metadataResolutionFailed(
                    parameterName: outerPath,
                    reason: "binding depth exceeded (maxBindingDepth = \(maxBindingDepth))"
                ))
                continue
            }
            do {
                let inner = try makeInnerContext(for: baseCandidate)
                let innerRequest = try inner.specializer.makeRequest(for: inner.descriptor)
                let innerSelection = SpecializationSelection(arguments: innerArguments)
                let innerValidation = inner.specializer.internalValidate(
                    selection: innerSelection,
                    for: innerRequest,
                    parameterPathPrefix: outerPath,
                    depth: depth + 1
                )
                innerValidation.errors.forEach { builder.addError($0) }
                innerValidation.warnings.forEach { builder.addWarning($0) }
            } catch {
                builder.addError(.metadataResolutionFailed(
                    parameterName: outerPath,
                    reason: "could not build inner request: \(error)"
                ))
            }
        }

        return builder.build()
    }

    /// Join an outer parameter path prefix with an inner parameter name
    /// using `.` as the separator. Empty prefixes yield the inner name
    /// untouched so top-level errors continue to read as before.
    static func joinedPath(_ prefix: String, _ name: String) -> String {
        prefix.isEmpty ? name : "\(prefix).\(name)"
    }

}

// MARK: - Runtime Preflight

@_spi(Support)
extension GenericSpecializer where MachO == MachOImage {

    /// Runtime-aware companion to `validate(selection:for:)`.
    ///
    /// Performs the checks that need an actual `Metadata`:
    ///   - **Protocol requirements**: every direct-GP `protocol` requirement
    ///     is exercised via `swift_conformsToProtocol`. A `nil` result becomes
    ///     `protocolRequirementNotSatisfied` instead of letting it surface
    ///     mid-`specialize` as `witnessTableNotFound`.
    ///   - **Layout (`AnyObject`) requirements**: the resolved metadata kind
    ///     must be class-like (`.class` / `.objcClassWrapper` / `.foreignClass`).
    ///
    /// Same-type / base-class / associated-type checks are intentionally
    /// out of scope — they require either type-equality or chain walking
    /// that we'd rather perform once inside `specialize`. Failures there
    /// continue to bubble up via their typed errors.
    ///
    /// Argument-kind handling:
    ///   - `.metatype` / `.metadata` / `.specialized` are validated. The
    ///     `.specialized` case already carries a resolved metadata pointer
    ///     in the `SpecializationResult`, so it's just as cheap as the
    ///     direct cases.
    ///   - `.candidate` is skipped (its concrete metadata requires running
    ///     the candidate's own metadata accessor; `specialize` validates it
    ///     implicitly via the lookup path).
    ///
    /// When the indexer doesn't have a definition for a protocol referenced
    /// by a requirement, the corresponding conformance check cannot be run.
    /// In that case the function emits a `.protocolNotInIndexer` warning
    /// (instead of silently skipping) so callers know validation is
    /// incomplete and which sub-indexer is missing.
    public func runtimePreflight(
        selection: SpecializationSelection,
        for request: SpecializationRequest
    ) -> SpecializationValidation {
        internalRuntimePreflight(
            selection: selection,
            for: request,
            parameterPathPrefix: "",
            depth: 0
        )
    }

    /// Depth + dotted-path-aware runtime preflight. Public
    /// `runtimePreflight` enters with an empty prefix and `depth = 0`;
    /// `.boundGeneric` recursion forwards `<outer>` as the prefix and
    /// `depth + 1` so nested inner specializations are bounded by
    /// `maxBindingDepth` and produce errors / warnings whose parameter
    /// names read as flat dotted paths against the same outer builder.
    func internalRuntimePreflight(
        selection: SpecializationSelection,
        for request: SpecializationRequest,
        parameterPathPrefix: String,
        depth: Int
    ) -> SpecializationValidation {
        let builder = SpecializationValidation.builder()

        // Pre-pass: resolve every non-candidate parameter's metadata in one
        // place so the main pass can index by parameter name. The shared
        // map is what enables the GP-vs-GP shape of `sameType` validation —
        // when a `where A == B` requirement targets parameter `A`, the
        // check needs to compare `A`'s selected metadata against `B`'s.
        var metadataByName: [String: Metadata] = [:]
        for parameter in request.parameters {
            guard let argument = selection[parameter.name] else { continue }
            let outerPath = Self.joinedPath(parameterPathPrefix, parameter.name)

            switch argument {
            case .metatype(let type):
                // `specialize` runs the same `Metadata.createInProcess`
                // call, so a failure here will also break the accessor
                // call. Surface it now as a typed error rather than a
                // silent skip — the caller's selection is unusable.
                do {
                    metadataByName[parameter.name] = try Metadata.createInProcess(type)
                } catch {
                    builder.addError(.metadataResolutionFailed(
                        parameterName: outerPath,
                        reason: "\(error)"
                    ))
                }
            case .metadata(let provided):
                metadataByName[parameter.name] = provided
            case .specialized(let result):
                // `SpecializationResult` already carries a resolved metadata
                // pointer — no accessor call needed; preflight should
                // exercise the same checks it does for `.metatype`. A
                // failure here means the supplied result is corrupt and
                // `specialize` will fail the same way; report as an error.
                do {
                    metadataByName[parameter.name] = try result.metadata()
                } catch {
                    builder.addError(.metadataResolutionFailed(
                        parameterName: outerPath,
                        reason: "\(error)"
                    ))
                }
            case .boundGeneric(let baseCandidate, let innerArguments):
                // Recursively validate + preflight the inner selection.
                // Inner errors/warnings arrive carrying the dotted
                // `<outer>.` prefix because `collectBoundGenericValidation`
                // calls the inner `internalValidate` /
                // `internalRuntimePreflight` with `parameterPathPrefix:
                // outerPath`. The outer-level aggregation here therefore
                // routes the single roll-up under `outerPath` as well.
                let outcome = collectBoundGenericValidation(
                    baseCandidate: baseCandidate,
                    innerArguments: innerArguments,
                    parameterPath: outerPath,
                    depth: depth
                )
                outcome.warnings.forEach { builder.addWarning($0) }
                if !outcome.errors.isEmpty {
                    let joined = outcome.errors.map { $0.description }.joined(separator: "; ")
                    builder.addError(.metadataResolutionFailed(
                        parameterName: outerPath,
                        reason: joined
                    ))
                } else if let metadata = outcome.metadata {
                    metadataByName[parameter.name] = metadata
                }
            case .candidate:
                // The candidate's metadata still requires an accessor call;
                // leave the actual conformance/layout enforcement to
                // `specialize`'s candidate-resolution path. Intentionally
                // not entered into the map so cross-parameter checks
                // (e.g. sameType) treat it as "unresolved".
                continue
            }
        }

        for parameter in request.parameters {
            guard let metadata = metadataByName[parameter.name] else { continue }
            let outerPath = Self.joinedPath(parameterPathPrefix, parameter.name)

            for requirement in parameter.requirements {
                switch requirement {
                case .protocol(let info) where info.requiresWitnessTable:
                    guard let indexer else {
                        // No indexer at all — we can never check conformance.
                        // Surface once per missing-protocol/requirement pair
                        // so the caller knows validation was a no-op.
                        builder.addWarning(.protocolNotInIndexer(
                            parameterName: outerPath,
                            protocolName: info.protocolName.name
                        ))
                        continue
                    }
                    guard let protocolDef = indexer.allAllProtocolDefinitions[info.protocolName] else {
                        // Indexer present but the protocol's defining image
                        // isn't included as a sub-indexer.
                        builder.addWarning(.protocolNotInIndexer(
                            parameterName: outerPath,
                            protocolName: info.protocolName.name
                        ))
                        continue
                    }
                    let descriptor: MachOSwiftSection.`Protocol`
                    do {
                        descriptor = try MachOSwiftSection.`Protocol`(
                            descriptor: protocolDef.value.protocol.descriptor.asPointerWrapper(in: protocolDef.machO)
                        )
                    } catch {
                        // Indexer found the entry but materializing the
                        // protocol descriptor failed — preflight cannot
                        // run the conformance check for this requirement.
                        // Distinct from `protocolNotInIndexer`: the
                        // protocol *is* known but unusable.
                        builder.addError(.protocolDescriptorResolutionFailed(
                            parameterName: outerPath,
                            protocolName: info.protocolName.name,
                            reason: "\(error)"
                        ))
                        continue
                    }
                    // Distinguish "couldn't run the check" (throw) from
                    // "ran the check, type doesn't conform" (nil). The
                    // former is a warning (validation incomplete); the
                    // latter is the existing hard error.
                    let conforms: ProtocolWitnessTable?
                    do {
                        conforms = try RuntimeFunctions.conformsToProtocol(
                            metadata: metadata,
                            protocolDescriptor: descriptor.descriptor
                        )
                    } catch {
                        builder.addWarning(.conformanceCheckFailed(
                            parameterName: outerPath,
                            protocolName: info.protocolName.name,
                            reason: "\(error)"
                        ))
                        continue
                    }
                    if conforms == nil {
                        builder.addError(.protocolRequirementNotSatisfied(
                            parameterName: outerPath,
                            protocolName: info.protocolName.name,
                            actualType: "\(metadata)"
                        ))
                    }
                case .layout(let layoutKind):
                    switch layoutKind {
                    case .class:
                        let kind = metadata.kind
                        let isClassLike = (kind == .class || kind == .objcClassWrapper || kind == .foreignClass)
                        if !isClassLike {
                            builder.addError(.layoutRequirementNotSatisfied(
                                parameterName: outerPath,
                                expectedLayout: layoutKind,
                                actualType: "\(metadata)"
                            ))
                        }
                    }
                case .baseClass, .sameType, .protocol:
                    // sameType / baseClass are validated below in the
                    // unified pass that delegates to runtime substitution
                    // (handles GP-LHS, dependent-member-LHS, and any RHS
                    // shape uniformly). ObjC-only `.protocol` requirements
                    // (no PWT slot) need no check.
                    continue
                }
            }
        }

        // Unified sameType / baseClass pass.
        //
        // Reads requirements directly from the binary's generic context
        // (so it covers dependent-member LHS forms like `A.Element == B`
        // which `SpecializationRequest` only surfaces via
        // `associatedTypeRequirements`, never on the parameter list) and
        // resolves both sides through `swift_getTypeByMangledNameInContext`.
        // This mirrors what Swift's own `_checkGenericRequirements` does
        // (`swift/stdlib/public/runtime/ProtocolConformance.cpp:1846`).
        runUnifiedConstraintCheck(
            selection: selection,
            request: request,
            into: builder
        )

        return builder.build()
    }

    /// Walk every binary-level `sameType` / `baseClass` requirement and
    /// validate it via runtime substitution.
    ///
    /// Skipped entirely when the selection contains any `.candidate` —
    /// preflight does not run candidate metadata accessors (that path is
    /// reserved for `specialize`). Buffer construction errors degrade
    /// silently because the same failures already surfaced in the
    /// per-parameter pre-pass above.
    private func runUnifiedConstraintCheck(
        selection: SpecializationSelection,
        request: SpecializationRequest,
        into builder: SpecializationValidation.Builder
    ) {
        // Candidate selections require running the candidate's metadata
        // accessor; preflight intentionally avoids that side-effect, so
        // skip the whole pass.
        let hasCandidate = selection.arguments.values.contains { argument in
            if case .candidate = argument { return true }
            return false
        }
        if hasCandidate { return }

        // Build the metadata + PWT arrays in canonical order. Failures
        // here typically map to errors already reported by the per-param
        // pre-pass (missing arg, metadata creation failure, …); silently
        // bail out so we don't double-report.
        let buffer: (metadatas: [Metadata], witnessTables: [ProtocolWitnessTable], resolvedArguments: [SpecializationResult.ResolvedArgument])
        do {
            buffer = try buildKeyArgumentsBuffer(for: request, with: selection)
        } catch {
            return
        }

        // Pack metadatas + PWTs into a flat raw pointer buffer in the
        // exact order `swift_getGenericMetadata` (and therefore
        // `swift_getTypeByMangledNameInContext`'s substitution) expects.
        var rawArguments: [UnsafeRawPointer] = []
        rawArguments.reserveCapacity(buffer.metadatas.count + buffer.witnessTables.count)
        do {
            for metadata in buffer.metadatas {
                rawArguments.append(try metadata.asPointer)
            }
            for witnessTable in buffer.witnessTables {
                rawArguments.append(try witnessTable.asPointer)
            }
        } catch {
            return
        }

        let typeDescriptor = request.typeDescriptor.asPointerWrapper(in: machO)
        let descriptorPointer: UnsafeRawPointer
        do {
            descriptorPointer = try typeDescriptor.typeContextDescriptor.asPointer
        } catch {
            return
        }

        guard let genericContext = (try? request.typeDescriptor.genericContext(in: machO)) ?? nil else {
            return
        }

        let mergedRequirements = Self.mergedRequirements(from: genericContext)

        rawArguments.withUnsafeBufferPointer { argumentsBuffer in
            guard let argumentsBase = argumentsBuffer.baseAddress else { return }
            let argumentsPointer = UnsafeRawPointer(argumentsBase)

            for requirement in mergedRequirements {
                let kind = requirement.layout.flags.kind
                guard kind == .sameType || kind == .baseClass else { continue }

                evaluateConstraintRequirement(
                    kind: kind,
                    descriptor: requirement,
                    typeDescriptorPointer: descriptorPointer,
                    argumentsPointer: argumentsPointer,
                    into: builder
                )
            }
        }
    }

    /// Resolve LHS / RHS of a single sameType / baseClass requirement via
    /// runtime substitution and compare metadata pointers. The display
    /// names used in diagnostics come from the demangled node (so
    /// `A.Element.Index` reads as written, not as a raw mangled string).
    private func evaluateConstraintRequirement(
        kind: GenericRequirementKind,
        descriptor: GenericRequirementDescriptor,
        typeDescriptorPointer: UnsafeRawPointer,
        argumentsPointer: UnsafeRawPointer,
        into builder: SpecializationValidation.Builder
    ) {
        let lhsMangled: MangledName
        let rhsMangled: MangledName
        do {
            lhsMangled = try descriptor.paramMangledName(in: machO)
            rhsMangled = try descriptor.type(in: machO)
        } catch {
            return
        }

        let lhsDisplay = constraintDisplayName(for: lhsMangled)
        let rhsDisplay = constraintDisplayName(for: rhsMangled)

        let lhsResolution = resolveConstraintSide(
            mangledName: lhsMangled,
            descriptorPointer: typeDescriptorPointer,
            argumentsPointer: argumentsPointer
        )
        switch lhsResolution {
        case .resolved(let lhsType):
            let rhsResolution = resolveConstraintSide(
                mangledName: rhsMangled,
                descriptorPointer: typeDescriptorPointer,
                argumentsPointer: argumentsPointer
            )
            switch rhsResolution {
            case .resolved(let rhsType):
                compareConstraintSides(
                    kind: kind,
                    lhsType: lhsType,
                    rhsType: rhsType,
                    lhsDisplay: lhsDisplay,
                    rhsDisplay: rhsDisplay,
                    into: builder
                )
            case .unresolved(let reason):
                emitResolutionWarning(
                    kind: kind, parameterName: lhsDisplay,
                    reason: "could not resolve RHS '\(rhsDisplay)': \(reason)",
                    into: builder
                )
            }
        case .unresolved(let reason):
            emitResolutionWarning(
                kind: kind, parameterName: lhsDisplay,
                reason: "could not resolve LHS: \(reason)",
                into: builder
            )
        }
    }

    /// Outcome of trying to resolve a requirement side via runtime
    /// substitution. `unresolved` carries a human-readable reason for the
    /// warning the caller will emit.
    private enum ConstraintResolution {
        case resolved(Any.Type)
        case unresolved(reason: String)
    }

    private func resolveConstraintSide(
        mangledName: MangledName,
        descriptorPointer: UnsafeRawPointer,
        argumentsPointer: UnsafeRawPointer
    ) -> ConstraintResolution {
        do {
            guard let resolvedType = try RuntimeFunctions.getTypeByMangledNameInContext(
                mangledName,
                genericContext: descriptorPointer,
                genericArguments: argumentsPointer,
                in: machO
            ) else {
                return .unresolved(reason: "swift_getTypeByMangledNameInContext returned nil")
            }
            return .resolved(resolvedType)
        } catch {
            return .unresolved(reason: "\(error)")
        }
    }

    /// Generates the readable display string for a side of a constraint —
    /// preferred for diagnostics over raw mangled bytes. Falls back to a
    /// placeholder when demangling fails (rare; should never block the
    /// rest of the validation pipeline).
    private func constraintDisplayName(for mangledName: MangledName) -> String {
        if let node = try? MetadataReader.demangleType(for: mangledName, in: machO) {
            return node.print(using: .interfaceTypeBuilderOnly)
        }
        return "<unprintable>"
    }

    private func compareConstraintSides(
        kind: GenericRequirementKind,
        lhsType: Any.Type,
        rhsType: Any.Type,
        lhsDisplay: String,
        rhsDisplay: String,
        into builder: SpecializationValidation.Builder
    ) {
        let lhsTypePointer = unsafeBitCast(lhsType, to: UnsafeRawPointer.self)
        let rhsTypePointer = unsafeBitCast(rhsType, to: UnsafeRawPointer.self)

        switch kind {
        case .sameType:
            if lhsTypePointer != rhsTypePointer {
                builder.addError(.sameTypeRequirementNotSatisfied(
                    parameterName: lhsDisplay,
                    expectedType: "\(rhsType)",
                    actualType: "\(lhsType)"
                ))
            }
        case .baseClass:
            if !isClassDescendantOrSelf(
                selectedPointer: lhsTypePointer,
                expectedPointer: rhsTypePointer,
                lhsType: lhsType
            ) {
                builder.addError(.baseClassRequirementNotSatisfied(
                    parameterName: lhsDisplay,
                    expectedBaseClass: "\(rhsType)",
                    actualType: "\(lhsType)"
                ))
            }
        default:
            break
        }
    }

    private func emitResolutionWarning(
        kind: GenericRequirementKind,
        parameterName: String,
        reason: String,
        into builder: SpecializationValidation.Builder
    ) {
        switch kind {
        case .sameType:
            builder.addWarning(.sameTypeRequirementResolutionSkipped(
                parameterName: parameterName,
                reason: reason
            ))
        case .baseClass:
            builder.addWarning(.baseClassRequirementResolutionFailed(
                parameterName: parameterName,
                reason: reason
            ))
        default:
            break
        }
    }

    /// Subclass-or-self test mirroring Swift runtime's `isSubclass`
    /// (`swift/stdlib/public/runtime/ProtocolConformance.cpp:1702`):
    /// pointer-equality short-circuit, then walk the superclass chain via
    /// the universal `AnyClassMetadataObjCInterop.superclass()` accessor
    /// (works for pure Swift classes, ObjC class wrappers, and foreign
    /// classes alike).
    private func isClassDescendantOrSelf(
        selectedPointer: UnsafeRawPointer,
        expectedPointer: UnsafeRawPointer,
        lhsType: Any.Type
    ) -> Bool {
        if selectedPointer == expectedPointer { return true }

        // The constraint demands a class — value-type metadata can never
        // satisfy it. Detect via metadata kind to avoid a misleading
        // "superclass walk threw" error.
        let lhsMetadata: Metadata
        do {
            lhsMetadata = try Metadata.createInProcess(lhsType)
        } catch {
            return false
        }
        let kind = lhsMetadata.kind
        let isClassLike = (kind == .class || kind == .objcClassWrapper || kind == .foreignClass)
        guard isClassLike else { return false }

        do {
            var current = try AnyClassMetadataObjCInterop.resolve(from: selectedPointer)
            while let parent = try current.superclass() {
                let parentPointer = try parent.asPointer
                if parentPointer == expectedPointer { return true }
                current = parent
            }
        } catch {
            return false
        }
        return false
    }

}

// MARK: - Specialization Execution

@_spi(Support)
extension GenericSpecializer where MachO == MachOImage {

    /// Execute specialization with user selections
    ///
    /// - Parameters:
    ///   - request: The specialization request
    ///   - selection: The user's type selections
    ///   - metadataRequest: Freshness state requested for the *returned*
    ///     metadata. Internal accessor calls used to resolve candidate
    ///     types and associated-type witnesses always use fully-complete
    ///     blocking requests, matching the semantics of
    ///     `swift_getGenericMetadata`.
    /// - Returns: Specialized metadata result
    /// - Throws: If specialization fails
    public func specialize(
        _ request: SpecializationRequest,
        with selection: SpecializationSelection,
        metadataRequest: MetadataRequest = .completeAndBlocking
    ) throws -> SpecializationResult {
        // Collapse `.boundGeneric` arguments into `.specialized` from the
        // leaves up before delegating to `internalSpecialize`. Without this
        // pass, every nested binding gets specialized twice per level —
        // once inside `internalRuntimePreflight`
        // (via `collectBoundGenericValidation`, which needs the inner
        // metadata for cross-parameter constraint checks) and once in the
        // main path (`buildKeyArgumentsBuffer` →
        // `recursivelySpecializeBoundGeneric`). Both branches recurse into
        // their inner specializers, so nesting depth N degrades to
        // O(2^N) inner specializations. Pre-resolution caches each level's
        // result in `.specialized`, restoring linear-in-depth behavior.
        let resolvedSelection = try preResolveBoundGenerics(selection: selection, depth: 0)
        return try internalSpecialize(
            request,
            with: resolvedSelection,
            metadataRequest: metadataRequest,
            depth: 0
        )
    }

    /// Walk the selection depth-first and replace every `.boundGeneric`
    /// argument with a `.specialized` argument carrying its already-
    /// resolved `SpecializationResult`. Inner selections are processed
    /// first so each level's `internalSpecialize` call sees only
    /// `.specialized` arguments — `internalValidate`,
    /// `internalRuntimePreflight`, and `buildKeyArgumentsBuffer` then have
    /// no nested binding chain to recurse into, and the inner accessor
    /// runs exactly once per level.
    private func preResolveBoundGenerics(
        selection: SpecializationSelection,
        depth: Int
    ) throws -> SpecializationSelection {
        var hasBoundGeneric = false
        for argument in selection.arguments.values {
            if case .boundGeneric = argument {
                hasBoundGeneric = true
                break
            }
        }
        guard hasBoundGeneric else { return selection }

        var resolvedArguments = selection.arguments
        for (parameterName, argument) in selection.arguments {
            guard case .boundGeneric(let baseCandidate, let innerArguments) = argument else {
                continue
            }
            if depth >= maxBindingDepth {
                throw SpecializerError.specializationFailed(
                    reason: "binding depth exceeded (maxBindingDepth = \(maxBindingDepth)) at parameter '\(parameterName)'"
                )
            }
            let result = try resolveBoundGenericNode(
                baseCandidate: baseCandidate,
                innerArguments: innerArguments,
                parameterName: parameterName,
                depth: depth
            )
            resolvedArguments[parameterName] = .specialized(result)
        }
        return SpecializationSelection(arguments: resolvedArguments)
    }

    /// Specialize one `.boundGeneric` node into a `SpecializationResult`.
    /// Recurses through `preResolveBoundGenerics` on the inner selection
    /// before invoking the inner `internalSpecialize`, so the inner call
    /// itself never re-specializes nested levels.
    ///
    /// Failures are lifted into `SpecializerError.specializationFailed`
    /// with a reason that mirrors the diagnostic
    /// `internalRuntimePreflight` would have produced — keeping callers
    /// that pattern-match on `.specializationFailed` working unchanged.
    private func resolveBoundGenericNode(
        baseCandidate: SpecializationRequest.Candidate,
        innerArguments: [String: SpecializationSelection.Argument],
        parameterName: String,
        depth: Int
    ) throws -> SpecializationResult {
        do {
            let inner = try makeInnerContext(for: baseCandidate)
            let innerRequest = try inner.specializer.makeRequest(for: inner.descriptor)
            let innerSelection = SpecializationSelection(arguments: innerArguments)
            let preResolvedInnerSelection = try inner.specializer.preResolveBoundGenerics(
                selection: innerSelection,
                depth: depth + 1
            )
            return try inner.specializer.internalSpecialize(
                innerRequest,
                with: preResolvedInnerSelection,
                metadataRequest: .completeAndBlocking,
                depth: depth + 1
            )
        } catch let SpecializerError.specializationFailed(innerReason) {
            // Inner already aggregated through `internalSpecialize`'s own
            // validation pipeline — propagate the message under the outer
            // parameter path so the joined reason still reads end-to-end.
            throw SpecializerError.specializationFailed(
                reason: "Could not resolve metadata for parameter '\(parameterName)': \(innerReason)"
            )
        } catch {
            // `makeInnerContext` / `makeRequest` failures (e.g. selecting a
            // non-generic candidate for `.boundGeneric`) used to surface
            // via preflight's `metadataResolutionFailed` aggregation.
            // Reproduce that wording so existing diagnostics stay stable.
            let underlyingMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            throw SpecializerError.specializationFailed(
                reason: "Could not resolve metadata for parameter '\(parameterName)': could not build inner request: \(underlyingMessage)"
            )
        }
    }

    /// Depth-aware specialize used to thread `Argument.boundGeneric`
    /// recursion through `maxBindingDepth`. Public API enters at `depth = 0`.
    /// Inner specializers spawned by `recursivelySpecializeBoundGeneric`
    /// call this with `depth + 1` so the soft guard sees the cumulative
    /// nesting level across instances.
    func internalSpecialize(
        _ request: SpecializationRequest,
        with selection: SpecializationSelection,
        metadataRequest: MetadataRequest,
        depth: Int
    ) throws -> SpecializationResult {
        let typeDescriptor = request.typeDescriptor.asPointerWrapper(in: machO)
        // Static validation first (cheap, no runtime resolution).
        let staticValidation = internalValidate(
            selection: selection,
            for: request,
            parameterPathPrefix: "",
            depth: depth
        )
        guard staticValidation.isValid else {
            let errorMessages = staticValidation.errors.map { $0.description }.joined(separator: "; ")
            throw SpecializerError.specializationFailed(reason: errorMessages)
        }

        // Runtime preflight — verifies protocol conformance, layout, and
        // sameType / baseClass constraints before we ever call the
        // accessor. Surfaces mismatches as `SpecializationValidation.Error`
        // values matching the requirement kind, instead of letting them
        // blow up inside `swift_getGenericMetadata` (which doesn't actually
        // verify sameType / baseClass — see
        // `swift/stdlib/public/runtime/Metadata.cpp:810`).
        let runtimeValidation = internalRuntimePreflight(
            selection: selection,
            for: request,
            parameterPathPrefix: "",
            depth: depth
        )
        guard runtimeValidation.isValid else {
            let errorMessages = runtimeValidation.errors.map { $0.description }.joined(separator: "; ")
            throw SpecializerError.specializationFailed(reason: errorMessages)
        }

        // Build metadata + PWT arrays in canonical (binary) order.
        let buffer = try buildKeyArgumentsBuffer(for: request, with: selection, depth: depth)

        // Get metadata accessor function
        let accessorFunction = try typeDescriptor.typeContextDescriptor.metadataAccessorFunction()
        guard let accessorFunction else {
            throw SpecializerError.metadataCreationFailed(
                typeName: "unknown",
                reason: "Cannot get metadata accessor function"
            )
        }

        // Call accessor with metadatas and witness tables
        let response = try accessorFunction(
            request: metadataRequest,
            metadatas: buffer.metadatas,
            witnessTables: buffer.witnessTables,
        )

        return SpecializationResult(
            metadataPointer: response.value,
            resolvedArguments: buffer.resolvedArguments
        )
    }

    /// Build the metadata + PWT arrays in canonical (binary) order — the
    /// shape that both `swift_getGenericMetadata` (used by the metadata
    /// accessor) and `swift_getTypeByMangledNameInContext` (used by the
    /// runtime's own `_checkGenericRequirements`, see
    /// `swift/stdlib/public/runtime/ProtocolConformance.cpp:1846`) expect.
    ///
    /// Layout: every direct-GP metadata first, every direct-GP PWT in
    /// `Parameter.requirements` order next, every associated-type PWT in
    /// `compareDependentTypes` order last.
    ///
    /// The PWT ordering invariant (verified by every existing fixture):
    /// Swift's `compareDependentTypesRec` orders all GP-rooted requirements
    /// before any nested-type-rooted requirement (see
    /// `swift/lib/AST/GenericSignature.cpp:846`). Walking direct-GP
    /// requirements in parameter order, then walking associated
    /// requirements in canonical merged-requirement order, reconstructs
    /// exactly the binary's emission order without an explicit re-sort.
    func buildKeyArgumentsBuffer(
        for request: SpecializationRequest,
        with selection: SpecializationSelection,
        depth: Int = 0
    ) throws -> (
        metadatas: [Metadata],
        witnessTables: [ProtocolWitnessTable],
        resolvedArguments: [SpecializationResult.ResolvedArgument]
    ) {
        let typeDescriptor = request.typeDescriptor.asPointerWrapper(in: machO)
        var metadatas: [Metadata] = []
        var witnessTables: [ProtocolWitnessTable] = []
        var resolvedArguments: [SpecializationResult.ResolvedArgument] = []

        for parameter in request.parameters {
            guard let argument = selection[parameter.name] else {
                throw SpecializerError.specializationFailed(reason: "Missing argument for \(parameter.name)")
            }

            let resolved = try resolveArgument(
                for: argument,
                parameterName: parameter.name,
                depth: depth
            )
            metadatas.append(resolved.metadata)

            var paramWitnessTables: [ProtocolWitnessTable] = []
            for requirement in parameter.requirements {
                if case .protocol(let info) = requirement, info.requiresWitnessTable {
                    let witnessTable = try resolveWitnessTable(
                        for: resolved.metadata,
                        conformingTo: info.protocolName,
                        parameterName: parameter.name
                    )
                    witnessTables.append(witnessTable)
                    paramWitnessTables.append(witnessTable)
                }
            }

            resolvedArguments.append(SpecializationResult.ResolvedArgument(
                parameterName: parameter.name,
                metadata: resolved.metadata,
                witnessTables: paramWitnessTables,
                innerResult: resolved.innerResult
            ))
        }

        let metadataByParamName = Dictionary(
            uniqueKeysWithValues: zip(request.parameters.map(\.name), metadatas)
        )
        let associatedTypeWitnesses = try resolveAssociatedTypeWitnesses(
            for: typeDescriptor,
            substituting: metadataByParamName
        )
        witnessTables.append(contentsOf: associatedTypeWitnesses)

        // Defensive invariant — the accessor expects exactly
        // `numKeyArguments` slots. If `buildParameters` /
        // `collectRequirements` / `buildAssociatedTypeRequirements` ever
        // miscount, we'd send the wrong number of args and the runtime
        // would fail opaquely. Reject up front with a typed error so the
        // regression is immediately attributable.
        let totalArguments = metadatas.count + witnessTables.count
        guard totalArguments == request.keyArgumentCount else {
            throw SpecializerError.specializationFailed(
                reason: "internal: key argument count mismatch — request expects \(request.keyArgumentCount) (header.numKeyArguments), built \(totalArguments) (\(metadatas.count) metadatas + \(witnessTables.count) witness tables)"
            )
        }

        return (metadatas, witnessTables, resolvedArguments)
    }

    /// Resolve metadata from a selection argument, also returning the
    /// recursively-resolved `SpecializationResult` when the argument
    /// originated from `.boundGeneric` or `.specialized` (so the tree
    /// can be surfaced via `ResolvedArgument.innerResult`).
    private func resolveArgument(
        for argument: SpecializationSelection.Argument,
        parameterName: String,
        depth: Int
    ) throws -> (metadata: Metadata, innerResult: SpecializationResult?) {
        switch argument {
        case .metatype(let type):
            return (try Metadata.createInProcess(type), nil)

        case .metadata(let metadata):
            return (metadata, nil)

        case .candidate(let candidate):
            return (try resolveCandidate(candidate, parameterName: parameterName), nil)

        case .specialized(let result):
            return (try result.metadata(), result)

        case .boundGeneric(let baseCandidate, let innerArguments):
            let innerResult = try recursivelySpecializeBoundGeneric(
                baseCandidate: baseCandidate,
                innerArguments: innerArguments,
                parameterName: parameterName,
                depth: depth
            )
            return (try innerResult.metadata(), innerResult)
        }
    }

    /// Resolve a `.boundGeneric` selection into a `SpecializationResult` by
    /// constructing an inner request from `baseCandidate`'s descriptor and
    /// running an inner specializer bound to the candidate's defining
    /// image. Throws `SpecializerError.boundGenericInnerFailed` wrapping
    /// the underlying error so callers can pattern-match while keeping the
    /// inner cause attached.
    private func recursivelySpecializeBoundGeneric(
        baseCandidate: SpecializationRequest.Candidate,
        innerArguments: [String: SpecializationSelection.Argument],
        parameterName: String,
        depth: Int
    ) throws -> SpecializationResult {
        if depth >= maxBindingDepth {
            throw SpecializerError.specializationFailed(
                reason: "binding depth exceeded (maxBindingDepth = \(maxBindingDepth)) at parameter '\(parameterName)'"
            )
        }

        let inner: (descriptor: TypeContextDescriptorWrapper, specializer: GenericSpecializer<MachO>)
        do {
            inner = try makeInnerContext(for: baseCandidate)
        } catch {
            throw SpecializerError.boundGenericInnerFailed(
                parameterName: parameterName,
                underlying: error
            )
        }

        let innerRequest: SpecializationRequest
        do {
            innerRequest = try inner.specializer.makeRequest(for: inner.descriptor)
        } catch {
            throw SpecializerError.boundGenericInnerFailed(
                parameterName: parameterName,
                underlying: error
            )
        }

        let innerSelection = SpecializationSelection(arguments: innerArguments)
        do {
            return try inner.specializer.internalSpecialize(
                innerRequest,
                with: innerSelection,
                metadataRequest: .completeAndBlocking,
                depth: depth + 1
            )
        } catch {
            throw SpecializerError.boundGenericInnerFailed(
                parameterName: parameterName,
                underlying: error
            )
        }
    }

    /// Run inner `validate` + inner `runtimePreflight` on a `.boundGeneric`
    /// selection so the outer preflight can report inner errors/warnings
    /// with dotted parameter paths. When no errors surface, the resolved
    /// inner metadata is returned so the caller can populate
    /// `metadataByName` for downstream cross-parameter checks (sameType /
    /// baseClass via runtime substitution).
    private func collectBoundGenericValidation(
        baseCandidate: SpecializationRequest.Candidate,
        innerArguments: [String: SpecializationSelection.Argument],
        parameterPath: String,
        depth: Int
    ) -> (
        errors: [SpecializationValidation.Error],
        warnings: [SpecializationValidation.Warning],
        metadata: Metadata?
    ) {
        if depth >= maxBindingDepth {
            return (
                [.metadataResolutionFailed(
                    parameterName: parameterPath,
                    reason: "binding depth exceeded (maxBindingDepth = \(maxBindingDepth))"
                )],
                [],
                nil
            )
        }

        let inner: (descriptor: TypeContextDescriptorWrapper, specializer: GenericSpecializer<MachO>)
        do {
            inner = try makeInnerContext(for: baseCandidate)
        } catch {
            return (
                [.metadataResolutionFailed(parameterName: parameterPath, reason: "\(error)")],
                [],
                nil
            )
        }

        let innerRequest: SpecializationRequest
        do {
            innerRequest = try inner.specializer.makeRequest(for: inner.descriptor)
        } catch {
            return (
                [.metadataResolutionFailed(
                    parameterName: parameterPath,
                    reason: "could not build inner request: \(error)"
                )],
                [],
                nil
            )
        }

        let innerSelection = SpecializationSelection(arguments: innerArguments)
        let innerStatic = inner.specializer.internalValidate(
            selection: innerSelection,
            for: innerRequest,
            parameterPathPrefix: parameterPath,
            depth: depth + 1
        )
        let innerRuntime = inner.specializer.internalRuntimePreflight(
            selection: innerSelection,
            for: innerRequest,
            parameterPathPrefix: parameterPath,
            depth: depth + 1
        )

        // `internalValidate` and `internalRuntimePreflight` both produce
        // pre-prefixed errors/warnings (they accept `parameterPathPrefix`).
        // Concatenating them keeps the dotted-path identity intact end-
        // to-end — no `prefixWarning` / `prefixError` pass is needed here.
        let combinedErrors = innerStatic.errors + innerRuntime.errors
        let combinedWarnings = innerStatic.warnings + innerRuntime.warnings

        if !combinedErrors.isEmpty {
            return (combinedErrors, combinedWarnings, nil)
        }

        do {
            let result = try inner.specializer.internalSpecialize(
                innerRequest,
                with: innerSelection,
                metadataRequest: .completeAndBlocking,
                depth: depth + 1
            )
            return ([], combinedWarnings, try result.metadata())
        } catch {
            return (
                [.metadataResolutionFailed(parameterName: parameterPath, reason: "\(error)")],
                combinedWarnings,
                nil
            )
        }
    }

    /// Resolve a candidate type to metadata
    private func resolveCandidate(_ candidate: SpecializationRequest.Candidate, parameterName: String) throws -> Metadata {
        let (typeContextWrapper, machO) = try resolveCandidateDescriptor(candidate)
        let typeContext = typeContextWrapper.typeContextDescriptor

        // Generic candidates need nested specialization; surface a typed error
        // rather than letting the no-argument accessor call below fail with
        // a generic message.
        if let genericContext = try typeContext.genericContext(in: machO) {
            throw SpecializerError.candidateRequiresNestedSpecialization(
                candidate: candidate,
                parameterCount: Int(genericContext.header.numParams)
            )
        }

        // Get accessor function from type definition's type context
        let accessorFunction = try typeContext.metadataAccessorFunction(in: machO)
        guard let accessorFunction else {
            throw SpecializerError.candidateResolutionFailed(
                candidate: candidate,
                reason: "Cannot get metadata accessor function"
            )
        }

        // Non-generic: call accessor with no arguments
        let response = try accessorFunction(request: .completeAndBlocking)
        let wrapper = try response.value.resolve()
        return try wrapper.metadata
    }

    /// Resolve witness table for a type conforming to a protocol using runtime conformance check
    private func resolveWitnessTable(
        for metadata: Metadata,
        conformingTo protocolName: ProtocolName,
        parameterName: String
    ) throws -> ProtocolWitnessTable {
        // Look up the protocol descriptor from indexer
        guard let indexer else {
            throw SpecializerError.witnessTableNotFound(
                typeName: parameterName,
                protocolName: protocolName.name
            )
        }

        guard let protocolDef = indexer.allAllProtocolDefinitions[protocolName] else {
            throw SpecializerError.witnessTableNotFound(
                typeName: parameterName,
                protocolName: protocolName.name
            )
        }

        // Create in-process protocol descriptor and use runtime conformance check
        let protocolDescriptor = try MachOSwiftSection.`Protocol`(
            descriptor: protocolDef.value.protocol.descriptor.asPointerWrapper(in: protocolDef.machO)
        )

        guard let witnessTable = try RuntimeFunctions.conformsToProtocol(
            metadata: metadata,
            protocolDescriptor: protocolDescriptor.descriptor
        ) else {
            throw SpecializerError.witnessTableNotFound(
                typeName: parameterName,
                protocolName: protocolName.name
            )
        }

        return witnessTable
    }
}

// MARK: - Associated Type Witness Resolution

@_spi(Support)
extension GenericSpecializer where MachO == MachOImage {

    /// Resolve associated type witness tables for a generic type's requirements.
    ///
    /// Processes the generic requirements to find associated type constraints
    /// (e.g. `A.Element: Hashable`) and resolves the corresponding witness
    /// tables using runtime functions.
    ///
    /// The returned array is in canonical (binary) requirement order — the
    /// same order Swift's `compareDependentTypes`
    /// (`swift/lib/AST/GenericSignature.cpp:846`) emits the witness-table
    /// slots into the metadata accessor's argument list. Callers are
    /// expected to splice this array into their PWT list **after** the
    /// direct-GP PWTs.
    ///
    /// - Parameters:
    ///   - type: The generic type descriptor
    ///   - genericArguments: Mapping from parameter name to resolved metadata
    /// - Returns: Witness tables, in canonical binary order, for every
    ///   associated-type requirement reachable from this descriptor.
    func resolveAssociatedTypeWitnesses(
        for type: TypeContextDescriptorWrapper,
        substituting genericArguments: [String: Metadata]
    ) throws -> [ProtocolWitnessTable] {
        guard let indexer else {
            throw AssociatedTypeResolutionError.missingIndexer
        }

        var results: [ProtocolWitnessTable] = []

        guard let genericContextInProcess = try type.genericContext() else {
            throw AssociatedTypeResolutionError.missingGenericContext(typeDescriptor: type)
        }

        if let unsupportedParameter = genericContextInProcess.parameters.first(where: { $0.kind == .typePack || $0.kind == .value }) {
            throw AssociatedTypeResolutionError.unsupportedGenericParameter(parameterKind: unsupportedParameter.kind)
        }

        let requirements = try Self.mergedRequirements(from: genericContextInProcess)
            .map { try GenericRequirement(descriptor: $0) }
        let allProtocolDefinitions = indexer.allAllProtocolDefinitions

        for requirement in requirements {
            // Only protocol conformance requirements with key arguments produce
            // associated-type witness tables; everything else is irrelevant here.
            guard requirement.flags.kind == .protocol,
                  requirement.flags.contains(.hasKeyArgument),
                  let requirementProtocolDescriptor = requirement.content.protocol?.resolved,
                  let protocolDescriptor = requirementProtocolDescriptor.swift else { continue }

            let requirementProtocol = try MachOSwiftSection.`Protocol`(descriptor: protocolDescriptor)
            let paramNode = try MetadataReader.demangleType(for: requirement.paramManagledName)

            guard let pathInfo = Self.extractAssociatedPath(of: paramNode) else {
                throw AssociatedTypeResolutionError.unknownParamNodeStructure(paramNode: paramNode)
            }

            // Direct generic parameter requirement: handled by `specialize()`, skip here.
            guard !pathInfo.steps.isEmpty else { continue }

            // Walk the associated-type chain step by step starting from the
            // root generic parameter's metadata.
            guard var currentMetadata = genericArguments[pathInfo.baseParamName] else {
                throw AssociatedTypeResolutionError.missingConformingTypeMetadata(
                    genericParam: pathInfo.baseParamName,
                    availableParams: Array(genericArguments.keys)
                )
            }

            for step in pathInfo.steps {
                currentMetadata = try resolveAssociatedTypeStep(
                    currentMetadata: currentMetadata,
                    step: step,
                    allProtocolDefinitions: allProtocolDefinitions
                )
            }

            // The leaf metadata must conform to the requirement protocol; that
            // conformance PWT is the value the runtime expects in the slot.
            let currentProtocolName = try requirementProtocol.protocolName()
            guard let associatedTypePWT = try? RuntimeFunctions.conformsToProtocol(
                metadata: currentMetadata,
                protocolDescriptor: requirementProtocol.descriptor
            ) else {
                throw AssociatedTypeResolutionError.associatedTypeDoesNotConformToProtocol(
                    associatedType: currentMetadata,
                    protocolName: currentProtocolName
                )
            }

            // Append in iteration (= binary) order. A previous version
            // grouped PWTs into an `OrderedDictionary<Metadata, [PWT]>`
            // keyed by leaf metadata; updates kept the original key
            // position, so when two distinct chains landed on the same
            // leaf and a third chain in between landed on a different
            // leaf, flattening the dictionary's values misordered the
            // PWT slots relative to `compareDependentTypes`. See
            // `associatedWitnessOrderingPreservesBinaryOrder` /
            // `specializeMatchesManualBinaryOrder` for the reproduction.
            results.append(associatedTypePWT)
        }

        return results
    }

    /// Resolve a single associated-type access (`Type → Type.Step`).
    ///
    /// Given the current conforming type's metadata and the protocol that
    /// declares the associated type, the function:
    /// 1. retrieves the protocol descriptor from the indexer,
    /// 2. fetches the witness table for `currentMetadata: stepProtocol`,
    /// 3. locates the associated-type access function for `step.name`,
    /// 4. invokes the runtime function to obtain the next metadata in the chain.
    private func resolveAssociatedTypeStep(
        currentMetadata: Metadata,
        step: AssociatedPathInfo.Step,
        allProtocolDefinitions: OrderedDictionary<ProtocolName, MachOIndexedValue<MachO, ProtocolDefinition>>
    ) throws -> Metadata {
        let stepProtocolName = ProtocolName(node: step.protocolNode)
        guard let entry = allProtocolDefinitions[stepProtocolName] else {
            throw AssociatedTypeResolutionError.missingAssociatedTypeRefMachOAndProtocol(protocolTypeNode: step.protocolNode)
        }

        let stepProtocol: MachOSwiftSection.`Protocol`
        do {
            stepProtocol = try MachOSwiftSection.`Protocol`(
                descriptor: entry.value.protocol.descriptor.asPointerWrapper(in: entry.machO)
            )
        } catch {
            throw AssociatedTypeResolutionError.failedToCreateAssociatedTypeRefProtocol(underlyingError: error)
        }

        let stepProtocolFullName = try stepProtocol.protocolName()
        let availableAssociatedTypes = try stepProtocol.descriptor.associatedTypes()

        guard let associatedTypeIndex = availableAssociatedTypes.firstIndex(of: step.name) else {
            throw AssociatedTypeResolutionError.missingAssociatedTypeIndex(
                associatedTypeName: step.name,
                protocolName: stepProtocolFullName,
                availableAssociatedTypes: availableAssociatedTypes
            )
        }

        guard let baseRequirement = stepProtocol.baseRequirement else {
            throw AssociatedTypeResolutionError.missingAssociatedTypeBaseRequirement(protocolName: stepProtocolFullName)
        }

        let accessFunctionRequirements = stepProtocol.requirements.filter {
            $0.flags.kind.isAssociatedTypeAccessFunction
        }

        guard let accessFunctionRequirement = accessFunctionRequirements[safe: associatedTypeIndex] else {
            throw AssociatedTypeResolutionError.missingAssociatedTypeAccessFunctionRequirement(
                index: associatedTypeIndex,
                protocolName: stepProtocolFullName,
                requirementCount: accessFunctionRequirements.count
            )
        }

        guard let conformingPWT = try RuntimeFunctions.conformsToProtocol(
            metadata: currentMetadata,
            protocolDescriptor: stepProtocol.descriptor
        ) else {
            throw AssociatedTypeResolutionError.conformingTypeDoesNotConformToProtocol(
                conformingType: currentMetadata,
                protocolName: stepProtocolFullName
            )
        }

        guard let nextMetadata = try? RuntimeFunctions.getAssociatedTypeWitness(
            request: .init(),
            protocolWitnessTable: conformingPWT,
            conformingTypeMetadata: currentMetadata,
            baseRequirement: baseRequirement,
            associatedTypeRequirement: accessFunctionRequirement
        ).value.resolve().metadata else {
            throw AssociatedTypeResolutionError.failedToGetAssociatedTypeWitness(
                conformingType: currentMetadata,
                protocolName: stepProtocolFullName,
                associatedTypeName: step.name
            )
        }

        return nextMetadata
    }

    /// Errors for associated type witness resolution
    enum AssociatedTypeResolutionError: LocalizedError {
        case missingIndexer
        case missingGenericContext(typeDescriptor: TypeContextDescriptorWrapper)
        case unsupportedGenericParameter(parameterKind: GenericParamKind)
        case missingDependentGenericParamType(dependentMemberType: Node)
        case missingGenericParamTypeText(dependentGenericParamType: Node)
        case missingConformingTypeMetadata(genericParam: String, availableParams: [String])
        case missingDependentAssociatedTypeRef(dependentMemberType: Node)
        case missingAssociatedTypeName(dependentAssociatedTypeRef: Node)
        case missingAssociatedTypeRefProtocolTypeNode(dependentAssociatedTypeRef: Node)
        case missingAssociatedTypeRefMachOAndProtocol(protocolTypeNode: Node)
        case failedToCreateAssociatedTypeRefProtocol(underlyingError: Swift.Error)
        case missingAssociatedTypeIndex(associatedTypeName: String, protocolName: ProtocolName, availableAssociatedTypes: [String])
        case missingAssociatedTypeBaseRequirement(protocolName: ProtocolName)
        case missingAssociatedTypeAccessFunctionRequirement(index: Int, protocolName: ProtocolName, requirementCount: Int)
        case conformingTypeDoesNotConformToProtocol(conformingType: Metadata, protocolName: ProtocolName)
        case failedToGetAssociatedTypeWitness(conformingType: Metadata, protocolName: ProtocolName, associatedTypeName: String)
        case associatedTypeDoesNotConformToProtocol(associatedType: Metadata, protocolName: ProtocolName)
        case unknownParamNodeStructure(paramNode: Node)

        var errorDescription: String? {
            switch self {
            case .missingIndexer:
                return "Indexer is required for associated type resolution"
            case .missingGenericContext(let typeDescriptor):
                return "Missing generic context for type descriptor: \(typeDescriptor)"
            case .unsupportedGenericParameter(let parameterKind):
                return "Unsupported generic parameter kind: \(parameterKind)"
            case .missingDependentGenericParamType(let dependentMemberType):
                return "Missing dependent generic param type in dependent member type: \(dependentMemberType)"
            case .missingGenericParamTypeText(let dependentGenericParamType):
                return "Missing text in dependent generic param type: \(dependentGenericParamType)"
            case .missingConformingTypeMetadata(let genericParam, let availableParams):
                return "Missing conforming type metadata for generic param '\(genericParam)'. Available params: \(availableParams.joined(separator: ", "))"
            case .missingDependentAssociatedTypeRef(let dependentMemberType):
                return "Missing dependent associated type ref in dependent member type: \(dependentMemberType)"
            case .missingAssociatedTypeName(let dependentAssociatedTypeRef):
                return "Missing associated type name in dependent associated type ref: \(dependentAssociatedTypeRef)"
            case .missingAssociatedTypeRefProtocolTypeNode(let dependentAssociatedTypeRef):
                return "Missing protocol type node in dependent associated type ref: \(dependentAssociatedTypeRef)"
            case .missingAssociatedTypeRefMachOAndProtocol(let protocolTypeNode):
                return "Missing MachO and protocol definition for protocol type node: \(protocolTypeNode)"
            case .failedToCreateAssociatedTypeRefProtocol(let underlyingError):
                return "Failed to create associated type ref protocol: \(underlyingError.localizedDescription)"
            case .missingAssociatedTypeIndex(let associatedTypeName, let protocolName, let availableAssociatedTypes):
                return "Associated type '\(associatedTypeName)' not found in protocol '\(protocolName.name)'. Available: \(availableAssociatedTypes.joined(separator: ", "))"
            case .missingAssociatedTypeBaseRequirement(let protocolName):
                return "Missing base requirement for protocol '\(protocolName.name)'"
            case .missingAssociatedTypeAccessFunctionRequirement(let index, let protocolName, let requirementCount):
                return "Missing associated type access function requirement at index \(index) for protocol '\(protocolName.name)'. Total: \(requirementCount)"
            case .conformingTypeDoesNotConformToProtocol(let conformingType, let protocolName):
                return "Conforming type '\(conformingType)' does not conform to protocol '\(protocolName.name)'"
            case .failedToGetAssociatedTypeWitness(let conformingType, let protocolName, let associatedTypeName):
                return "Failed to get associated type witness for '\(associatedTypeName)' from '\(conformingType)' to '\(protocolName.name)'"
            case .associatedTypeDoesNotConformToProtocol(let associatedType, let protocolName):
                return "Associated type '\(associatedType)' does not conform to protocol '\(protocolName.name)'"
            case .unknownParamNodeStructure(let paramNode):
                return "Unknown param node structure: \(paramNode)"
            }
        }
    }
}

// MARK: - Errors

@_spi(Support)
extension GenericSpecializer {
    /// Errors that can occur during specialization
    public enum SpecializerError: LocalizedError {
        case notGenericType(type: TypeContextDescriptorWrapper)
        case candidateResolutionFailed(candidate: SpecializationRequest.Candidate, reason: String)
        case candidateRequiresNestedSpecialization(
            candidate: SpecializationRequest.Candidate,
            parameterCount: Int
        )
        case metadataCreationFailed(typeName: String, reason: String)
        case witnessTableNotFound(typeName: String, protocolName: String)
        case specializationFailed(reason: String)
        case unsupportedGenericParameter(parameterKind: GenericParamKind)
        /// An `Argument.boundGeneric` selection's recursive specialization
        /// failed. `parameterName` is the outer parameter the binding was
        /// supplied for; `underlying` keeps the inner error's typed identity
        /// (often another `SpecializerError`) so callers can still match on
        /// the original cause rather than parsing a flattened string.
        case boundGenericInnerFailed(parameterName: String, underlying: Swift.Error)

        public var errorDescription: String? {
            switch self {
            case .notGenericType(let type):
                return "Type is not generic: \(type)"
            case .candidateResolutionFailed(let candidate, let reason):
                return "Failed to resolve candidate \(candidate.typeName.name): \(reason)"
            case .candidateRequiresNestedSpecialization(let candidate, let parameterCount):
                return "Candidate \(candidate.typeName.name) is generic with \(parameterCount) parameter(s); pass Argument.specialized(...) instead of Argument.candidate(...)"
            case .metadataCreationFailed(let typeName, let reason):
                return "Failed to create metadata for \(typeName): \(reason)"
            case .witnessTableNotFound(let typeName, let protocolName):
                return "Witness table not found for \(typeName) conforming to \(protocolName)"
            case .specializationFailed(let reason):
                return "Specialization failed: \(reason)"
            case .unsupportedGenericParameter(let parameterKind):
                return "Unsupported generic parameter kind: \(parameterKind). TypePack (variadic generics) and Value generics are not implemented yet."
            case .boundGenericInnerFailed(let parameterName, let underlying):
                let inner = (underlying as? LocalizedError)?.errorDescription ?? "\(underlying)"
                return "Inner specialization for parameter '\(parameterName)' failed: \(inner)"
            }
        }
    }
}
