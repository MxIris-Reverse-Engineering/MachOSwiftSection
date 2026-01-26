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
    /// - Returns: A request containing parameters, constraints, and candidate types
    /// - Throws: If the type is not generic or cannot be analyzed
    public func makeRequest(for type: TypeContextDescriptorWrapper) throws -> SpecializationRequest {
        let genericContext = try getGenericContext(for: type)

        // Build parameters from generic context
        let parameters = try buildParameters(from: genericContext, for: type)

        // Build associated type constraints
        let associatedTypeConstraints = try buildAssociatedTypeConstraints(from: genericContext, for: type)

        return SpecializationRequest(
            typeDescriptor: type,
            parameters: parameters,
            associatedTypeConstraints: associatedTypeConstraints,
            keyArgumentCount: Int(genericContext.header.numKeyArguments)
        )
    }

    /// Get generic context for a type descriptor
    private func getGenericContext(for type: TypeContextDescriptorWrapper) throws -> GenericContext {
        guard let genericContext = try type.genericContext(in: machO) else {
            throw SpecializerError.notGenericType(type: type)
        }
        return genericContext
    }

    /// Build parameter list from generic context
    private func buildParameters(from genericContext: GenericContext, for type: TypeContextDescriptorWrapper) throws -> [SpecializationRequest.Parameter] {
        var parameters: [SpecializationRequest.Parameter] = []
        var parameterIndex = 0

        // Process parameters at each depth level
        for (depth, levelParams) in genericContext.allParameters.enumerated() {
            for param in levelParams {
                // Skip non-key parameters (type packs, values, etc.)
                guard param.hasKeyArgument, param.kind == .type else { continue }

                // Get parameter name from demangled signature
                let paramName = parameterName(index: parameterIndex, depth: depth)

                // Collect constraints for this parameter
                let constraints = try collectConstraints(
                    for: paramName,
                    from: genericContext.allRequirements.flatMap { $0 },
                    parameterIndex: parameterIndex,
                    depth: depth
                )

                // Find candidate types that satisfy all protocol constraints
                let protocolConstraints = constraints.compactMap { constraint -> ProtocolName? in
                    if case .protocol(let info) = constraint {
                        return info.protocolName
                    }
                    return nil
                }

                let candidates = findCandidates(satisfying: protocolConstraints)

                parameters.append(SpecializationRequest.Parameter(
                    name: paramName,
                    index: parameterIndex,
                    depth: depth,
                    constraints: constraints,
                    candidates: candidates
                ))

                parameterIndex += 1
            }
        }

        return parameters
    }

    /// Generate parameter name based on index and depth
    private func parameterName(index: Int, depth: Int) -> String {
        // Standard Swift naming: T, U, V, W, then T1, U1, etc.
        let baseNames = ["T", "U", "V", "W", "X", "Y", "Z"]
        let cycle = index / baseNames.count
        let position = index % baseNames.count
        let baseName = baseNames[position]
        return cycle == 0 ? baseName : "\(baseName)\(cycle)"
    }

    /// Collect constraints for a specific parameter
    private func collectConstraints(
        for paramName: String,
        from requirements: [GenericRequirementDescriptor],
        parameterIndex: Int,
        depth: Int
    ) throws -> [SpecializationRequest.Constraint] {
        var constraints: [SpecializationRequest.Constraint] = []

        for requirement in requirements {
            // Get the mangled param name and demangle it
            let mangledParamName = try requirement.paramMangledName(in: machO)
            let paramNode = try MetadataReader.demangleType(for: mangledParamName, in: machO)

            // Check if this requirement applies to our parameter
            guard let dependentGenericParamType = paramNode.first(of: .dependentGenericParamType) else {
                // This might be an associated type constraint - handle separately
                continue
            }

            guard let nodeParamName = dependentGenericParamType.text, nodeParamName == paramName else {
                continue
            }

            // Build constraint based on kind
            let constraint = try buildConstraint(from: requirement)
            if let constraint = constraint {
                constraints.append(constraint)
            }
        }

        return constraints
    }

    /// Build a constraint from a requirement descriptor
    private func buildConstraint(from requirement: GenericRequirementDescriptor) throws -> SpecializationRequest.Constraint? {
        let flags = requirement.layout.flags

        switch flags.kind {
        case .protocol:
            let resolvedContent = try requirement.resolvedContent(in: machO)
            guard case .protocol(let protocolRef) = resolvedContent,
                  let resolved = protocolRef.resolved else {
                return nil
            }

            // Try to get protocol name
            let protocolName: ProtocolName
            if let swiftProto = resolved.swift {
                let proto = try MachOSwiftSection.Protocol(descriptor: swiftProto, in: machO)
                protocolName = try proto.protocolName(in: machO)
            } else if let objcProto = resolved.objc {
                // Create a minimal protocol name for ObjC protocols
                let objcName = try objcProto.name(in: machO)
                let typeNode = Node(kind: .type, children: [
                    Node(kind: .protocol, children: [
                        Node(kind: .module, contents: .text("ObjectiveC")),
                        Node(kind: .identifier, contents: .text(objcName))
                    ])
                ])
                protocolName = ProtocolName(node: typeNode)
            } else {
                return nil
            }

            return .protocol(SpecializationRequest.ProtocolConstraintInfo(
                protocolName: protocolName,
                requiresWitnessTable: flags.contains(.hasKeyArgument)
            ))

        case .sameType:
            let mangledTypeName = try requirement.type(in: machO)
            return .sameType(mangledTypeName: mangledTypeName.rawString)

        case .baseClass:
            let mangledTypeName = try requirement.type(in: machO)
            return .baseClass(mangledTypeName: mangledTypeName.rawString)

        case .layout:
            let resolvedContent = try requirement.resolvedContent(in: machO)
            guard case .layout(let layoutKind) = resolvedContent else {
                return nil
            }
            return .layout(convertLayoutKind(layoutKind))

        case .sameConformance, .sameShape, .invertedProtocols:
            // These are more advanced constraints that we don't need for basic specialization
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

    /// Build associated type constraints
    private func buildAssociatedTypeConstraints(
        from genericContext: GenericContext,
        for type: TypeContextDescriptorWrapper
    ) throws -> [SpecializationRequest.AssociatedTypeConstraint] {
        var constraints: [SpecializationRequest.AssociatedTypeConstraint] = []
        let requirements = genericContext.allRequirements.flatMap { $0 }

        for requirement in requirements {
            let mangledParamName = try requirement.paramMangledName(in: machO)
            let paramNode = try MetadataReader.demangleType(for: mangledParamName, in: machO)

            // Check for dependent member type (associated type constraint)
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

            // Build constraint for this associated type
            if let constraint = try buildConstraint(from: requirement) {
                constraints.append(SpecializationRequest.AssociatedTypeConstraint(
                    parameterName: baseParamName,
                    path: [associatedTypeName],
                    constraints: [constraint]
                ))
            }
        }

        return constraints
    }

    /// Find candidate types that satisfy all protocol constraints
    private func findCandidates(satisfying protocols: [ProtocolName]) -> [SpecializationRequest.Candidate] {
        let machOName = "unknown"

        guard !protocols.isEmpty else {
            // No constraints - return all indexed types
            return conformanceProvider.allTypeNames.compactMap { typeName -> SpecializationRequest.Candidate? in
                guard let definition = conformanceProvider.typeDefinition(for: typeName) else {
                    return nil
                }
                return SpecializationRequest.Candidate(
                    typeName: typeName,
                    kind: definition.typeName.kind,
                    source: .indexed(machOName: machOName),
                    isGeneric: definition.isGeneric,
                    genericParameterNames: definition.isGeneric ? definition.genericParameterNames : nil
                )
            }
        }

        // Find types conforming to all protocols
        let conformingTypes = conformanceProvider.types(conformingToAll: protocols)

        return conformingTypes.compactMap { typeName -> SpecializationRequest.Candidate? in
            guard let definition = conformanceProvider.typeDefinition(for: typeName) else {
                return nil
            }
            return SpecializationRequest.Candidate(
                typeName: typeName,
                kind: definition.typeName.kind,
                source: .indexed(machOName: machOName),
                isGeneric: definition.isGeneric,
                genericParameterNames: definition.isGeneric ? definition.genericParameterNames : nil
            )
        }
    }
}

// MARK: - TypeDefinition Extensions

extension TypeDefinition {
    /// Whether this type is generic
    var isGeneric: Bool {
        !(genericParameterNames?.isEmpty ?? true)
    }

    /// Generic parameter names if available
    var genericParameterNames: [String]? {
        // This would need to be implemented based on the actual TypeDefinition structure
        // For now, return nil as a placeholder
        nil
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
        case constraintParsingFailed(reason: String)
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
            case .constraintParsingFailed(let reason):
                return "Failed to parse constraint: \(reason)"
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
