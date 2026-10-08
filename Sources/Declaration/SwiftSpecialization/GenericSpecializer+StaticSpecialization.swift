@_spi(Support) import SwiftIndexing
import SwiftDeclaration
import SwiftDeclarationRendering
import Foundation
import MachOSwiftSection
import MachOKit
@_spi(Internals) import Demangling
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection
#if canImport(ObjectiveC)
import ObjectiveC
#endif

// MARK: - Offline Execution

/// Specialization without the runtime (evolution proposal
/// `offline-generic-specialization`), for a type read from a file — what
/// RuntimeViewer's offline mode browses. Nothing in the target image runs: an
/// argument is a type node, never metadata, and the result is the
/// instantiation's name and the argument of every parameter, which the
/// interface printer and the static layout engine turn into a bound
/// declaration with its layout.
@_spi(Support)
extension GenericSpecializer where MachO == MachOFile {
    /// Specializes the request's type offline.
    ///
    /// An argument stands for a type node: a `.candidate` for its name, a
    /// `.boundGeneric` for the inner type specialized the same way, and a
    /// `.metatype` / `.metadata` / `.specialized` for the name this process's
    /// runtime gives it — the host's type, read without calling anything in
    /// the target image.
    ///
    /// Throws what the runtime path throws for the same mistakes: the static
    /// validation's errors and `staticPreflight`'s as `specializationFailed`,
    /// a generic `.candidate` as `candidateRequiresNestedSpecialization`. A
    /// requirement offline evidence cannot settle is not an error; ask
    /// `staticPreflight` for the warnings.
    public func specialize(
        _ request: SpecializationRequest,
        with selection: SpecializationSelection
    ) throws -> StaticSpecializationResult {
        try internalStaticSpecialize(request, with: selection, depth: 0)
    }

    /// The offline counterpart of `runtimePreflight(selection:for:)`: checks
    /// the selection against the type's requirements with the evidence a file
    /// carries.
    ///
    /// Two outcomes per requirement, because offline evidence is incomplete:
    ///
    /// - **An error** when the requirement is provably violated: an
    ///   `AnyObject` parameter given a struct or an enum; a class known to
    ///   the indexer outside the required base class's subtree; a same-type
    ///   requirement whose two sides resolve to different types.
    /// - **A warning** when it cannot be proved either way: a conformance the
    ///   indexed images do not record (it may be conditional, declared in an
    ///   image the indexer does not hold, or synthesized by the runtime); a
    ///   member of an associated type no witness record projects; a base
    ///   class the indexer knows no hierarchy for.
    ///
    /// Arguments of `.boundGeneric` are specialized and checked in turn, their
    /// diagnostics named by dotted parameter path.
    public func staticPreflight(
        selection: SpecializationSelection,
        for request: SpecializationRequest
    ) -> SpecializationValidation {
        let builder = SpecializationValidation.builder()
        let resolution = resolveStaticArguments(for: request, with: selection, parameterPathPrefix: "", depth: 0)
        resolution.errors.forEach { builder.addError($0) }
        resolution.warnings.forEach { builder.addWarning($0) }
        checkStaticRequirements(of: request, with: resolution, parameterPathPrefix: "", into: builder)
        return builder.build()
    }
}

// MARK: - Internals

extension GenericSpecializer where MachO == MachOFile {
    /// What each selected argument stands for, resolved once per
    /// specialization: the requirement checks and the result both read it,
    /// and a `.boundGeneric` argument is specialized exactly once per level.
    struct StaticArgumentResolution {
        struct ResolvedArgument {
            /// The argument, `.type`-wrapped.
            let node: Node

            /// The nominal type the argument instantiates, as the indexer
            /// names it — what conformance and subclass lookups key on.
            let nominalTypeName: TypeName?

            let innerResult: StaticSpecializationResult?

            /// The type itself when the host process supplied it: its kind
            /// and superclass chain are then known exactly.
            let hostMetatype: Any.Type?
        }

        var arguments: [String: ResolvedArgument] = [:]
        var errors: [SpecializationValidation.Error] = []
        var warnings: [SpecializationValidation.Warning] = []
    }

    func internalStaticSpecialize(
        _ request: SpecializationRequest,
        with selection: SpecializationSelection,
        depth: Int
    ) throws -> StaticSpecializationResult {
        let staticValidation = internalValidate(selection: selection, for: request, parameterPathPrefix: "", depth: depth)
        guard staticValidation.isValid else {
            throw SpecializerError.specializationFailed(reason: staticValidation.errors.map(\.description).joined(separator: "; "))
        }

        // The runtime path's typed error for a generic candidate, raised
        // before anything else as there: it needs `.boundGeneric`.
        for parameter in request.parameters {
            guard case .candidate(let candidate) = selection[parameter.name] else { continue }
            try requireNonGenericCandidate(candidate)
        }

        let resolution = resolveStaticArguments(for: request, with: selection, parameterPathPrefix: "", depth: depth)
        let builder = SpecializationValidation.builder()
        resolution.errors.forEach { builder.addError($0) }
        checkStaticRequirements(of: request, with: resolution, parameterPathPrefix: "", into: builder)
        let validation = builder.build()
        guard validation.isValid else {
            throw SpecializerError.specializationFailed(reason: validation.errors.map(\.description).joined(separator: "; "))
        }

        return try staticResult(for: request, with: selection, resolution: resolution)
    }

    private func requireNonGenericCandidate(_ candidate: SpecializationRequest.Candidate) throws {
        let (descriptor, candidateMachO) = try resolveCandidateDescriptor(candidate)
        if let genericContext = try descriptor.typeContextDescriptor.genericContext(in: candidateMachO.context) {
            throw SpecializerError.candidateRequiresNestedSpecialization(
                candidate: candidate,
                parameterCount: Int(genericContext.header.numParams)
            )
        }
    }

    /// The result for arguments that passed every check: the arguments of
    /// every parameter — the fixed ones recovered from their same-type
    /// requirements — and the instantiation's name.
    private func staticResult(
        for request: SpecializationRequest,
        with selection: SpecializationSelection,
        resolution: StaticArgumentResolution
    ) throws -> StaticSpecializationResult {
        var keyArguments: [Node] = []
        var resolvedArguments: [StaticSpecializationResult.ResolvedArgument] = []
        for parameter in request.parameters {
            guard let argument = resolution.arguments[parameter.name] else {
                throw SpecializerError.specializationFailed(reason: "Missing argument for \(parameter.name)")
            }
            keyArguments.append(argument.node)
            resolvedArguments.append(.init(parameterName: parameter.name, argumentNode: argument.node, innerResult: argument.innerResult))
        }

        let instantiation: GenericInstantiation
        do {
            instantiation = try GenericInstantiation(of: request.typeDescriptor, keyArguments: keyArguments, in: machO)
        } catch {
            throw SpecializerError.specializationFailed(reason: "could not bind the type's parameters: \((error as? LocalizedError)?.errorDescription ?? "\(error)")")
        }
        let typeName = TypeName(
            node: InternedNodeReferenceCache.shared.reference(interning: instantiation.typeNode, in: machO),
            kind: request.typeDescriptor.kind
        )
        return StaticSpecializationResult(
            typeDescriptor: request.typeDescriptor,
            typeName: typeName,
            binding: instantiation.binding,
            selection: selection,
            resolvedArguments: resolvedArguments
        )
    }

    // MARK: Argument resolution

    func resolveStaticArguments(
        for request: SpecializationRequest,
        with selection: SpecializationSelection,
        parameterPathPrefix: String,
        depth: Int
    ) -> StaticArgumentResolution {
        var resolution = StaticArgumentResolution()
        for parameter in request.parameters {
            guard let argument = selection[parameter.name] else { continue }
            let parameterPath = Self.joinedPath(parameterPathPrefix, parameter.name)
            switch argument {
            case .candidate(let candidate):
                resolution.arguments[parameter.name] = .init(
                    node: typeWrappedNode(candidate.typeName.node.materialize()),
                    nominalTypeName: candidate.typeName,
                    innerResult: nil,
                    hostMetatype: nil
                )
            case .boundGeneric(let baseCandidate, let innerArguments):
                let outcome = staticBoundGenericOutcome(
                    baseCandidate: baseCandidate,
                    innerArguments: innerArguments,
                    parameterPath: parameterPath,
                    depth: depth
                )
                resolution.errors.append(contentsOf: outcome.errors)
                resolution.warnings.append(contentsOf: outcome.warnings)
                if let innerResult = outcome.result {
                    resolution.arguments[parameter.name] = .init(
                        node: innerResult.typeName.node.materialize(),
                        nominalTypeName: baseCandidate.typeName,
                        innerResult: innerResult,
                        hostMetatype: nil
                    )
                }
            case .metatype(let type):
                resolveHostArgument(type, parameterName: parameter.name, parameterPath: parameterPath, into: &resolution)
            case .metadata(let metadata):
                do {
                    resolveHostArgument(unsafeBitCast(try metadata.asPointer, to: Any.Type.self), parameterName: parameter.name, parameterPath: parameterPath, into: &resolution)
                } catch {
                    resolution.errors.append(.metadataResolutionFailed(parameterName: parameterPath, reason: "\(error)"))
                }
            case .specialized(let result):
                do {
                    resolveHostArgument(unsafeBitCast(try result.metadata().asPointer, to: Any.Type.self), parameterName: parameter.name, parameterPath: parameterPath, into: &resolution)
                } catch {
                    resolution.errors.append(.metadataResolutionFailed(parameterName: parameterPath, reason: "\(error)"))
                }
            }
        }
        return resolution
    }

    /// A type the host process supplied, named the way this process's runtime
    /// names it — the source the runtime path's own headers and field types
    /// are printed from, so both paths spell the argument alike.
    private func resolveHostArgument(_ type: Any.Type, parameterName: String, parameterPath: String, into resolution: inout StaticArgumentResolution) {
        guard let node = RuntimeTypeNameDemangling.node(forMetatype: type) else {
            resolution.errors.append(.metadataResolutionFailed(parameterName: parameterPath, reason: "this process's runtime has no name for \(type)"))
            return
        }
        let argumentNode = typeWrappedNode(node)
        resolution.arguments[parameterName] = .init(
            node: argumentNode,
            nominalTypeName: unboundNominalTypeName(of: argumentNode),
            innerResult: nil,
            hostMetatype: type
        )
    }

    /// Specializes a `.boundGeneric` argument with an inner specializer bound
    /// to the candidate's image, collecting the inner diagnostics under the
    /// argument's parameter path. Each level resolves its own arguments
    /// once, so the work stays linear in the nesting depth.
    private func staticBoundGenericOutcome(
        baseCandidate: SpecializationRequest.Candidate,
        innerArguments: [String: SpecializationSelection.Argument],
        parameterPath: String,
        depth: Int
    ) -> (result: StaticSpecializationResult?, errors: [SpecializationValidation.Error], warnings: [SpecializationValidation.Warning]) {
        if depth >= maxBindingDepth {
            return (nil, [.metadataResolutionFailed(parameterName: parameterPath, reason: "binding depth exceeded (maxBindingDepth = \(maxBindingDepth))")], [])
        }
        let inner: (descriptor: TypeContextDescriptorWrapper, specializer: GenericSpecializer<MachO>)
        do {
            inner = try makeInnerContext(for: baseCandidate)
        } catch {
            return (nil, [.metadataResolutionFailed(parameterName: parameterPath, reason: "\(error)")], [])
        }
        let innerRequest: SpecializationRequest
        do {
            innerRequest = try inner.specializer.makeRequest(for: inner.descriptor)
        } catch {
            return (nil, [.metadataResolutionFailed(parameterName: parameterPath, reason: "could not build inner request: \(error)")], [])
        }

        let innerSelection = SpecializationSelection(arguments: innerArguments)
        let innerValidation = inner.specializer.internalValidate(
            selection: innerSelection,
            for: innerRequest,
            parameterPathPrefix: parameterPath,
            depth: depth + 1
        )
        var errors = innerValidation.errors
        var warnings = innerValidation.warnings
        for innerParameter in innerRequest.parameters {
            guard case .candidate(let candidate) = innerSelection[innerParameter.name] else { continue }
            do {
                try inner.specializer.requireNonGenericCandidate(candidate)
            } catch {
                errors.append(.metadataResolutionFailed(
                    parameterName: Self.joinedPath(parameterPath, innerParameter.name),
                    reason: (error as? LocalizedError)?.errorDescription ?? "\(error)"
                ))
            }
        }

        let innerResolution = inner.specializer.resolveStaticArguments(
            for: innerRequest,
            with: innerSelection,
            parameterPathPrefix: parameterPath,
            depth: depth + 1
        )
        errors.append(contentsOf: innerResolution.errors)
        warnings.append(contentsOf: innerResolution.warnings)
        let checksBuilder = SpecializationValidation.builder()
        inner.specializer.checkStaticRequirements(of: innerRequest, with: innerResolution, parameterPathPrefix: parameterPath, into: checksBuilder)
        let checks = checksBuilder.build()
        errors.append(contentsOf: checks.errors)
        warnings.append(contentsOf: checks.warnings)
        guard errors.isEmpty else { return (nil, errors, warnings) }

        do {
            return (try inner.specializer.staticResult(for: innerRequest, with: innerSelection, resolution: innerResolution), [], warnings)
        } catch {
            return (nil, [.metadataResolutionFailed(parameterName: parameterPath, reason: (error as? LocalizedError)?.errorDescription ?? "\(error)")], warnings)
        }
    }

    // MARK: Requirement checks

    /// Checks every requirement of the type's generic signature whose subject
    /// is rooted in a selected parameter, against what offline evidence can
    /// prove. See `staticPreflight(selection:for:)` for which outcome is an
    /// error and which a warning.
    func checkStaticRequirements(
        of request: SpecializationRequest,
        with resolution: StaticArgumentResolution,
        parameterPathPrefix: String,
        into builder: SpecializationValidation.Builder
    ) {
        guard let genericContext = (try? request.typeDescriptor.genericContext(in: machO.context)) ?? nil else { return }
        let depthLayout = GenericParameterDepthLayout.make(for: genericContext, ownedBy: .type(request.typeDescriptor), in: machO.context)
        let binding = partialBinding(of: resolution, depthLayout: depthLayout)

        for requirement in Self.mergedRequirements(from: genericContext) {
            let flags = requirement.layout.flags
            switch flags.kind {
            case .protocol:
                // Marker and Objective-C protocols take no witness table and
                // are not checked, as on the runtime path.
                guard flags.contains(.hasKeyArgument) else { continue }
            case .layout, .baseClass, .sameType:
                break
            default:
                continue
            }
            guard let subjectNode = try? SymbolicDemangler.demangleType(for: requirement.paramMangledName(in: machO.context), in: machO.context),
                  let rootParameterName = Self.directGenericParamName(of: subjectNode) ?? Self.extractAssociatedPath(of: subjectNode)?.baseParamName,
                  // A parameter that takes no argument is fixed by the very
                  // requirement read here; one left unselected is `validate`'s
                  // error, one that failed to resolve is reported already.
                  let rootArgument = resolution.arguments[rootParameterName]
            else { continue }

            let isDirectParameter = Self.directGenericParamName(of: subjectNode) != nil
            // A member is named by its access path, `A.Element` — the
            // spelling of `AssociatedTypeRequirement.fullPath`, which is how
            // the request lists it.
            let memberPath = Self.extractAssociatedPath(of: subjectNode).map { ([$0.baseParamName] + $0.steps.map(\.name)).joined(separator: ".") }
            let subject = StaticRequirementSubject(
                path: Self.joinedPath(parameterPathPrefix, isDirectParameter ? rootParameterName : (memberPath ?? displayName(of: subjectNode))),
                type: DependentMemberProjection.projectingConcreteMembers(in: binding.substituting(in: subjectNode), in: machO),
                nominalTypeName: isDirectParameter ? rootArgument.nominalTypeName : nil,
                hostMetatype: isDirectParameter ? rootArgument.hostMetatype : nil
            )

            switch flags.kind {
            case .protocol:
                checkConformance(of: subject, to: requirement, into: builder)
            case .layout:
                checkClassLayout(of: subject, into: builder)
            case .baseClass:
                checkBaseClass(of: subject, requirement: requirement, binding: binding, into: builder)
            case .sameType:
                checkSameType(of: subject, requirement: requirement, binding: binding, into: builder)
            default:
                break
            }
        }
    }

    /// A requirement's subject with the arguments substituted.
    private struct StaticRequirementSubject {
        /// The parameter path diagnostics name: the parameter, or the member
        /// (`A.Element`).
        let path: String
        /// The subject's type, its members projected where a record allows.
        let type: Node
        let nominalTypeName: TypeName?
        let hostMetatype: Any.Type?

        var isResolved: Bool {
            !containsDependentReference(type)
        }

        var display: String {
            displayName(of: type)
        }
    }

    private func checkConformance(of subject: StaticRequirementSubject, to requirement: GenericRequirementDescriptor, into builder: SpecializationValidation.Builder) {
        guard let builtRequirement = try? buildRequirement(from: requirement), case .protocol(let info) = builtRequirement else { return }
        let protocolName = info.protocolName
        guard subject.isResolved, let typeName = subject.nominalTypeName ?? unboundNominalTypeName(of: subject.type) else {
            builder.addWarning(.conformanceCheckFailed(
                parameterName: subject.path,
                protocolName: protocolName.name,
                reason: "offline: \(subject.display) is not a nominal type the indexed images could describe"
            ))
            return
        }
        guard conformanceProvider.doesType(typeName, conformTo: protocolName) else {
            builder.addWarning(.conformanceCheckFailed(
                parameterName: subject.path,
                protocolName: protocolName.name,
                reason: "offline: the indexed images record no conformance of \(subject.display) to \(protocolName.name); a conformance in an image the indexer does not hold, a conditional one, or one the runtime synthesizes cannot be checked without the runtime"
            ))
            return
        }
        // The record is kept under the type's unbound name, so a conditional
        // one says nothing about this instantiation: `[FixtureUnmarked]`
        // passed `Hashable` on `Array`'s record, conditions and all.
        guard conformanceProvider.isConditionalConformance(of: typeName, to: protocolName) else { return }
        builder.addWarning(.conformanceCheckFailed(
            parameterName: subject.path,
            protocolName: protocolName.name,
            reason: "offline: \(typeName.name) conforms to \(protocolName.name) only under conditions, which \(subject.display) may not meet; they cannot be checked without the runtime"
        ))
    }

    private func checkClassLayout(of subject: StaticRequirementSubject, into builder: SpecializationValidation.Builder) {
        if let hostMetatype = subject.hostMetatype {
            guard let kind = try? Metadata.createInProcess(hostMetatype).kind else { return }
            if !(kind == .class || kind == .objcClassWrapper || kind == .foreignClass) {
                builder.addError(.layoutRequirementNotSatisfied(parameterName: subject.path, expectedLayout: .class, actualType: subject.display))
            }
            return
        }
        guard subject.isResolved else {
            builder.addWarning(.conformanceCheckFailed(
                parameterName: subject.path,
                protocolName: "AnyObject",
                reason: "offline: \(subject.display) could not be resolved to a concrete type"
            ))
            return
        }
        if Self.isValueType(subject.type) {
            builder.addError(.layoutRequirementNotSatisfied(parameterName: subject.path, expectedLayout: .class, actualType: subject.display))
        }
    }

    private func checkBaseClass(of subject: StaticRequirementSubject, requirement: GenericRequirementDescriptor, binding: GenericArgumentBinding, into builder: SpecializationValidation.Builder) {
        guard let expectedNode = try? SymbolicDemangler.demangleType(for: requirement.type(in: machO.context), in: machO.context) else { return }
        let expectedType = DependentMemberProjection.projectingConcreteMembers(in: binding.substituting(in: expectedNode), in: machO)
        let expectedDisplay = displayName(of: expectedType)
        guard let expectedClassName = unboundNominalTypeName(of: expectedType, kind: .class) else {
            builder.addWarning(.baseClassRequirementResolutionFailed(parameterName: subject.path, reason: "offline: \(expectedDisplay) is not a class the indexed images could describe"))
            return
        }

        if let hostMetatype = subject.hostMetatype {
            // The host's own class: its superclass chain is complete.
            if Self.hostClassChainNames(of: hostMetatype).contains(expectedClassName.name) { return }
            builder.addError(.baseClassRequirementNotSatisfied(parameterName: subject.path, expectedBaseClass: expectedDisplay, actualType: subject.display))
            return
        }
        guard subject.isResolved, let actualTypeName = subject.nominalTypeName ?? unboundNominalTypeName(of: subject.type) else {
            builder.addWarning(.baseClassRequirementResolutionFailed(parameterName: subject.path, reason: "offline: \(subject.display) could not be resolved to a concrete type"))
            return
        }
        if Self.isValueType(subject.type) {
            builder.addError(.baseClassRequirementNotSatisfied(parameterName: subject.path, expectedBaseClass: expectedDisplay, actualType: subject.display))
            return
        }
        // Up the superclass chain the indexed images describe, class names
        // compared unbound. Reaching the base proves the requirement; a root
        // class reached without it proves the violation. A link no indexed
        // image describes proves nothing either way: an Objective-C class —
        // `NSOperation` between a Swift class and an `NSObject` bound — or a
        // class of an image the indexer does not hold. Taking that for a
        // violation rejected every Swift class below a Cocoa class, which the
        // runtime accepts.
        var currentClassName = actualTypeName
        var visitedClassNames: Set<String> = []
        while visitedClassNames.insert(currentClassName.name).inserted {
            if currentClassName.name == expectedClassName.name { return }
            switch conformanceProvider.superclassLink(of: currentClassName) {
            case .inherits(let superclassName):
                currentClassName = unboundNominalTypeName(of: superclassName.node.materialize(), kind: .class) ?? superclassName
            case .root:
                builder.addError(.baseClassRequirementNotSatisfied(parameterName: subject.path, expectedBaseClass: expectedDisplay, actualType: subject.display))
                return
            case .unknown:
                let reason = currentClassName.name == actualTypeName.name
                    ? "offline: \(subject.display) is in no indexed image, so its superclass chain cannot be read"
                    : "offline: the superclass chain of \(subject.display) leaves the indexed images at \(currentClassName.name), so whether it reaches \(expectedDisplay) cannot be read"
                builder.addWarning(.baseClassRequirementResolutionFailed(parameterName: subject.path, reason: reason))
                return
            }
        }
        builder.addWarning(.baseClassRequirementResolutionFailed(parameterName: subject.path, reason: "offline: the superclass chain of \(subject.display) loops back on itself"))
    }

    private func checkSameType(of subject: StaticRequirementSubject, requirement: GenericRequirementDescriptor, binding: GenericArgumentBinding, into builder: SpecializationValidation.Builder) {
        guard let expectedNode = try? SymbolicDemangler.demangleType(for: requirement.type(in: machO.context), in: machO.context) else { return }
        let expectedType = DependentMemberProjection.projectingConcreteMembers(in: binding.substituting(in: expectedNode), in: machO)
        guard subject.isResolved, !containsDependentReference(expectedType) else {
            builder.addWarning(.sameTypeRequirementResolutionSkipped(
                parameterName: subject.path,
                reason: "offline: \(subject.display) == \(displayName(of: expectedType)) could not be resolved to two concrete types"
            ))
            return
        }
        if unwrappedTypeNode(subject.type) != unwrappedTypeNode(expectedType) {
            builder.addError(.sameTypeRequirementNotSatisfied(parameterName: subject.path, expectedType: displayName(of: expectedType), actualType: subject.display))
        }
    }

    // MARK: Helpers

    /// The arguments resolved so far by `(depth, index)`, every parameter
    /// without one standing for itself.
    private func partialBinding(of resolution: StaticArgumentResolution, depthLayout: GenericParameterDepthLayout) -> GenericArgumentBinding {
        let arguments = (0 ..< depthLayout.parameterCount).map { flatIndex -> Node in
            guard let position = depthLayout.position(ofParameterAt: flatIndex) else {
                return Node.createTransient(kind: .type, child: .createTransient(kind: .errorType))
            }
            let parameterName = genericParameterName(depth: UInt64(position.depth), index: UInt64(position.index))
            if let argument = resolution.arguments[parameterName] {
                return argument.node
            }
            return Node.createTransient(kind: .type, child: Node.createTransient(kind: .dependentGenericParamType, children: [
                .createTransient(kind: .index, index: UInt64(position.depth)),
                .createTransient(kind: .index, index: UInt64(position.index)),
            ]))
        }
        return GenericArgumentBinding(argumentsByDepth: depthLayout.grouped(arguments) ?? [])
    }

    /// The nominal type a type node instantiates, unbound and named the way
    /// the indexer names a definition: `Swift.Array` for `[Swift.Int]`,
    /// `Outer.Inner` for `Outer<Swift.Int>.Inner`.
    private func unboundNominalTypeName(of typeNode: Node, kind: TypeKind? = nil) -> TypeName? {
        guard let nominal = Self.unboundNominal(of: unwrappedTypeNode(typeNode)) else { return nil }
        let nominalKind: TypeKind
        switch nominal.kind {
        case .structure: nominalKind = .struct
        case .enum: nominalKind = .enum
        case .class: nominalKind = .class
        case .typeAlias, .otherNominalType: nominalKind = kind ?? .struct
        default: return nil
        }
        return TypeName(
            node: InternedNodeReferenceCache.shared.reference(interning: Node.createTransient(kind: .type, child: nominal), in: machO),
            kind: kind ?? nominalKind
        )
    }

    private static func unboundNominal(of node: Node) -> Node? {
        switch node.kind {
        case .boundGenericStructure, .boundGenericEnum, .boundGenericClass, .boundGenericOtherNominalType, .boundGenericTypeAlias:
            guard let unboundType = node.firstChild else { return nil }
            return unboundNominal(of: unwrappedTypeNode(unboundType))
        case .structure, .enum, .class, .typeAlias, .otherNominalType:
            guard node.children.count >= 2, let context = node.firstChild else { return node }
            let unboundContext = unboundNominal(of: context) ?? context
            guard unboundContext !== context else { return node }
            return Node.createTransient(kind: node.kind, children: [unboundContext] + node.children.dropFirst())
        case .extension:
            // `Extension(<module>, <extended type>, <signature>?)`.
            guard node.children.count >= 2, let extendedType = unboundNominal(of: unwrappedTypeNode(node.children[1])) else { return node }
            var children = Array(node.children)
            children[1] = extendedType
            return Node.createTransient(kind: .extension, children: children)
        default:
            return nil
        }
    }

    private static func isValueType(_ typeNode: Node) -> Bool {
        switch unwrappedTypeNode(typeNode).kind {
        case .structure, .boundGenericStructure, .enum, .boundGenericEnum, .tuple:
            return true
        default:
            return false
        }
    }

    /// The names of the host class and every ancestor, as the indexer names
    /// a class.
    private static func hostClassChainNames(of type: Any.Type) -> Set<String> {
        var names: Set<String> = []
        #if canImport(ObjectiveC)
        var currentClass: AnyClass? = type as? AnyClass
        while let ancestorClass = currentClass {
            if let node = RuntimeTypeNameDemangling.node(forMetatype: ancestorClass), let nominal = unboundNominal(of: unwrappedTypeNode(node)) {
                names.insert(Node.createTransient(kind: .type, child: nominal).print(using: .interfaceTypeBuilderOnly))
            }
            currentClass = class_getSuperclass(ancestorClass)
        }
        #endif
        return names
    }
}

/// How a diagnostic spells a type: the way the interface prints it.
private func displayName(of typeNode: Node) -> String {
    typeNode.print(using: .interface)
}

private func unwrappedTypeNode(_ node: Node) -> Node {
    node.kind == .type ? (node.firstChild ?? node) : node
}

private func typeWrappedNode(_ node: Node) -> Node {
    node.kind == .type ? node : Node.createTransient(kind: .type, child: node)
}

private func containsDependentReference(_ node: Node) -> Bool {
    switch node.kind {
    case .dependentGenericParamType, .dependentMemberType:
        return true
    default:
        return node.children.contains(where: containsDependentReference)
    }
}
