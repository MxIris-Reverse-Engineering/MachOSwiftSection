import Foundation
import MachOSwiftSection
import MachOKit
import Demangling
import OrderedCollections
@_spi(Internals) import SwiftInspection

// MARK: - GenericSpecializer

/// Specializer for generic Swift types
///
/// Provides an interactive API for specializing generic types:
/// 1. Call `makeRequest(for:)` to get parameters and candidate types
/// 2. User selects concrete types for each parameter
/// 3. Call `specialize(_:with:)` to execute specialization
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
    /// - Parameter type: The generic type descriptor
    /// - Returns: A request containing parameters, requirements, and candidate types
    /// - Throws: If the type is not generic or cannot be analyzed
    public func makeRequest(for type: TypeContextDescriptorWrapper) throws -> SpecializationRequest {
        let genericContext = try genericContext(for: type)

        // Build parameters from generic context
        let parameters = try buildParameters(from: genericContext, for: type)

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

    /// Build parameter list from generic context
    private func buildParameters(from genericContext: GenericContext, for type: TypeContextDescriptorWrapper) throws -> [SpecializationRequest.Parameter] {
        var parameters: [SpecializationRequest.Parameter] = []

        // Process parameters at each depth level
        for (depth, levelParams) in genericContext.allParameters.enumerated() {
            for (index, param) in levelParams.enumerated() {
                // Skip non-key parameters (type packs, values, etc.)
                guard param.hasKeyArgument, param.kind == .type else { continue }

                // Get parameter name based on depth and index (e.g., A, B, A1, B1, A2...)
                let paramName = genericParameterName(depth: depth.cast(), index: index.cast())

                // Collect requirements for this parameter (ordered for PWT passing)
                let requirements = try collectRequirements(
                    for: paramName,
                    from: genericContext.allRequirements.flatMap { $0 },
                    parameterIndex: index,
                    depth: depth
                )

                // Find candidate types that satisfy all protocol requirements
                let protocolRequirements = requirements.compactMap { requirement -> ProtocolName? in
                    if case .protocol(let info) = requirement {
                        return info.protocolName
                    }
                    return nil
                }

                let candidates = findCandidates(satisfying: protocolRequirements)

                parameters.append(SpecializationRequest.Parameter(
                    name: paramName,
                    index: index,
                    depth: depth,
                    requirements: requirements,
                    candidates: candidates
                ))
            }
        }

        return parameters
    }

    /// Collect requirements for a specific parameter (ordered for PWT passing)
    private func collectRequirements(
        for paramName: String,
        from genericRequirements: [GenericRequirementDescriptor],
        parameterIndex: Int,
        depth: Int
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
            guard protocolNode.kind == .type else { return nil }
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

        case .sameConformance, .sameShape, .invertedProtocols:
            // These are more advanced requirements that we don't need for basic specialization
            return nil
        }
    }

    /// Convert runtime layout kind to our model
    private func convertLayoutKind(_ kind: GenericRequirementLayoutKind) -> SpecializationRequest.LayoutKind {
        switch kind {
        case .class:
            return .class
        }
    }

    /// Build associated type requirements (ordered for PWT passing)
    private func buildAssociatedTypeRequirements(
        from genericContext: GenericContext,
        for type: TypeContextDescriptorWrapper
    ) throws -> [SpecializationRequest.AssociatedTypeRequirement] {
        var associatedTypeRequirements: [SpecializationRequest.AssociatedTypeRequirement] = []
        let genericRequirements = genericContext.allRequirements.flatMap { $0 }

        for genericRequirement in genericRequirements {
            let mangledParamName = try genericRequirement.paramMangledName(in: machO)
            let paramNode = try MetadataReader.demangleType(for: mangledParamName, in: machO)

            // Only handle dependent-member chains here; direct GP requirements
            // are collected per parameter in `collectRequirements`.
            guard let pathInfo = Self.extractAssociatedPath(of: paramNode), !pathInfo.steps.isEmpty else {
                continue
            }

            // Build requirement for this associated type
            if let requirement = try buildRequirement(from: genericRequirement) {
                associatedTypeRequirements.append(SpecializationRequest.AssociatedTypeRequirement(
                    parameterName: pathInfo.baseParamName,
                    path: pathInfo.steps.map(\.name),
                    requirements: [requirement]
                ))
            }
        }

        return associatedTypeRequirements
    }

    /// Find candidate types that satisfy all protocol constraints
    private func findCandidates(satisfying protocols: [ProtocolName]) -> [SpecializationRequest.Candidate] {
        guard !protocols.isEmpty else {
            // No constraints - return all indexed types
            return conformanceProvider.allTypeNames.compactMap { typeName -> SpecializationRequest.Candidate? in
                guard conformanceProvider.typeDefinition(for: typeName) != nil else {
                    return nil
                }
                let imagePath = conformanceProvider.imagePath(for: typeName) ?? ""
                return SpecializationRequest.Candidate(
                    typeName: typeName,
                    source: .image(imagePath)
                )
            }
        }

        // Find types conforming to all protocols
        let conformingTypes = conformanceProvider.types(conformingToAll: protocols)

        return conformingTypes.compactMap { typeName -> SpecializationRequest.Candidate? in
            guard conformanceProvider.typeDefinition(for: typeName) != nil else {
                return nil
            }
            let imagePath = conformanceProvider.imagePath(for: typeName) ?? ""
            return SpecializationRequest.Candidate(
                typeName: typeName,
                source: .image(imagePath)
            )
        }
    }
}

// MARK: - Validation

@_spi(Support)
extension GenericSpecializer {

    /// Validate a selection against a request
    ///
    /// - Parameters:
    ///   - selection: The user's type selections
    ///   - request: The specialization request
    /// - Returns: Validation result with any errors or warnings
    public func validate(selection: SpecializationSelection, for request: SpecializationRequest) -> SpecializationValidation {
        let builder = SpecializationValidation.builder()

        // Check all required parameters are provided
        for parameter in request.parameters {
            guard selection.hasArgument(for: parameter.name) else {
                builder.addError(.missingArgument(parameterName: parameter.name))
                continue
            }

            // Validate each requirement for this parameter
            // Note: We don't validate all requirements here since some require runtime resolution
            // Full validation happens during specialize()
        }

        // Check for extra arguments
        for paramName in selection.selectedParameterNames {
            if !request.parameters.contains(where: { $0.name == paramName }) {
                builder.addWarning(.extraArgument(parameterName: paramName))
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
    /// - Returns: Specialized metadata result
    /// - Throws: If specialization fails
    public func specialize(_ request: SpecializationRequest, with selection: SpecializationSelection) throws -> SpecializationResult {
        let typeDescriptor = request.typeDescriptor.asPointerWrapper(in: machO)
        // Validate selection first
        let validation = validate(selection: selection, for: request)
        guard validation.isValid else {
            let errorMessages = validation.errors.map { $0.description }.joined(separator: "; ")
            throw SpecializerError.specializationFailed(reason: errorMessages)
        }

        // Build metadata and witness table arrays in requirement order
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
        for (_, pwts) in associatedTypeWitnesses {
            witnessTables.append(contentsOf: pwts)
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
            request: .completeAndBlocking,
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

        // Get accessor function from type definition's type context
        let accessorFunction = try typeDefinition.type.typeContextDescriptorWrapper.typeContextDescriptor.metadataAccessorFunction(in: typeDefinitionEntry.machO)
        guard let accessorFunction else {
            throw SpecializerError.candidateResolutionFailed(
                candidate: candidate,
                reason: "Cannot get metadata accessor function"
            )
        }

        // For non-generic types, just call the accessor
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

    /// Resolve associated type witness tables for a generic type's requirements
    ///
    /// Processes the generic requirements to find associated type constraints (e.g., A.Element: Hashable)
    /// and resolves the corresponding witness tables using runtime functions.
    ///
    /// - Parameters:
    ///   - type: The generic type descriptor
    ///   - genericArguments: Mapping from parameter name to resolved metadata
    /// - Returns: Ordered dictionary mapping associated type metadata to their witness tables
    func resolveAssociatedTypeWitnesses(
        for type: TypeContextDescriptorWrapper,
        substituting genericArguments: [String: Metadata]
    ) throws -> OrderedDictionary<Metadata, [ProtocolWitnessTable]> {
        guard let indexer else {
            throw AssociatedTypeResolutionError.missingIndexer
        }

        var results: OrderedDictionary<Metadata, [ProtocolWitnessTable]> = [:]

        guard let genericContextInProcess = try type.genericContext() else {
            throw AssociatedTypeResolutionError.missingGenericContext(typeDescriptor: type)
        }

        if let unsupportedParameter = genericContextInProcess.parameters.first(where: { $0.kind == .typePack || $0.kind == .value }) {
            throw AssociatedTypeResolutionError.unsupportedGenericParameter(parameterKind: unsupportedParameter.kind)
        }

        let requirements = try genericContextInProcess.requirements.map { try GenericRequirement(descriptor: $0) }
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

            results[currentMetadata, default: []].append(associatedTypePWT)
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
        case missingGenericContext
        case invalidParameterIndex(index: Int, max: Int)
        case requirementParsingFailed(reason: String)
        case candidateResolutionFailed(candidate: SpecializationRequest.Candidate, reason: String)
        case metadataCreationFailed(typeName: String, reason: String)
        case witnessTableNotFound(typeName: String, protocolName: String)
        case specializationFailed(reason: String)

        public var errorDescription: String? {
            switch self {
            case .notGenericType(let type):
                return "Type is not generic: \(type)"
            case .missingGenericContext:
                return "Missing generic context"
            case .invalidParameterIndex(let index, let max):
                return "Invalid parameter index \(index), maximum is \(max)"
            case .requirementParsingFailed(let reason):
                return "Failed to parse requirement: \(reason)"
            case .candidateResolutionFailed(let candidate, let reason):
                return "Failed to resolve candidate \(candidate.typeName.name): \(reason)"
            case .metadataCreationFailed(let typeName, let reason):
                return "Failed to create metadata for \(typeName): \(reason)"
            case .witnessTableNotFound(let typeName, let protocolName):
                return "Witness table not found for \(typeName) conforming to \(protocolName)"
            case .specializationFailed(let reason):
                return "Specialization failed: \(reason)"
            }
        }
    }
}
