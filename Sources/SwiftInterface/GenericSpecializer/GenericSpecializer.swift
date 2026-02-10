import Foundation
import MachOSwiftSection
import MachOKit
import Demangling
import OrderedCollections
import SwiftInspection

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
            guard genericRequirement.flags.contains(.hasKeyArgument) else { continue }
            // Get the mangled param name and demangle it
            let mangledParamName = try genericRequirement.paramMangledName(in: machO)
            let paramNode = try MetadataReader.demangleType(for: mangledParamName, in: machO)

            // Check if this requirement applies to our parameter
            guard let dependentGenericParamType = paramNode.first(of: .dependentGenericParamType) else {
                // This might be an associated type requirement - handle separately
                continue
            }

            guard let nodeParamName = dependentGenericParamType.text, nodeParamName == paramName else {
                continue
            }

            // Build requirement based on kind
            let requirement = try buildRequirement(from: genericRequirement)
            if let requirement = requirement {
                requirements.append(requirement)
            }
        }

        return requirements
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

            // Check for dependent member type (associated type requirement)
            guard let dependentMemberType = paramNode.first(of: .dependentMemberType) else {
                continue
            }

            // Get base parameter name
            guard let dependentGenericParamType = dependentMemberType.first(of: .dependentGenericParamType),
                  let baseParamName = dependentGenericParamType.text else {
                continue
            }

            // Get associated type path
            guard let dependentAssociatedTypeRef = dependentMemberType.first(of: .dependentAssociatedTypeRef),
                  let associatedTypeName = dependentAssociatedTypeRef.children.first?.text else {
                continue
            }

            // Build requirement for this associated type
            if let requirement = try buildRequirement(from: genericRequirement) {
                associatedTypeRequirements.append(SpecializationRequest.AssociatedTypeRequirement(
                    parameterName: baseParamName,
                    path: [associatedTypeName],
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
        var conformingTypeMetadataByGenericParam: [String: Metadata] = [:]
        let allProtocolDefinitions = indexer.allAllProtocolDefinitions

        for requirement in requirements {
            guard let requirementProtocolDescriptor = requirement.content.protocol?.resolved,
                  let protocolDescriptor = requirementProtocolDescriptor.swift,
                  requirement.flags.contains(.hasKeyArgument) else { continue }

            let requirementProtocol = try MachOSwiftSection.`Protocol`(descriptor: protocolDescriptor)
            let paramNode = try MetadataReader.demangleType(for: requirement.paramManagledName)

            if let dependentMemberType = paramNode.first(of: .dependentMemberType) {
                // Associated type requirement (e.g., A.Element: Hashable)
                guard let dependentGenericParamType = dependentMemberType.first(of: .dependentGenericParamType) else {
                    throw AssociatedTypeResolutionError.missingDependentGenericParamType(dependentMemberType: dependentMemberType)
                }

                guard let genericParamType = dependentGenericParamType.text else {
                    throw AssociatedTypeResolutionError.missingGenericParamTypeText(dependentGenericParamType: dependentGenericParamType)
                }

                guard let conformingTypeMetadata = conformingTypeMetadataByGenericParam[genericParamType] else {
                    throw AssociatedTypeResolutionError.missingConformingTypeMetadata(
                        genericParam: genericParamType,
                        availableParams: Array(conformingTypeMetadataByGenericParam.keys)
                    )
                }

                guard let dependentAssociatedTypeRef = dependentMemberType.first(of: .dependentAssociatedTypeRef) else {
                    throw AssociatedTypeResolutionError.missingDependentAssociatedTypeRef(dependentMemberType: dependentMemberType)
                }

                guard let associatedTypeName = dependentAssociatedTypeRef.children.first?.text else {
                    throw AssociatedTypeResolutionError.missingAssociatedTypeName(dependentAssociatedTypeRef: dependentAssociatedTypeRef)
                }

                guard let associatedTypeRefProtocolTypeNode = dependentAssociatedTypeRef.children.second else {
                    throw AssociatedTypeResolutionError.missingAssociatedTypeRefProtocolTypeNode(dependentAssociatedTypeRef: dependentAssociatedTypeRef)
                }

                guard let associatedTypeRefMachOAndProtocol = allProtocolDefinitions[.init(node: associatedTypeRefProtocolTypeNode)] else {
                    throw AssociatedTypeResolutionError.missingAssociatedTypeRefMachOAndProtocol(protocolTypeNode: associatedTypeRefProtocolTypeNode)
                }

                let associatedTypeRefProtocol: MachOSwiftSection.`Protocol`
                do {
                    associatedTypeRefProtocol = try MachOSwiftSection.`Protocol`(
                        descriptor: associatedTypeRefMachOAndProtocol.value.protocol.descriptor.asPointerWrapper(in: associatedTypeRefMachOAndProtocol.machO)
                    )
                } catch {
                    throw AssociatedTypeResolutionError.failedToCreateAssociatedTypeRefProtocol(underlyingError: error)
                }

                let associatedTypeRefProtocolName = try associatedTypeRefProtocol.protocolName()
                let availableAssociatedTypes = try associatedTypeRefProtocol.descriptor.associatedTypes()

                guard let associatedTypeIndex = availableAssociatedTypes.firstIndex(of: associatedTypeName) else {
                    throw AssociatedTypeResolutionError.missingAssociatedTypeIndex(
                        associatedTypeName: associatedTypeName,
                        protocolName: associatedTypeRefProtocolName,
                        availableAssociatedTypes: availableAssociatedTypes
                    )
                }

                guard let associatedTypeBaseRequirement = associatedTypeRefProtocol.baseRequirement else {
                    throw AssociatedTypeResolutionError.missingAssociatedTypeBaseRequirement(protocolName: associatedTypeRefProtocolName)
                }

                let associatedTypeAccessFunctionRequirements = associatedTypeRefProtocol.requirements.filter {
                    $0.flags.kind.isAssociatedTypeAccessFunction
                }

                guard let associatedTypeAccessFunctionRequirement = associatedTypeAccessFunctionRequirements[safe: associatedTypeIndex] else {
                    throw AssociatedTypeResolutionError.missingAssociatedTypeAccessFunctionRequirement(
                        index: associatedTypeIndex,
                        protocolName: associatedTypeRefProtocolName,
                        requirementCount: associatedTypeAccessFunctionRequirements.count
                    )
                }

                guard let conformingTypePWT = try RuntimeFunctions.conformsToProtocol(
                    metadata: conformingTypeMetadata,
                    protocolDescriptor: associatedTypeRefProtocol.descriptor
                ) else {
                    throw AssociatedTypeResolutionError.conformingTypeDoesNotConformToProtocol(
                        conformingType: conformingTypeMetadata,
                        protocolName: associatedTypeRefProtocolName
                    )
                }

                guard let associatedTypeMetadata = try? RuntimeFunctions.getAssociatedTypeWitness(
                    request: .init(),
                    protocolWitnessTable: conformingTypePWT,
                    conformingTypeMetadata: conformingTypeMetadata,
                    baseRequirement: associatedTypeBaseRequirement,
                    associatedTypeRequirement: associatedTypeAccessFunctionRequirement
                ).value.resolve().metadata else {
                    throw AssociatedTypeResolutionError.failedToGetAssociatedTypeWitness(
                        conformingType: conformingTypeMetadata,
                        protocolName: associatedTypeRefProtocolName,
                        associatedTypeName: associatedTypeName
                    )
                }

                let currentProtocolName = try requirementProtocol.protocolName()

                guard let associatedTypePWT = try? RuntimeFunctions.conformsToProtocol(
                    metadata: associatedTypeMetadata,
                    protocolDescriptor: requirementProtocol.descriptor
                ) else {
                    throw AssociatedTypeResolutionError.associatedTypeDoesNotConformToProtocol(
                        associatedType: associatedTypeMetadata,
                        protocolName: currentProtocolName
                    )
                }

                results[associatedTypeMetadata, default: []].append(associatedTypePWT)

            } else if let dependentGenericParamType = paramNode.first(of: .dependentGenericParamType) {
                // Direct generic parameter - record metadata mapping
                guard let genericParamType = dependentGenericParamType.text else {
                    throw AssociatedTypeResolutionError.missingGenericParamTypeText(dependentGenericParamType: dependentGenericParamType)
                }

                guard let conformingTypeMetadata = genericArguments[genericParamType] else {
                    throw AssociatedTypeResolutionError.missingConformingTypeMetadata(
                        genericParam: genericParamType,
                        availableParams: Array(genericArguments.keys)
                    )
                }

                conformingTypeMetadataByGenericParam[genericParamType] = conformingTypeMetadata
            } else {
                throw AssociatedTypeResolutionError.unknownParamNodeStructure(paramNode: paramNode)
            }
        }

        return results
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
