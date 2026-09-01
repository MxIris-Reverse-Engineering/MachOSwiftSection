import SwiftDeclaration
import SwiftIndexing
import SwiftPrinting
import Demangling
import MachOKit
import MachOSwiftSection
import Dependencies
import OrderedCollections
@_spi(Internals) import MachOSymbols
import SwiftStdlibToolbox
import SwiftDeclarationRendering
@_spi(Internals) import SwiftInspection

public struct SwiftInterfaceBuilderOpaqueTypeProvider<MachO: MachOSwiftSectionRepresentableWithCache & Sendable>: SwiftInterfaceBuilderExtraDataProvider, OpaqueTypeResolving, Sendable {
    public let machO: MachO

    public init(machO: MachO) {
        self.machO = machO
    }

    public func opaqueType(forNode node: Node, index: Int?) async -> String? {
        do {
            @Dependency(\.symbolIndexStore)
            var symbolIndexStore
            guard let opaqueTypeDescriptorSymbol = symbolIndexStore.opaqueTypeDescriptorSymbol(for: node, in: machO) else { return nil }

            let opaqueType = try OpaqueType(descriptor: OpaqueTypeDescriptor.resolve(from: opaqueTypeDescriptorSymbol.offset, in: machO), in: machO)
            let requirements = try opaqueType.requirements(in: machO)
            var protocolRequirementsByParamType: OrderedDictionary<String, [GenericRequirementDescriptor]> = [:]
            var protocolRequirements = requirements.filter(\.content.isProtocol)
            for protocolRequirement in protocolRequirements {
                let parameterName = try await protocolRequirement.dumpParameterName(resolver: .using(options: .opaqueTypeBuilderOnly), in: machO).string
                protocolRequirementsByParamType[parameterName, default: []].append(protocolRequirement)
            }
            if let index {
                protocolRequirements = protocolRequirementsByParamType.elements[index + 1].value
            } else {
                protocolRequirements = protocolRequirementsByParamType.elements[0].value
            }
            let typeRequirements = requirements.filter(\.content.isType)
            let typeRequirementNodes = try typeRequirements.compactMap { try MetadataReader.buildGenericSignature(for: $0, in: machO) }
            var substitutionMap: SubstitutionMap<Node> = .init()
            var constraintsByParamType: [String: [OpaqueSameTypeConstraint]] = [:]
            for typeRequirementNode in typeRequirementNodes {
                guard let sameTypeRequirementNode = typeRequirementNode.first(of: .dependentGenericSameTypeRequirement) else { continue }
                guard let firstType = sameTypeRequirementNode.children.at(0), let secondType = sameTypeRequirementNode.children.at(1) else { continue }
                if secondType.children.first?.isKind(of: .dependentMemberType) ?? false {
                    // Reversed pin (`outer == τ.Name`): the substitution map
                    // recovers the outer argument at render time.
                    substitutionMap.add(original: firstType, substitution: secondType)
                    guard let projection = await OpaqueDependentMemberProjection.parse(typeNode: secondType) else { continue }
                    constraintsByParamType[projection.parameterName, default: []].append(OpaqueSameTypeConstraint(
                        associatedTypeName: projection.associatedTypeName,
                        anchorProtocolName: projection.anchorProtocolName,
                        argumentSource: .substitutionRoot(secondType)
                    ))
                } else if let projection = await OpaqueDependentMemberProjection.parse(typeNode: firstType) {
                    // Direct pin (`τ.Name == X`).
                    constraintsByParamType[projection.parameterName, default: []].append(OpaqueSameTypeConstraint(
                        associatedTypeName: projection.associatedTypeName,
                        anchorProtocolName: projection.anchorProtocolName,
                        argumentSource: .node(secondType)
                    ))
                }
            }

            let factsResolver = ProtocolFactsResolver(machO: machO)
            var compositionProtocolNames: Set<String> = []
            for protocolRequirement in protocolRequirements {
                try await compositionProtocolNames.insert(protocolRequirement.dumpContent(resolver: .using(options: .opaqueTypeBuilderOnly), in: machO).string)
            }
            var results: [String] = []
            for protocolRequirement in protocolRequirements {
                var result = ""
                let parameterName = try await protocolRequirement.dumpParameterName(resolver: .using(options: .opaqueTypeBuilderOnly), in: machO).string
                let protocolName = try await protocolRequirement.dumpContent(resolver: .using(options: .opaqueTypeBuilderOnly), in: machO).string
                result.write(protocolName)

                let constraints = constraintsByParamType[parameterName] ?? []
                let attachedConstraints = await attributedConstraints(
                    from: constraints,
                    toProtocolNamed: protocolName,
                    inCompositionOf: compositionProtocolNames,
                    requirement: protocolRequirement,
                    factsResolver: factsResolver
                )

                if !attachedConstraints.isEmpty {
                    var primaryAssociatedTypes: [String] = []
                    for attachedConstraint in attachedConstraints {
                        switch attachedConstraint.argumentSource {
                        case .node(let argumentNode):
                            await primaryAssociatedTypes.append(argumentNode.print(using: .opaqueTypeBuilderOnly))
                        case .substitutionRoot(let substitutionNode):
                            await primaryAssociatedTypes.append(substitutionMap.rootOriginal(for: substitutionNode).print(using: .opaqueTypeBuilderOnly))
                        }
                    }
                    result.write("<")
                    result.write(primaryAssociatedTypes.joined(separator: ", "))
                    result.write(">")
                }

                results.append(result)
            }

            return results.joined(separator: " & ")
        } catch {
            return nil
        }
    }

    /// Decides which of the parameter's same-type constraints belong to one
    /// protocol of the composition (the opaque-primary-associated-type-attribution evolution proposal):
    ///
    /// 1. anchor is the protocol itself (identity only — works offline);
    /// 2. anchor lies in the protocol's refine closure;
    /// 3. name fallback for compiler-collapsed equivalence classes: only when
    ///    no anchor matched, the protocol itself declares an associated type
    ///    with the constraint's name, that name has exactly one candidate, and
    ///    the candidate's anchor lies outside the composition — an in-
    ///    composition anchor already owns its sugar, and a same-named member
    ///    that was pinned to it is byte-identical in the descriptor to one
    ///    that was never pinned at all, so attaching would fabricate sugar;
    /// 4. unknown facts (or an ObjC protocol) attach nothing beyond rule 1 —
    ///    a missed parameter beats a fabricated one.
    private func attributedConstraints(
        from constraints: [OpaqueSameTypeConstraint],
        toProtocolNamed protocolName: String,
        inCompositionOf compositionProtocolNames: Set<String>,
        requirement: GenericRequirementDescriptor,
        factsResolver: ProtocolFactsResolver<MachO>
    ) async -> [OpaqueSameTypeConstraint] {
        guard !constraints.isEmpty else { return [] }

        var symbolOrElement: SymbolOrElement<ProtocolDescriptorWithObjCInterop>?
        if let resolvedContent = try? requirement.resolvedContent(in: machO), case .protocol(let element) = resolvedContent {
            symbolOrElement = element
        }
        if case .element(.objc) = symbolOrElement {
            // An ObjC protocol cannot declare Swift associated types.
            return []
        }

        var descriptor: ProtocolDescriptor?
        if case .element(.swift(let swiftDescriptor)) = symbolOrElement {
            descriptor = swiftDescriptor
        }
        let facts = await factsResolver.facts(for: ProtocolReference(qualifiedName: protocolName, descriptor: descriptor))

        var attachedConstraints = constraints.filter { $0.anchorProtocolName == protocolName }

        if attachedConstraints.isEmpty, let facts {
            for constraint in constraints {
                guard let anchorProtocolName = constraint.anchorProtocolName else { continue }
                if await factsResolver.refineClosureContainsAnchor(anchorProtocolName, startingFrom: facts) == true {
                    attachedConstraints.append(constraint)
                }
            }

            if attachedConstraints.isEmpty {
                var handledAssociatedTypeNames: Set<String> = []
                for constraint in constraints {
                    guard facts.declaredAssociatedTypeNames.contains(constraint.associatedTypeName) else { continue }
                    guard handledAssociatedTypeNames.insert(constraint.associatedTypeName).inserted else { continue }
                    let candidates = constraints.filter { $0.associatedTypeName == constraint.associatedTypeName }
                    guard candidates.count == 1, let candidate = candidates.first else { continue }
                    if let anchorProtocolName = candidate.anchorProtocolName, compositionProtocolNames.contains(anchorProtocolName) {
                        continue
                    }
                    attachedConstraints.append(candidate)
                }
            }
        }

        if let primaryAssociatedTypeNames = facts?.primaryAssociatedTypeNames {
            attachedConstraints = attachedConstraints
                .filter { primaryAssociatedTypeNames.contains($0.associatedTypeName) }
                .enumerated()
                .sorted { first, second in
                    let firstPrimaryIndex = primaryAssociatedTypeNames.firstIndex(of: first.element.associatedTypeName) ?? primaryAssociatedTypeNames.count
                    let secondPrimaryIndex = primaryAssociatedTypeNames.firstIndex(of: second.element.associatedTypeName) ?? primaryAssociatedTypeNames.count
                    return (firstPrimaryIndex, first.offset) < (secondPrimaryIndex, second.offset)
                }
                .map(\.element)
        }

        return attachedConstraints
    }
}
