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

    /// Indexer for accessing protocol definitions (needed for associated type resolution)
    private let indexer: SwiftInterfaceIndexer<MachO>?

    /// Initialize with an indexer (recommended)
    public init(indexer: SwiftInterfaceIndexer<MachO>) {
        self.machO = indexer.machO
        self.conformanceProvider = IndexerConformanceProvider(indexer: indexer)
        self.indexer = indexer
    }

    /// Initialize with MachO and custom conformance provider
    public init(machO: MachO, conformanceProvider: any ConformanceProvider, indexer: SwiftInterfaceIndexer<MachO>? = nil) {
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

                let candidates = findCandidates(
                    satisfying: protocolRequirements,
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
            return .sameType(demangledTypeNode: try MetadataReader.demangleType(for: mangledTypeName, in: machO))

        case .baseClass:
            let mangledTypeName = try genericRequirement.type(in: machO)
            return .baseClass(demangledTypeNode: try MetadataReader.demangleType(for: mangledTypeName, in: machO))

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
    private struct AssociatedTypeRequirementKey: Hashable {
        let parameterName: String
        let path: [String]
    }

    /// Find candidate types that satisfy all protocol constraints.
    ///
    /// Generic candidates are included by default but flagged via
    /// `Candidate.isGeneric`; selecting one via `Argument.candidate` would
    /// throw `candidateRequiresNestedSpecialization` from `specialize`. Pass
    /// `candidateOptions: .excludeGenerics` to skip them up front when the
    /// caller wants a "directly-specializable" list.
    private func findCandidates(
        satisfying protocols: [ProtocolName],
        options: SpecializationRequest.CandidateOptions = .default
    ) -> [SpecializationRequest.Candidate] {
        let typeNames: [TypeName]
        if protocols.isEmpty {
            typeNames = conformanceProvider.allTypeNames
        } else {
            typeNames = conformanceProvider.types(conformingToAll: protocols)
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
        let builder = SpecializationValidation.builder()

        for parameter in request.parameters {
            guard selection.hasArgument(for: parameter.name) else {
                builder.addError(.missingArgument(parameterName: parameter.name))
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
                builder.addWarning(.associatedTypePathInSelection(path: paramName))
            } else {
                builder.addWarning(.extraArgument(parameterName: paramName))
            }
        }

        return builder.build()
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
        let builder = SpecializationValidation.builder()

        for parameter in request.parameters {
            guard let argument = selection[parameter.name] else { continue }

            let metadata: Metadata
            switch argument {
            case .metatype(let type):
                guard let resolved = try? Metadata.createInProcess(type) else { continue }
                metadata = resolved
            case .metadata(let provided):
                metadata = provided
            case .specialized(let result):
                // `SpecializationResult` already carries a resolved metadata
                // pointer — no accessor call needed; preflight should
                // exercise the same checks it does for `.metatype`.
                guard let resolved = try? result.metadata() else { continue }
                metadata = resolved
            case .candidate:
                // The candidate's metadata still requires an accessor call;
                // leave the actual conformance/layout enforcement to
                // `specialize`'s candidate-resolution path.
                continue
            }

            for requirement in parameter.requirements {
                switch requirement {
                case .protocol(let info) where info.requiresWitnessTable:
                    guard let indexer else {
                        // No indexer at all — we can never check conformance.
                        // Surface once per missing-protocol/requirement pair
                        // so the caller knows validation was a no-op.
                        builder.addWarning(.protocolNotInIndexer(
                            parameterName: parameter.name,
                            protocolName: info.protocolName.name
                        ))
                        continue
                    }
                    guard let protocolDef = indexer.allAllProtocolDefinitions[info.protocolName] else {
                        // Indexer present but the protocol's defining image
                        // isn't included as a sub-indexer.
                        builder.addWarning(.protocolNotInIndexer(
                            parameterName: parameter.name,
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
                        continue
                    }
                    let conforms = (try? RuntimeFunctions.conformsToProtocol(
                        metadata: metadata,
                        protocolDescriptor: descriptor.descriptor
                    )) ?? nil
                    if conforms == nil {
                        builder.addError(.protocolRequirementNotSatisfied(
                            parameterName: parameter.name,
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
                                parameterName: parameter.name,
                                expectedLayout: layoutKind,
                                actualType: "\(metadata)"
                            ))
                        }
                    }
                case .protocol, .sameType, .baseClass:
                    // Other kinds: skip (no PWT, or out-of-scope — see header).
                    continue
                }
            }
        }

        return builder.build()
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
        let typeDescriptor = request.typeDescriptor.asPointerWrapper(in: machO)
        // Static validation first (cheap, no runtime resolution).
        let staticValidation = validate(selection: selection, for: request)
        guard staticValidation.isValid else {
            let errorMessages = staticValidation.errors.map { $0.description }.joined(separator: "; ")
            throw SpecializerError.specializationFailed(reason: errorMessages)
        }

        // Runtime preflight — verifies protocol conformance and layout
        // constraints before we ever call the accessor. Surfaces
        // mismatches as `SpecializationValidation.Error` values matching
        // the requirement kind, instead of letting them blow up inside
        // `swift_getGenericMetadata` or `RuntimeFunctions.conformsToProtocol`.
        let runtimeValidation = runtimePreflight(selection: selection, for: request)
        guard runtimeValidation.isValid else {
            let errorMessages = runtimeValidation.errors.map { $0.description }.joined(separator: "; ")
            throw SpecializerError.specializationFailed(reason: errorMessages)
        }

        // Build metadata and witness table arrays in requirement order.
        //
        // The PWT ordering invariant (still verified by every existing
        // fixture): Swift's `compareDependentTypesRec` orders all GP-rooted
        // requirements before any nested-type-rooted requirement (see
        // `swift/lib/AST/GenericSignature.cpp:846`). That means walking
        // direct-GP requirements in parameter order, then walking associated
        // requirements in canonical merged-requirement order, reconstructs
        // exactly the binary's emission order without an explicit re-sort.
        var metadatas: [Metadata] = []
        var witnessTables: [ProtocolWitnessTable] = []
        var resolvedArguments: [SpecializationResult.ResolvedArgument] = []

        for parameter in request.parameters {
            guard let argument = selection[parameter.name] else {
                throw SpecializerError.specializationFailed(reason: "Missing argument for \(parameter.name)")
            }

            // Resolve metadata for this argument
            let metadata = try resolveMetadata(for: argument, parameterName: parameter.name)
            metadatas.append(metadata)

            // Collect witness tables for protocol requirements (in order)
            var paramWitnessTables: [ProtocolWitnessTable] = []
            for requirement in parameter.requirements {
                if case .protocol(let info) = requirement, info.requiresWitnessTable {
                    let witnessTable = try resolveWitnessTable(
                        for: metadata,
                        conformingTo: info.protocolName,
                        parameterName: parameter.name
                    )
                    witnessTables.append(witnessTable)
                    paramWitnessTables.append(witnessTable)
                }
            }

            resolvedArguments.append(SpecializationResult.ResolvedArgument(
                parameterName: parameter.name,
                metadata: metadata,
                witnessTables: paramWitnessTables
            ))
        }

        // Resolve associated type witness tables (in requirement order, appended after parameter PWTs)
        let metadataByParamName = Dictionary(
            uniqueKeysWithValues: zip(request.parameters.map(\.name), metadatas)
        )
        let associatedTypeWitnesses = try resolveAssociatedTypeWitnesses(
            for: typeDescriptor,
            substituting: metadataByParamName
        )
        witnessTables.append(contentsOf: associatedTypeWitnesses)

        // Defensive invariant — the accessor expects exactly
        // `numKeyArguments` slots (metadatas first, then PWTs in canonical
        // order). If `buildParameters` / `collectRequirements` /
        // `buildAssociatedTypeRequirements` ever miscount, we'd send the
        // wrong number of args and the runtime would fail opaquely.
        // Reject up front with a typed error so the regression is
        // immediately attributable.
        let totalArguments = metadatas.count + witnessTables.count
        guard totalArguments == request.keyArgumentCount else {
            throw SpecializerError.specializationFailed(
                reason: "internal: key argument count mismatch — request expects \(request.keyArgumentCount) (header.numKeyArguments), built \(totalArguments) (\(metadatas.count) metadatas + \(witnessTables.count) witness tables)"
            )
        }

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
            metadatas: metadatas,
            witnessTables: witnessTables,
        )

        return SpecializationResult(
            metadataPointer: response.value,
            resolvedArguments: resolvedArguments
        )
    }

    /// Resolve metadata from a selection argument
    private func resolveMetadata(for argument: SpecializationSelection.Argument, parameterName: String) throws -> Metadata {
        switch argument {
        case .metatype(let type):
            return try Metadata.createInProcess(type)

        case .metadata(let metadata):
            return metadata

        case .candidate(let candidate):
            return try resolveCandidate(candidate, parameterName: parameterName)

        case .specialized(let result):
            return try result.metadata()
        }
    }

    /// Resolve a candidate type to metadata
    private func resolveCandidate(_ candidate: SpecializationRequest.Candidate, parameterName: String) throws -> Metadata {
        // Find the type definition from indexer
        guard let indexer else {
            throw SpecializerError.candidateResolutionFailed(
                candidate: candidate,
                reason: "Indexer not available for candidate resolution"
            )
        }

        // Look up type definition
        guard let typeDefinitionEntry = indexer.allAllTypeDefinitions[candidate.typeName] else {
            throw SpecializerError.candidateResolutionFailed(
                candidate: candidate,
                reason: "Type not found in indexer"
            )
        }

        let typeDefinition = typeDefinitionEntry.value
        let typeContext = typeDefinition.type.typeContextDescriptorWrapper.typeContextDescriptor

        // Generic candidates need nested specialization; surface a typed error
        // rather than letting the no-argument accessor call below fail with
        // a generic message.
        if let genericContext = try typeContext.genericContext(in: typeDefinitionEntry.machO) {
            throw SpecializerError.candidateRequiresNestedSpecialization(
                candidate: candidate,
                parameterCount: Int(genericContext.header.numParams)
            )
        }

        // Get accessor function from type definition's type context
        let accessorFunction = try typeContext.metadataAccessorFunction(in: typeDefinitionEntry.machO)
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
    public enum SpecializerError: Error, LocalizedError {
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
            }
        }
    }
}
