import Foundation
@_spi(Internals) import Demangling
import MachOKit
import MachOFoundation
import MachOSwiftSection
import MachOSwiftSectionC
#if canImport(ObjectiveC)
import ObjectiveC
#endif

/// In-process `TypeBuilder` conformer: decodes a demangled `Node` tree into
/// live runtime metadata, mirroring the runtime's own `DecodedMetadataBuilder`
/// (`stdlib/public/runtime/MetadataLookup.cpp`) over the same runtime entry
/// points — descriptor metadata accessors, `swift_conformsToProtocol`,
/// `swift_getTupleTypeMetadata`, `swift_getFunctionTypeMetadata`,
/// `swift_getExistentialTypeMetadata` — instead of remangling the node back to
/// a string for `swift_getTypeByMangledNameInContext`.
///
/// Construction requests use `MetadataState.abstract` while composing (the
/// runtime does the same to stay cycle-tolerant); the public entry point
/// forces completion through `swift_checkMetadataState` before returning.
///
/// First-version rejection surface (each returns a typed `TypeLookupError`,
/// never a fabricated value): SIL function/box types, parameter packs, value
/// generic arguments (`InlineArray<5, _>`), opaque return types, constrained
/// and extended existential shapes, and dynamic `Self`. This is the same or a
/// narrower rejection set than the runtime builder's.
public struct RuntimeMetadataTypeBuilder: TypeBuilder {
    /// Absolute `(depth, index)` of a generic parameter, matching the
    /// demangler's `dependentGenericParamType` coordinates.
    public struct GenericParameterPosition: Hashable, Sendable {
        public let depth: Int
        public let index: Int

        public init(depth: Int, index: Int) {
            self.depth = depth
            self.index = index
        }
    }

    /// Substitutions for `dependentGenericParamType` nodes reached during
    /// decoding. Empty by default — an unbound generic parameter then fails
    /// with a typed error rather than guessing.
    public var genericParameterMetadataTypes: [GenericParameterPosition: Any.Type]

    /// Resolution seam for nominal declaration nodes that carry a name rather
    /// than a resolved symbolic reference. Return the type context
    /// descriptor's in-process address, or `nil` to fall through to the
    /// builder's own fallbacks (runtime name lookup for non-generic nominals,
    /// known stdlib descriptors for the sugar types).
    public var nominalTypeDescriptorResolver: (@Sendable (Node) -> UnsafeRawPointer?)?

    public init(
        genericParameterMetadataTypes: [GenericParameterPosition: Any.Type] = [:],
        nominalTypeDescriptorResolver: (@Sendable (Node) -> UnsafeRawPointer?)? = nil
    ) {
        self.genericParameterMetadataTypes = genericParameterMetadataTypes
        self.nominalTypeDescriptorResolver = nominalTypeDescriptorResolver
    }

    // MARK: - Public entry point

    /// Decodes `node` into complete in-process runtime metadata.
    public func metadataType(for node: Node) throws(TypeLookupError) -> Any.Type {
        let decoder = TypeDecoder(builder: self)
        let abstractType = try decoder.decodeMangledType(node: node, forRequirement: false).get()
        return try Self.completedMetadataType(of: abstractType)
    }

    /// Same as `metadataType(for:)`, returning the project's `Metadata`
    /// wrapper for callers composing with the inspection APIs.
    public func metadata(for node: Node) throws -> Metadata {
        try Metadata.createInProcess(metadataType(for: node))
    }

    private static func completedMetadataType(of type: Any.Type) throws(TypeLookupError) -> Any.Type {
        let response = swift_checkMetadataState(
            MetadataRequest(state: .complete, isBlocking: true).rawValue.cast(),
            metadataPointer(of: type)
        )
        guard let completedPointer = response.Metadata else {
            throw TypeLookupError("swift_checkMetadataState returned no metadata")
        }
        return anyType(fromMetadataPointer: completedPointer)
    }

    // MARK: - Associated types

    public typealias BuiltType = TypeLookupErrorOr<Any.Type>

    /// A nominal declaration reached by the decoder: either a resolved type
    /// context descriptor address, or the declaration node itself when only
    /// the name is known (resolution then happens at metadata-construction
    /// time, where the argument shape is known).
    public enum NominalTypeDeclaration {
        case descriptor(UnsafeRawPointer)
        case named(Node)
    }

    public typealias BuiltTypeDecl = NominalTypeDeclaration
    public typealias BuiltProtocolDecl = ProtocolDescriptorRef

    /// Placeholder for the builder projections this conformer cannot realize
    /// as runtime metadata (SIL boxes, generic signatures, requirement
    /// values used only by constrained existentials). Constructible so the
    /// non-throwing protocol requirements can return it; every `BuiltType`
    /// composed from one fails with a typed error instead.
    public struct UnsupportedProjection {}

    public typealias BuiltSILBoxField = UnsupportedProjection
    public typealias BuiltSubstitution = UnsupportedProjection
    public typealias BuiltRequirement = UnsupportedProjection
    public typealias BuiltInverseRequirement = UnsupportedProjection
    public typealias BuiltLayoutConstraint = UnsupportedProjection
    public typealias BuiltGenericSignature = UnsupportedProjection
    public typealias BuiltSubstitutionMap = UnsupportedProjection

    // MARK: - TypeBuilder core

    public func getManglingFlavor() -> ManglingFlavor { .default }

    public func decodeMangledType(node: Node?, forRequirement: Bool) throws(TypeLookupError) -> BuiltType {
        guard let node else { throw TypeLookupError("nil node") }
        let decoder = TypeDecoder(builder: self)
        return try decoder.decodeMangledType(node: node, forRequirement: forRequirement)
    }

    // MARK: - Type declarations

    public func createTypeDecl(node: Node, typeAlias: inout Bool) -> NominalTypeDeclaration? {
        typeAlias = node.kind == .typeAlias || node.kind == .boundGenericTypeAlias
        if node.kind == .typeSymbolicReference {
            guard let address = node.index, let pointer = UnsafeRawPointer(bitPattern: UInt(address)) else {
                return nil
            }
            return .descriptor(pointer)
        }
        if let resolvedPointer = nominalTypeDescriptorResolver?(node) {
            return .descriptor(resolvedPointer)
        }
        return .named(node)
    }

    public func createProtocolDecl(node: Node) -> ProtocolDescriptorRef? {
        switch node.kind {
        case .protocolSymbolicReference:
            guard let address = node.index else { return nil }
            return .forSwift(StoredPointer(address))
        case .objectiveCProtocolSymbolicReference:
            guard let address = node.index else { return nil }
            return .forObjC(StoredPointer(address))
        default:
            break
        }
        if let resolvedPointer = nominalTypeDescriptorResolver?(node) {
            return .forSwift(StoredPointer(UInt(bitPattern: resolvedPointer)))
        }
        // Named Swift protocol: resolve through the runtime by building the
        // single-protocol existential's metadata from the node's bare type
        // mangling and reading the descriptor reference back out of it.
        guard let existentialType = Self.runtimeTypeByName(
            of: Node.createTransient(kind: .type, child: Node.createTransient(
                kind: .protocolList,
                child: Node.createTransient(kind: .typeList, child: Node.createTransient(kind: .type, child: node))
            ))
        ) else { return nil }
        guard let existentialMetadata = try? ExistentialTypeMetadata.createInProcess(existentialType),
              let reference = try? existentialMetadata.protocols().first else {
            return nil
        }
        return reference
    }

    #if canImport(ObjectiveC)
    public func createObjCProtocolDecl(name: String) -> ProtocolDescriptorRef {
        guard let objcProtocol = objc_getProtocol(name) else {
            return .forSwift(0)
        }
        return .forObjC(StoredPointer(UInt(bitPattern: unsafeBitCast(objcProtocol, to: UnsafeRawPointer.self))))
    }

    public func createObjCClassType(name: String) -> BuiltType {
        guard let objcClass = objc_lookUpClass(name) else {
            return .failure(TypeLookupError("Objective-C class '\(name)' is not present in this process"))
        }
        // The canonical `Any.Type` for an Objective-C class is the realized
        // class object itself (`NSObject.self` bitcasts to the class
        // pointer); `swift_getObjCClassMetadata`'s wrapper is a distinct
        // metadata identity and would split generic instantiation caches.
        let realizedClass = swift_getInitializedObjCClass(objcClass)
        return .success(Self.anyType(fromMetadataPointer: unsafeBitCast(realizedClass, to: UnsafeRawPointer.self)))
    }

    public func createBoundGenericObjCClassType(name: String, args: [BuiltType]) -> BuiltType {
        // Generic arguments of lightweight Objective-C generic classes are
        // not reified in metadata — same as the runtime builder.
        createObjCClassType(name: name)
    }
    #endif

    // MARK: - Nominal types

    public func createNominalType(typeDecl: NominalTypeDeclaration, parent: BuiltType?) -> BuiltType {
        createBoundGenericType(typeDecl: typeDecl, args: [], parent: parent)
    }

    public func createTypeAliasType(typeDecl: NominalTypeDeclaration, parent: BuiltType?) -> BuiltType {
        // No way to resolve a typealias's underlying type from a binary; some
        // CF types are mangled as typealiases, so treat it as nominal (the
        // runtime builder does the same).
        createNominalType(typeDecl: typeDecl, parent: parent)
    }

    public func createBoundGenericType(typeDecl: NominalTypeDeclaration, args: [BuiltType], parent: BuiltType?) -> BuiltType {
        let ownArguments: [Any.Type]
        switch Self.unwrap(args) {
        case .success(let unwrapped): ownArguments = unwrapped
        case .failure(let error): return .failure(error)
        }
        let parentType: Any.Type?
        switch parent {
        case .none: parentType = nil
        case .success(let type): parentType = type
        case .failure(let error): return .failure(error)
        }

        switch typeDecl {
        case .descriptor(let descriptorPointer):
            return buildNominalMetadataType(
                descriptorPointer: descriptorPointer,
                ownArguments: ownArguments,
                parentType: parentType
            )
        case .named(let node):
            if ownArguments.isEmpty, parentType == nil {
                // A concrete non-generic nominal resolves through the
                // runtime's own name lookup, which searches every loaded
                // image's type section with its conformance caches.
                guard let resolvedType = Self.runtimeTypeByName(of: Node.createTransient(kind: .type, child: node)) else {
                    return .failure(TypeLookupError(node: node, message: "runtime name lookup found no type descriptor"))
                }
                return .success(resolvedType)
            }
            // A named generic declaration needs its descriptor. The standard
            // library's generic types come from textual manglings (`Sa`,
            // `SD`, …), so their descriptors are kept on hand.
            if let qualifiedName = Self.qualifiedDeclarationName(of: node),
               let descriptorPointer = Self.standardLibraryGenericDescriptorPointersByQualifiedName[qualifiedName] {
                return buildNominalMetadataType(
                    descriptorPointer: descriptorPointer,
                    ownArguments: ownArguments,
                    parentType: parentType
                )
            }
            return .failure(TypeLookupError(
                node: node,
                message: "cannot resolve a named generic declaration to its descriptor; supply nominalTypeDescriptorResolver"
            ))
        }
    }

    private func buildNominalMetadataType(
        descriptorPointer: UnsafeRawPointer,
        ownArguments: [Any.Type],
        parentType: Any.Type?
    ) -> BuiltType {
        let contextWrapper: ContextDescriptorWrapper
        do {
            contextWrapper = try ContextDescriptorWrapper.resolve(from: descriptorPointer)
        } catch {
            return .failure(TypeLookupError("cannot read context descriptor: \(error)"))
        }

        // A protocol descriptor in type position denotes the bare existential
        // (the runtime builder's `_getSimpleProtocolTypeMetadata`).
        if contextWrapper.isProtocol {
            var protocolReferences = [ProtocolDescriptorRef.forSwift(StoredPointer(UInt(bitPattern: descriptorPointer)))]
            return Self.existentialMetadataType(
                protocolReferences: &protocolReferences,
                superclassType: nil,
                isClassBound: false
            )
        }

        guard let typeWrapper = contextWrapper.typeContextDescriptorWrapper else {
            return .failure(TypeLookupError("context descriptor at \(descriptorPointer) is not a type context"))
        }

        let genericContext: GenericContext?
        do {
            genericContext = try typeWrapper.genericContext()
        } catch {
            return .failure(TypeLookupError("cannot read generic context: \(error)"))
        }

        var keyMetadataTypes: [Any.Type] = []
        var witnessTables: [ProtocolWitnessTable] = []

        if let genericContext {
            switch keyArguments(of: genericContext, ownArguments: ownArguments, parentType: parentType) {
            case .success(let gathered):
                keyMetadataTypes = gathered.metadataTypes
                witnessTables = gathered.witnessTables
            case .failure(let error):
                return .failure(error)
            }
        } else if !ownArguments.isEmpty {
            return .failure(TypeLookupError("generic arguments supplied to the non-generic declaration at \(descriptorPointer)"))
        }

        do {
            guard let accessorFunction = try typeWrapper.typeContextDescriptor.metadataAccessorFunction() else {
                return .failure(TypeLookupError("type context descriptor at \(descriptorPointer) has no metadata accessor"))
            }
            let keyMetadatas = try keyMetadataTypes.map { try Metadata.createInProcess($0) }
            let response = try accessorFunction(
                request: MetadataRequest(state: .abstract, isBlocking: false),
                metadatas: keyMetadatas,
                witnessTables: witnessTables
            )
            let responseMetadata = try response.value.resolve()
            return .success(Self.anyType(fromMetadataPointer: try responseMetadata.metadata.asPointer))
        } catch {
            return .failure(TypeLookupError("metadata accessor invocation failed: \(error)"))
        }
    }

    /// The gathered key-argument buffer contents for one generic context, in
    /// the runtime's canonical order: every key type parameter's metadata
    /// first, then one witness table per key protocol requirement in
    /// requirement order — the `_gatherGenericParameters` +
    /// `_checkGenericRequirements` shape.
    private struct GatheredKeyArguments {
        var metadataTypes: [Any.Type]
        var witnessTables: [ProtocolWitnessTable]
    }

    private func keyArguments(
        of genericContext: GenericContext,
        ownArguments: [Any.Type],
        parentType: Any.Type?
    ) -> TypeLookupErrorOr<GatheredKeyArguments> {
        let cumulativeParameters = genericContext.parameters

        if let unsupportedParameter = cumulativeParameters.first(where: { $0.kind != .type }) {
            return .failure(TypeLookupError("generic parameter kind \(unsupportedParameter.kind) (pack or value) is not supported yet"))
        }

        // Written arguments cover the whole cumulative parameter list. Either
        // the caller supplied only the innermost level (parent metadata fills
        // the outer levels), or the complete flattened list with no parent —
        // the same two acceptable shapes as `_gatherGenericParameters`.
        var writtenArguments: [Any.Type]
        if ownArguments.count == genericContext.currentParameters.count {
            switch Self.writtenGenericArguments(ofParent: parentType) {
            case .success(let parentArguments):
                writtenArguments = parentArguments + ownArguments
            case .failure(let error):
                return .failure(error)
            }
        } else if ownArguments.count == cumulativeParameters.count, parentType == nil {
            writtenArguments = ownArguments
        } else {
            return .failure(TypeLookupError(
                "incorrect number of generic arguments: have \(ownArguments.count), context declares \(genericContext.currentParameters.count) local / \(cumulativeParameters.count) total"
            ))
        }

        guard writtenArguments.count == cumulativeParameters.count else {
            return .failure(TypeLookupError(
                "written generic arguments (\(writtenArguments.count)) do not cover the cumulative parameter list (\(cumulativeParameters.count))"
            ))
        }

        var gathered = GatheredKeyArguments(metadataTypes: [], witnessTables: [])
        for (parameter, argument) in zip(cumulativeParameters, writtenArguments) where parameter.hasKeyArgument {
            gathered.metadataTypes.append(argument)
        }

        // Witness tables for the key protocol requirements. Requirement
        // subjects (`A`, `A.Element`, …) decode through a nested builder
        // whose bindings are the written arguments.
        var subjectBuilder = self
        subjectBuilder.genericParameterMetadataTypes = Self.bindings(
            of: genericContext,
            writtenArguments: writtenArguments
        )

        for requirementDescriptor in genericContext.requirements {
            let flags = requirementDescriptor.layout.flags
            guard flags.kind == .protocol, flags.contains(.hasKeyArgument) else { continue }

            let requirement: GenericRequirement
            do {
                requirement = try GenericRequirement(descriptor: requirementDescriptor)
            } catch {
                return .failure(TypeLookupError("cannot read generic requirement: \(error)"))
            }
            guard case .protocol(let protocolReference) = requirement.content,
                  let resolvedProtocol = protocolReference.resolved,
                  let protocolDescriptor = resolvedProtocol.swift else {
                return .failure(TypeLookupError("key protocol requirement's descriptor did not resolve"))
            }

            let subjectNode: Node
            do {
                subjectNode = try MetadataReader.demangleType(for: requirement.paramManagledName)
            } catch {
                return .failure(TypeLookupError("cannot demangle requirement subject: \(error)"))
            }

            let subjectType: Any.Type
            switch Result(catching: { () throws(TypeLookupError) in
                try subjectBuilder.decodeMangledType(node: subjectNode, forRequirement: true).get()
            }) {
            case .success(let type): subjectType = type
            case .failure(let error): return .failure(TypeLookupError("cannot resolve requirement subject: \(error)"))
            }

            do {
                guard let witnessTable = try RuntimeFunctions.conformsToProtocol(
                    metadata: Metadata.createInProcess(subjectType),
                    protocolDescriptor: protocolDescriptor
                ) else {
                    return .failure(TypeLookupError("\(subjectType) does not conform to the required protocol"))
                }
                gathered.witnessTables.append(witnessTable)
            } catch {
                return .failure(TypeLookupError("conformance lookup failed: \(error)"))
            }
        }

        // The same final honesty check the runtime performs: the accessor's
        // argument buffer must hold exactly the declared key-argument count —
        // a mismatch means a requirement kind this builder does not model.
        let declaredKeyArgumentCount = Int(genericContext.header.layout.numKeyArguments)
        let gatheredKeyArgumentCount = gathered.metadataTypes.count + gathered.witnessTables.count
        guard gatheredKeyArgumentCount == declaredKeyArgumentCount else {
            return .failure(TypeLookupError(
                "gathered \(gatheredKeyArgumentCount) key arguments but the generic context declares \(declaredKeyArgumentCount)"
            ))
        }

        return .success(gathered)
    }

    /// Maps every cumulative generic parameter position to its written
    /// argument, using the per-level "newly introduced" counts so `(depth,
    /// index)` matches the demangler's coordinates.
    private static func bindings(
        of genericContext: GenericContext,
        writtenArguments: [Any.Type]
    ) -> [GenericParameterPosition: Any.Type] {
        var perLevelCounts: [Int] = []
        var previousCumulativeCount = 0
        for parentLevel in genericContext.parentParameters {
            perLevelCounts.append(parentLevel.count - previousCumulativeCount)
            previousCumulativeCount = parentLevel.count
        }
        perLevelCounts.append(genericContext.currentParameters.count)

        var result: [GenericParameterPosition: Any.Type] = [:]
        var flatIndex = 0
        for (depth, count) in perLevelCounts.enumerated() {
            for indexInLevel in 0 ..< count {
                guard flatIndex < writtenArguments.count else { return result }
                result[GenericParameterPosition(depth: depth, index: indexInLevel)] = writtenArguments[flatIndex]
                flatIndex += 1
            }
        }
        return result
    }

    /// Reads a parent context's written generic arguments back out of its
    /// live metadata (the outer levels of a nested instantiation). `nil` or a
    /// non-generic parent contributes nothing.
    private static func writtenGenericArguments(ofParent parentType: Any.Type?) -> TypeLookupErrorOr<[Any.Type]> {
        guard let parentType else { return .success([]) }
        do {
            let parentMetadata = try Metadata.createInProcess(parentType)
            guard let parentWrapper = try parentMetadata.typeContextDescriptorWrapper() else {
                return .success([])
            }
            guard let parentGenericContext = try parentWrapper.genericContext() else {
                return .success([])
            }
            // Reconstructing written arguments for non-key parameters (ones a
            // same-type constraint erased from the key buffer) needs the
            // requirement solver the runtime hides in
            // `_gatherWrittenGenericParameters`; reject rather than guess.
            if let nonKeyParameter = parentGenericContext.parameters.first(where: { !$0.hasKeyArgument || $0.kind != .type }) {
                return .failure(TypeLookupError("parent context has a non-key or non-type generic parameter (\(nonKeyParameter.kind)); not supported yet"))
            }

            let argumentCount = parentGenericContext.parameters.count
            let argumentsPointer = try genericArgumentsPointer(ofParentMetadata: parentMetadata)
            let arguments = (0 ..< argumentCount).map { argumentIndex in
                anyType(fromMetadataPointer: argumentsPointer.load(
                    fromByteOffset: argumentIndex * MemoryLayout<UnsafeRawPointer>.size,
                    as: UnsafeRawPointer.self
                ))
            }
            return .success(arguments)
        } catch {
            return .failure(TypeLookupError("cannot read parent generic arguments: \(error)"))
        }
    }

    private static func genericArgumentsPointer(ofParentMetadata parentMetadata: Metadata) throws -> UnsafeRawPointer {
        let metadataPointer = try parentMetadata.asPointer
        switch parentMetadata.kind {
        case .struct, .enum, .optional:
            return metadataPointer.advanced(by: MemoryLayout<ValueMetadata.Layout>.size)
        case .class:
            let classMetadata = try ClassMetadataObjCInterop.resolve(from: metadataPointer)
            guard let classDescriptor = try classMetadata.descriptor() else {
                throw TypeLookupError("parent class metadata has no Swift descriptor")
            }
            let immediateMembersOffsetInWords: Int
            if classDescriptor.hasResilientSuperclass {
                let bounds = try classDescriptor.resilientMetadataBounds()
                immediateMembersOffsetInWords = Int(bounds.layout.immediateMembersOffset) / MemoryLayout<StoredPointer>.size
            } else {
                immediateMembersOffsetInWords = Int(classDescriptor.nonResilientImmediateMembersOffset)
            }
            return metadataPointer.advanced(by: immediateMembersOffsetInWords * MemoryLayout<StoredPointer>.size)
        default:
            throw TypeLookupError("parent metadata kind \(parentMetadata.kind) cannot carry generic arguments")
        }
    }

    // MARK: - Generic parameters

    public func createGenericTypeParameterType(depth: Int, index: Int) -> BuiltType {
        guard let boundType = genericParameterMetadataTypes[GenericParameterPosition(depth: depth, index: index)] else {
            return .failure(TypeLookupError("generic parameter (depth \(depth), index \(index)) has no bound metadata"))
        }
        return .success(boundType)
    }

    public func createDependentMemberType(member: String, base: BuiltType) -> BuiltType {
        .failure(TypeLookupError("unbound dependent member type '\(member)' cannot be resolved"))
    }

    public func createDependentMemberType(member: String, base: BuiltType, protocol protocolDecl: ProtocolDescriptorRef) -> BuiltType {
        let baseType: Any.Type
        switch base {
        case .success(let type): baseType = type
        case .failure(let error): return .failure(error)
        }
        if protocolDecl.isObjC {
            return .failure(TypeLookupError("associated type '\(member)' of an Objective-C protocol cannot be resolved"))
        }
        do {
            let protocolDescriptor = try protocolDecl.swiftProtocol()
            let declaredProtocol = try MachOSwiftSection.Protocol(descriptor: protocolDescriptor)
            let associatedTypeNames = try protocolDescriptor.associatedTypes()
            guard let associatedTypeIndex = associatedTypeNames.firstIndex(of: member) else {
                return .failure(TypeLookupError("protocol declares no associated type named '\(member)'"))
            }
            guard let baseRequirement = declaredProtocol.baseRequirement else {
                return .failure(TypeLookupError("protocol has no requirement base descriptor"))
            }
            let accessFunctionRequirements = declaredProtocol.requirements.filter {
                $0.flags.kind.isAssociatedTypeAccessFunction
            }
            guard associatedTypeIndex < accessFunctionRequirements.count else {
                return .failure(TypeLookupError("associated type index \(associatedTypeIndex) exceeds the requirement list"))
            }
            let baseMetadata = try Metadata.createInProcess(baseType)
            guard let witnessTable = try RuntimeFunctions.conformsToProtocol(
                metadata: baseMetadata,
                protocolDescriptor: protocolDescriptor
            ) else {
                return .failure(TypeLookupError("\(baseType) does not conform to the protocol declaring '\(member)'"))
            }
            let response = try RuntimeFunctions.getAssociatedTypeWitness(
                request: MetadataRequest(state: .abstract, isBlocking: false),
                protocolWitnessTable: witnessTable,
                conformingTypeMetadata: baseMetadata,
                baseRequirement: baseRequirement,
                associatedTypeRequirement: accessFunctionRequirements[associatedTypeIndex]
            )
            let witnessMetadata = try response.value.resolve().metadata
            return .success(Self.anyType(fromMetadataPointer: try witnessMetadata.asPointer))
        } catch {
            return .failure(TypeLookupError("associated type witness resolution failed: \(error)"))
        }
    }

    // MARK: - Metatypes

    public func createMetatypeType(instance: BuiltType, repr: ImplMetatypeRepresentation?) -> BuiltType {
        instance.map { instanceType in
            Self.anyType(fromMetadataPointer: swift_getMetatypeMetadata(Self.metadataPointer(of: instanceType)))
        }
    }

    public func createExistentialMetatypeType(instance: BuiltType, repr: ImplMetatypeRepresentation?) -> BuiltType {
        let instanceType: Any.Type
        switch instance {
        case .success(let type): instanceType = type
        case .failure(let error): return .failure(error)
        }
        let instanceKind = (try? Metadata.createInProcess(instanceType).kind) ?? .opaque
        guard instanceKind == .existential || instanceKind == .existentialMetatype else {
            return .failure(TypeLookupError("existential metatype instance is neither an existential nor an existential metatype"))
        }
        return .success(Self.anyType(fromMetadataPointer: swift_getExistentialMetatypeMetadata(Self.metadataPointer(of: instanceType))))
    }

    // MARK: - Existentials

    public func createProtocolCompositionType(protocols: [ProtocolDescriptorRef], superclass: BuiltType?, isClassBound: Bool, forRequirement: Bool) -> BuiltType {
        let superclassType: Any.Type?
        switch superclass {
        case .none: superclassType = nil
        case .success(let type): superclassType = type
        case .failure(let error): return .failure(error)
        }
        guard !protocols.contains(where: { $0.storage == 0 }) else {
            return .failure(TypeLookupError("a protocol in the composition did not resolve"))
        }
        var protocolReferences = protocols
        return Self.existentialMetadataType(
            protocolReferences: &protocolReferences,
            superclassType: superclassType,
            isClassBound: isClassBound
        )
    }

    public func createProtocolCompositionType(protocol protocolDecl: ProtocolDescriptorRef, superclass: BuiltType?, isClassBound: Bool, forRequirement: Bool) -> BuiltType {
        createProtocolCompositionType(protocols: [protocolDecl], superclass: superclass, isClassBound: isClassBound, forRequirement: forRequirement)
    }

    private static func existentialMetadataType(
        protocolReferences: inout [ProtocolDescriptorRef],
        superclassType: Any.Type?,
        isClassBound: Bool
    ) -> BuiltType {
        var classConstraint = ProtocolClassConstraint.any
        if isClassBound || superclassType != nil {
            classConstraint = .class
        } else {
            for reference in protocolReferences where classConstraint == .any {
                if reference.isObjC {
                    classConstraint = .class
                } else if let descriptor = try? reference.swiftProtocol(),
                          descriptor.flags.kindSpecificFlags?.protocolFlags?.classConstraint == .class {
                    classConstraint = .class
                }
            }
        }
        let superclassPointer = superclassType.map { metadataPointer(of: $0) }
        // The runtime sorts the protocol array in place; hand it scratch storage.
        let existentialPointer = protocolReferences.withUnsafeMutableBufferPointer { buffer in
            swift_getExistentialTypeMetadata(
                classConstraint.rawValue,
                superclassPointer,
                buffer.count,
                buffer.baseAddress
            )
        }
        guard let existentialPointer else {
            return .failure(TypeLookupError("swift_getExistentialTypeMetadata returned nil"))
        }
        return .success(anyType(fromMetadataPointer: existentialPointer))
    }

    public func createConstrainedExistentialType(base: BuiltType, requirements: [UnsupportedProjection], inverseRequirements: [UnsupportedProjection]) -> BuiltType {
        // The runtime builder rejects these too ("FIXME: Runtime plumbing").
        .failure(TypeLookupError("constrained existential types are not supported"))
    }

    public func createSymbolicExtendedExistentialType(shapeNode: Node, args: [BuiltType]) -> BuiltType {
        .failure(TypeLookupError("extended existential shapes are not supported yet"))
    }

    // MARK: - Functions

    public func createFunctionType(
        parameters: [FunctionParam<BuiltType>],
        result: BuiltType,
        flags: Demangling.FunctionTypeFlags,
        extFlags: ExtendedFunctionTypeFlags,
        diffKind: FunctionMetadataDifferentiabilityKind,
        globalActorType: BuiltType?,
        thrownErrorType: BuiltType?
    ) -> BuiltType {
        let resultType: Any.Type
        switch result {
        case .success(let type): resultType = type
        case .failure(let error): return .failure(error)
        }

        var parameterPointers: [UnsafeRawPointer?] = []
        var parameterFlags: [UInt32] = []
        parameterPointers.reserveCapacity(parameters.count)
        for parameter in parameters {
            switch parameter.type {
            case .success(let parameterType):
                parameterPointers.append(Self.metadataPointer(of: parameterType))
            case .failure(let error):
                return .failure(error)
            case .none:
                return .failure(TypeLookupError("function parameter carries no type"))
            }
            parameterFlags.append(parameter.flags.rawValue)
        }

        let globalActor: Any.Type?
        switch globalActorType {
        case .none: globalActor = nil
        case .success(let type): globalActor = type
        case .failure(let error): return .failure(error)
        }
        let thrownError: Any.Type?
        switch thrownErrorType {
        case .none: thrownError = nil
        case .success(let type): thrownError = type
        case .failure(let error): return .failure(error)
        }

        let needsExtendedEntryPoint = extFlags.rawValue != 0 || diffKind.isDifferentiable || globalActor != nil || thrownError != nil

        let functionMetadataPointer: UnsafeRawPointer? = parameterPointers.withUnsafeBufferPointer { parameterBuffer in
            parameterFlags.withUnsafeBufferPointer { flagsBuffer in
                let flagsPointer = flags.hasParameterFlags ? flagsBuffer.baseAddress : nil
                if needsExtendedEntryPoint {
                    guard hasExtendedFunctionMetadataEntryPoint else { return nil }
                    return swift_getExtendedFunctionTypeMetadata(
                        Int(flags.rawValue).cast(),
                        Self.runtimeDifferentiabilityKindValue(of: diffKind),
                        parameterBuffer.baseAddress,
                        flagsPointer,
                        Self.metadataPointer(of: resultType),
                        globalActor.map { Self.metadataPointer(of: $0) },
                        extFlags.rawValue,
                        thrownError.map { Self.metadataPointer(of: $0) }
                    )
                }
                return swift_getFunctionTypeMetadata(
                    Int(flags.rawValue).cast(),
                    parameterBuffer.baseAddress,
                    flagsPointer,
                    Self.metadataPointer(of: resultType)
                )
            }
        }
        guard let functionMetadataPointer else {
            return .failure(TypeLookupError(
                needsExtendedEntryPoint
                    ? "this Swift runtime has no swift_getExtendedFunctionTypeMetadata (needed for global actor / typed throws / differentiability)"
                    : "swift_getFunctionTypeMetadata returned nil"
            ))
        }
        return .success(Self.anyType(fromMetadataPointer: functionMetadataPointer))
    }

    private var hasExtendedFunctionMetadataEntryPoint: Bool {
        // The symbol is weak-imported; an older runtime does not have it.
        dlsym(UnsafeMutableRawPointer(bitPattern: -2) /* RTLD_DEFAULT */, "swift_getExtendedFunctionTypeMetadata") != nil
    }

    private static func runtimeDifferentiabilityKindValue(of diffKind: FunctionMetadataDifferentiabilityKind) -> Int {
        switch diffKind {
        case .nonDifferentiable: return 0
        case .forward: return 1
        case .reverse: return 2
        case .normal: return 3
        case .linear: return 4
        }
    }

    public func createImplFunctionType(
        calleeConvention: ImplParameterConvention,
        coroutineKind: ImplCoroutineKind,
        parameters: [ImplFunctionParam<BuiltType>],
        yields: [ImplFunctionYield<BuiltType>],
        results: [ImplFunctionResult<BuiltType>],
        errorResult: ImplFunctionResult<BuiltType>?,
        flags: ImplFunctionTypeFlags
    ) -> BuiltType {
        .failure(TypeLookupError("SIL function types have no runtime metadata"))
    }

    // MARK: - Tuples and packs

    public func createTupleType(elements: [BuiltType], labels: [String?]) -> BuiltType {
        let elementTypes: [Any.Type]
        switch Self.unwrap(elements) {
        case .success(let unwrapped): elementTypes = unwrapped
        case .failure(let error): return .failure(error)
        }
        // The runtime unwraps unlabeled one-element tuples to the element.
        if elementTypes.count == 1, labels.first ?? nil == nil {
            return .success(elementTypes[0])
        }

        var labelsString = ""
        for (labelIndex, label) in labels.enumerated() {
            guard let label, !label.isEmpty else {
                if !labelsString.isEmpty { labelsString.append(" ") }
                continue
            }
            if labelsString.isEmpty {
                labelsString.append(String(repeating: " ", count: labelIndex))
            }
            labelsString.append(label)
            labelsString.append(" ")
        }

        let tupleFlagsNonConstantLabelsMask = 0x10000
        let tupleFlags = elementTypes.count | (labelsString.isEmpty ? 0 : tupleFlagsNonConstantLabelsMask)

        let elementPointers: [UnsafeRawPointer?] = elementTypes.map { Self.metadataPointer(of: $0) }
        let response = elementPointers.withUnsafeBufferPointer { elementBuffer in
            labelsString.isEmpty
                ? swift_getTupleTypeMetadata(
                    MetadataRequest(state: .abstract, isBlocking: false).rawValue.cast(),
                    tupleFlags.cast(),
                    elementBuffer.baseAddress,
                    nil,
                    nil
                )
                : labelsString.withCString { labelsPointer in
                    swift_getTupleTypeMetadata(
                        MetadataRequest(state: .abstract, isBlocking: false).rawValue.cast(),
                        tupleFlags.cast(),
                        elementBuffer.baseAddress,
                        labelsPointer,
                        nil
                    )
                }
        }
        guard let tuplePointer = response.Metadata else {
            return .failure(TypeLookupError("swift_getTupleTypeMetadata returned nil"))
        }
        return .success(Self.anyType(fromMetadataPointer: tuplePointer))
    }

    public func createPackType(elements: [BuiltType]) -> BuiltType {
        .failure(TypeLookupError("parameter packs are not supported yet"))
    }

    public func createSILPackType(elements: [BuiltType], isElementAddress: Bool) -> BuiltType {
        .failure(TypeLookupError("lowered SIL pack types cannot be built"))
    }

    public func createExpandedPackElement(type: BuiltType) -> BuiltType {
        type
    }

    public func beginPackExpansion(countType: BuiltType) -> Int {
        0
    }

    public func advancePackExpansion(index: Int) {}

    public func endPackExpansion() {}

    public func pushGenericParams(parameterPacks: [(Int, Int)]) {}

    public func popGenericParams() {}

    // MARK: - Reference storage

    public func createUnownedStorageType(base: BuiltType) -> BuiltType {
        // Reference-storage qualifiers do not change metadata identity; the
        // runtime builder records ownership out of band and returns the base.
        base
    }

    public func createUnmanagedStorageType(base: BuiltType) -> BuiltType {
        base
    }

    public func createWeakStorageType(base: BuiltType) -> BuiltType {
        base
    }

    // MARK: - SIL boxes

    public func createSILBoxField(type: BuiltType, isMutable: Bool) -> UnsupportedProjection {
        UnsupportedProjection()
    }

    public func createSILBoxType(base: BuiltType) -> BuiltType {
        .failure(TypeLookupError("SIL box types have no runtime metadata"))
    }

    public func createSILBoxTypeWithLayout(
        fields: [UnsupportedProjection],
        substitutions: [UnsupportedProjection],
        requirements: [UnsupportedProjection],
        inverseRequirements: [UnsupportedProjection]
    ) -> BuiltType {
        .failure(TypeLookupError("SIL box types have no runtime metadata"))
    }

    // MARK: - Special types

    public func createDynamicSelfType(base: BuiltType) -> BuiltType {
        .failure(TypeLookupError("dynamic Self cannot appear in a free-standing type"))
    }

    public func resolveOpaqueType(descriptor: Node, genericArgs: [ArraySlice<BuiltType>], ordinal: UInt64) -> BuiltType {
        .failure(TypeLookupError("opaque return types are not supported yet"))
    }

    public func createBuiltinType(name: String, mangledName: String) -> BuiltType {
        // Builtin metadata is exported as "$s<mangling>N" symbols from the
        // runtime (the runtime builder reads the same table statically).
        guard let metadataAddress = dlsym(UnsafeMutableRawPointer(bitPattern: -2) /* RTLD_DEFAULT */, "$s\(mangledName)N") else {
            return .failure(TypeLookupError("builtin type '\(name)' has no exported metadata symbol"))
        }
        return .success(Self.anyType(fromMetadataPointer: UnsafeRawPointer(metadataAddress)))
    }

    // MARK: - Sugar

    public func createOptionalType(base: BuiltType) -> BuiltType {
        boundGenericStandardLibraryType(of: Optional<Int>.self, arguments: [base])
    }

    public func createArrayType(element: BuiltType) -> BuiltType {
        boundGenericStandardLibraryType(of: [Int].self, arguments: [element])
    }

    public func createDictionaryType(key: BuiltType, value: BuiltType) -> BuiltType {
        boundGenericStandardLibraryType(of: [Int: Int].self, arguments: [key, value])
    }

    public func createInlineArrayType(count: BuiltType, element: BuiltType) -> BuiltType {
        .failure(TypeLookupError("InlineArray needs a value generic argument; not supported yet"))
    }

    private func boundGenericStandardLibraryType(of instantiation: Any.Type, arguments: [BuiltType]) -> BuiltType {
        let descriptorPointer: UnsafeRawPointer
        do {
            guard let wrapper = try Metadata.createInProcess(instantiation).typeContextDescriptorWrapper() else {
                return .failure(TypeLookupError("cannot locate the standard library descriptor via \(instantiation)"))
            }
            descriptorPointer = try wrapper.typeContextDescriptor.asPointer
        } catch {
            return .failure(TypeLookupError("cannot locate the standard library descriptor via \(instantiation): \(error)"))
        }
        return createBoundGenericType(typeDecl: .descriptor(descriptorPointer), args: arguments, parent: nil)
    }

    // MARK: - Integer generic arguments

    public func createIntegerType(value: Int) -> BuiltType {
        .failure(TypeLookupError("value generic arguments are not supported yet"))
    }

    public func createNegativeIntegerType(value: Int) -> BuiltType {
        .failure(TypeLookupError("value generic arguments are not supported yet"))
    }

    public func createBuiltinFixedArrayType(size: BuiltType, element: BuiltType) -> BuiltType {
        .failure(TypeLookupError("Builtin.FixedArray needs a value generic argument; not supported yet"))
    }

    // MARK: - Requirements (constrained existentials only; rejected above)

    public func createRequirement(kind: RequirementKind, subjectType: BuiltType, constraintType: BuiltType) -> UnsupportedProjection {
        UnsupportedProjection()
    }

    public func createRequirement(kind: RequirementKind, subjectType: BuiltType, layout: UnsupportedProjection) -> UnsupportedProjection {
        UnsupportedProjection()
    }

    public func createSubstitution(firstType: BuiltType, secondType: BuiltType) -> UnsupportedProjection {
        UnsupportedProjection()
    }

    public func createInverseRequirement(subjectType: BuiltType, kind: Demangling.InvertibleProtocolKind) -> UnsupportedProjection {
        UnsupportedProjection()
    }

    public func getLayoutConstraint(kind: LayoutConstraintKind) -> UnsupportedProjection {
        UnsupportedProjection()
    }

    public func getLayoutConstraintWithSizeAlign(kind: LayoutConstraintKind, size: Int, alignment: Int) -> UnsupportedProjection {
        UnsupportedProjection()
    }

    // MARK: - Queries

    public func isExistential(type: BuiltType) -> Bool {
        guard case .success(let builtType) = type,
              let kind = try? Metadata.createInProcess(builtType).kind else {
            return false
        }
        return kind == .existential || kind == .existentialMetatype
    }

    // MARK: - Shared helpers

    private static func unwrap(_ builtTypes: [BuiltType]) -> TypeLookupErrorOr<[Any.Type]> {
        var unwrapped: [Any.Type] = []
        unwrapped.reserveCapacity(builtTypes.count)
        for builtType in builtTypes {
            switch builtType {
            case .success(let type): unwrapped.append(type)
            case .failure(let error): return .failure(error)
            }
        }
        return .success(unwrapped)
    }

    private static func metadataPointer(of type: Any.Type) -> UnsafeRawPointer {
        unsafeBitCast(type, to: UnsafeRawPointer.self)
    }

    private static func anyType(fromMetadataPointer pointer: UnsafeRawPointer) -> Any.Type {
        unsafeBitCast(pointer, to: Any.Type.self)
    }

    /// Runtime name lookup: remangles `typeNode` to its bare type mangling and
    /// asks `swift_getTypeByMangledNameInEnvironment` — the entry behind
    /// `_typeByName`, covering every image the runtime has registered.
    private static func runtimeTypeByName(of typeNode: Node) -> Any.Type? {
        guard let mangledSymbol = try? mangleAsString(typeNode) else { return nil }
        var bareTypeMangling = Substring(mangledSymbol)
        if let prefixLength = manglingPrefixLength(of: mangledSymbol), prefixLength > 0 {
            bareTypeMangling = bareTypeMangling.dropFirst(prefixLength)
        }
        var utf8Bytes = Array(bareTypeMangling.utf8)
        return utf8Bytes.withUnsafeMutableBufferPointer { buffer -> Any.Type? in
            guard let baseAddress = buffer.baseAddress else { return nil }
            return baseAddress.withMemoryRebound(to: CChar.self, capacity: buffer.count) { characterPointer in
                guard let resolved = swift_getTypeByMangledNameInEnvironment(characterPointer, buffer.count, nil, nil) else {
                    return nil
                }
                return anyType(fromMetadataPointer: resolved)
            }
        }
    }

    private static func manglingPrefixLength(of mangledSymbol: String) -> Int? {
        for prefix in ["$s", "_$s", "$S", "_$S", "$e", "_$e"] where mangledSymbol.hasPrefix(prefix) {
            return prefix.count
        }
        return nil
    }

    /// `Module.Name` of a depth-1 nominal declaration node; `nil` for nested
    /// declarations (their resolution goes through the resolver seam).
    private static func qualifiedDeclarationName(of node: Node) -> String? {
        guard node.children.count >= 2,
              let moduleNode = node.children.first, moduleNode.kind == .module,
              let moduleName = moduleNode.text else { return nil }
        for child in node.children.dropFirst() where child.kind == .identifier {
            if let declarationName = child.text {
                return "\(moduleName).\(declarationName)"
            }
        }
        return nil
    }

    /// Descriptors of the standard library's common generic types, located
    /// through an arbitrary known instantiation's metadata — the same trick
    /// the sugar paths use, cached process-wide.
    private static nonisolated(unsafe) let standardLibraryGenericDescriptorPointersByQualifiedName: [String: UnsafeRawPointer] = {
        let knownInstantiations: [String: Any.Type] = [
            "Swift.Array": [Int].self,
            "Swift.ContiguousArray": ContiguousArray<Int>.self,
            "Swift.ArraySlice": ArraySlice<Int>.self,
            "Swift.Dictionary": [Int: Int].self,
            "Swift.Set": Set<Int>.self,
            "Swift.Optional": Int?.self,
            "Swift.Range": Range<Int>.self,
            "Swift.ClosedRange": ClosedRange<Int>.self,
            "Swift.PartialRangeFrom": PartialRangeFrom<Int>.self,
            "Swift.PartialRangeUpTo": PartialRangeUpTo<Int>.self,
            "Swift.PartialRangeThrough": PartialRangeThrough<Int>.self,
            "Swift.Result": Result<Int, Error>.self,
            "Swift.Unmanaged": Unmanaged<AnyObject>.self,
            "Swift.UnsafePointer": UnsafePointer<Int>.self,
            "Swift.UnsafeMutablePointer": UnsafeMutablePointer<Int>.self,
            "Swift.UnsafeBufferPointer": UnsafeBufferPointer<Int>.self,
            "Swift.UnsafeMutableBufferPointer": UnsafeMutableBufferPointer<Int>.self,
        ]
        var descriptorPointers: [String: UnsafeRawPointer] = [:]
        for (qualifiedName, instantiation) in knownInstantiations {
            guard let wrapper = try? Metadata.createInProcess(instantiation).typeContextDescriptorWrapper(),
                  let descriptorPointer = try? wrapper.typeContextDescriptor.asPointer else { continue }
            descriptorPointers[qualifiedName] = descriptorPointer
        }
        return descriptorPointers
    }()
}
