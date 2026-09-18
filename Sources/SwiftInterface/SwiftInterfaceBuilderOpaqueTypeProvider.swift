import SwiftDeclaration
import SwiftIndexing
import SwiftPrinting
import Demangling
import FoundationToolbox
import MachOKit
import MachOSwiftSection
import Dependencies
@_spi(Internals) import MachOSymbols
import SwiftStdlibToolbox
import SwiftDeclarationRendering
@_spi(Internals) import SwiftInspection

/// Carries the logging floor onto the provider.
///
/// `@Loggable` on a **protocol** rather than on the provider itself: the
/// provider is generic over its `MachO` reader, and applied to a type the
/// macro expands to a static *stored* property, which a generic type cannot
/// have. On a protocol it expands to computed properties in an extension, so
/// the conformer gets `logger` and can use `#log`. Same shape as
/// `OpaqueTypeRewriteLogging` in `SwiftDeclarationRendering`.
@Loggable(.fileprivate, subsystem: "com.machoswiftsection.swift-interface", category: "SwiftInterfaceBuilderOpaqueTypeProvider")
fileprivate protocol OpaqueTypeProviderLogging {}

/// Where a requirement's subject sits in its generic signature — the depth and
/// index a `dependentGenericParamType` carries.
private struct GenericParameterCoordinate: Hashable {
    let depth: Int
    let index: Int

    init(depth: Int, index: Int) {
        self.depth = depth
        self.index = index
    }

    /// nil when the subject is not a plain parameter: a dependent member such
    /// as `τ_1_0.Element` constrains an associated type, not the `some` itself.
    init?(subjectNode: Node) {
        let parameterNode = subjectNode.isKind(of: .type) ? subjectNode[safeChild: 0] : subjectNode
        guard let parameterNode, parameterNode.isKind(of: .dependentGenericParamType),
              let depth = parameterNode[safeChild: 0]?.index,
              let index = parameterNode[safeChild: 1]?.index else { return nil }
        self.depth = Int(depth)
        self.index = Int(index)
    }
}

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
            // `Qr` names the first opaque return type and carries no index;
            // `QR<n>` names the one after the n-th
            // (`ASTMangler::appendOpaqueTypeArchetype`).
            let ordinal = (index ?? -1) + 1
            guard let protocolRequirements = try await protocolRequirements(onOpaqueParameter: ordinal, of: opaqueType, among: requirements, declaredBy: node) else {
                return nil
            }
            let typeRequirements = requirements.filter(\.content.isType)
            let typeRequirementNodes = try typeRequirements.compactMap { try SymbolicDemangler.buildGenericSignature(for: $0, in: machO) }
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
            // A read the reader cannot make (a protocol descriptor bound from
            // another image, an offset outside a cache image) degrades to a
            // bare `some`; say so instead of swallowing it.
            let declaration = await node.print(using: .default)
            #log(.error, "opaque return type of \(declaration, privacy: .public) could not be resolved, rendering a bare `some`: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// The protocol requirements on the opaque parameter at `ordinal`, or nil
    /// when nothing constrains it at runtime.
    ///
    /// Every opaque parameter of a declaration sits at one depth — one below
    /// the deepest depth the declaration inherits or introduces — and its
    /// index IS its ordinal, so the lookup is by coordinate. It used to be by
    /// position in the grouped list, which crashed RuntimeViewer on
    /// `PhotosUIFoundation.PhotosGroupingItemListManager.GroupItem.value`: a
    /// `some Sendable` records no requirement at all (marker protocols never
    /// do), the grouped list was empty, and `elements[0]` trapped. `some Any`
    /// and `some AnyObject` (a layout requirement, not a protocol one) reach
    /// the same state, and all three are legitimate descriptors: the answer is
    /// nil and the printer emits a bare `some`.
    ///
    /// The depth comes from the descriptor, not from the declaration's mangled
    /// signature: a member's signature spells only the depths it adds
    /// (`ASTMangler::appendGenericSignatureParts` skips the context's). It is
    /// the number of enclosing depths — one per parent level that grows the
    /// parameter count, as the runtime's `_gatherGenericParameterCounts`
    /// counts them, so a non-generic nested type adds none — plus one when the
    /// declaration is generic itself, which its type node says (a
    /// `dependentGenericType` wrapper; a constrained extension's signature
    /// sits in the context and does not count).
    ///
    /// A requirement on a parameter beyond that depth cannot exist for a
    /// well-formed image: that is reported as a fault and asserted in debug
    /// builds, and answered with nil in release ones.
    private func protocolRequirements(onOpaqueParameter ordinal: Int, of opaqueType: OpaqueType, among requirements: [GenericRequirementDescriptor], declaredBy node: Node) async throws -> [GenericRequirementDescriptor]? {
        guard let genericContext = opaqueType.genericContext else { return nil }
        guard !genericContext.currentParameters.isEmpty else {
            let declaration = await node.print(using: .default)
            #log(.fault, "opaque type descriptor of \(declaration, privacy: .public) introduces no generic parameter of its own")
            assertionFailure("opaque type descriptor of \(declaration) introduces no generic parameter of its own")
            return nil
        }

        var enclosingDepthCount = 0
        var inheritedParameterCount = 0
        for parameters in genericContext.parentParameters where parameters.count > inheritedParameterCount {
            enclosingDepthCount += 1
            inheritedParameterCount = parameters.count
        }
        let opaqueParameterDepth = enclosingDepthCount + (Self.declaresOwnGenericParameters(node) ? 1 : 0)

        var protocolRequirementsByParameter: [GenericParameterCoordinate: [GenericRequirementDescriptor]] = [:]
        for protocolRequirement in requirements.filter(\.content.isProtocol) {
            guard let coordinate = GenericParameterCoordinate(subjectNode: try await protocolRequirement.dumpParameterName(in: machO)) else { continue }
            guard coordinate.depth <= opaqueParameterDepth else {
                let declaration = await node.print(using: .default)
                #log(.fault, "opaque type descriptor of \(declaration, privacy: .public) constrains parameter τ_\(coordinate.depth, privacy: .public)_\(coordinate.index, privacy: .public), beyond the opaque parameters' depth \(opaqueParameterDepth, privacy: .public)")
                assertionFailure("opaque type descriptor of \(declaration) constrains parameter τ_\(coordinate.depth)_\(coordinate.index), beyond the opaque parameters' depth \(opaqueParameterDepth)")
                return nil
            }
            protocolRequirementsByParameter[coordinate, default: []].append(protocolRequirement)
        }
        return protocolRequirementsByParameter[GenericParameterCoordinate(depth: opaqueParameterDepth, index: ordinal)]
    }

    /// Whether the declaration introduces generic parameters of its own: its
    /// type is wrapped in a `dependentGenericType`. The entity is unwrapped
    /// first so a `static` or accessor wrapper does not hide it; a constrained
    /// extension's signature sits in the context child and is not consulted.
    private static func declaresOwnGenericParameters(_ node: Node) -> Bool {
        let declarationNode = node.first(of: .function, .variable, .subscript) ?? node
        guard let typeNode = declarationNode.children.last, typeNode.isKind(of: .type) else { return false }
        return typeNode[safeChild: 0]?.isKind(of: .dependentGenericType) ?? false
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

extension SwiftInterfaceBuilderOpaqueTypeProvider: OpaqueTypeProviderLogging {}
