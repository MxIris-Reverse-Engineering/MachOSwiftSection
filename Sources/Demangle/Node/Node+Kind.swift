extension Node {
    public enum Kind: String, Hashable, Sendable, CaseIterable {
        case allocator
        case accessibleFunctionRecord
        case accessorFunctionReference
        case accessorAttachedMacroExpansion
        case anonymousContext
        case anonymousDescriptor
        case anyProtocolConformanceList
        case argumentTuple
        case associatedConformanceDescriptor
        case associatedType
        case associatedTypeDescriptor
        case associatedTypeGenericParamRef
        case associatedTypeMetadataAccessor
        case associatedTypeRef
        case associatedTypeWitnessTableAccessor
        case assocTypePath
        case asyncAnnotation
        case asyncAwaitResumePartialFunction
        case asyncFunctionPointer
        case asyncRemoved
        case asyncSuspendResumePartialFunction
        case autoClosureType
        case autoDiffDerivativeVTableThunk
        case autoDiffFunction
        case autoDiffFunctionKind
        case autoDiffSelfReorderingReabstractionThunk
        case autoDiffSubsetParametersThunk
        case backDeploymentThunk
        case backDeploymentFallback
        case baseConformanceDescriptor
        case baseWitnessTableAccessor
        case bodyAttachedMacroExpansion
        case boundGenericClass
        case boundGenericEnum
        case boundGenericFunction
        case boundGenericOtherNominalType
        case boundGenericProtocol
        case boundGenericStructure
        case boundGenericTypeAlias
        case builtinTypeName
        case builtinTupleType
        case builtinFixedArray
        case canonicalPrespecializedGenericTypeCachingOnceToken
        case canonicalSpecializedGenericMetaclass
        case canonicalSpecializedGenericTypeMetadataAccessFunction
        case cFunctionPointer
        case clangType
        case `class`
        case classMetadataBaseOffset
        case compileTimeConst
        case concreteProtocolConformance
        case concurrentFunctionType
        case conformanceAttachedMacroExpansion
        case constrainedExistential
        case constrainedExistentialRequirementList
        case constrainedExistentialSelf
        case constructor
        case coroutineContinuationPrototype
        case curryThunk
        case deallocator
        case declContext
        case defaultArgumentInitializer
        case defaultAssociatedConformanceAccessor
        case defaultAssociatedTypeMetadataAccessor
        case dependentAssociatedConformance
        case dependentAssociatedTypeRef
        case dependentGenericConformanceRequirement
        case dependentGenericInverseConformanceRequirement
        case dependentGenericLayoutRequirement
        case dependentGenericParamCount
        case dependentGenericParamPackMarker
        case dependentGenericParamValueMarker
        case dependentGenericParamType
        case dependentGenericSameShapeRequirement
        case dependentGenericSameTypeRequirement
        case dependentGenericSignature
        case dependentGenericType
        case dependentMemberType
        case dependentProtocolConformanceAssociated
        case dependentProtocolConformanceInherited
        case dependentProtocolConformanceRoot
        case dependentPseudogenericSignature
        case destructor
        case didSet
        case differentiabilityWitness
        case differentiableFunctionType
        case directMethodReferenceAttribute
        case directness
        case dispatchThunk
        case distributedAccessor
        case distributedThunk
        case droppedArgument
        case dynamicallyReplaceableFunctionImpl
        case dynamicallyReplaceableFunctionKey
        case dynamicallyReplaceableFunctionVar
        case dynamicAttribute
        case dynamicSelf
        case emptyList
        case `enum`
        case enumCase
        case errorType
        case escapingAutoClosureType
        case escapingObjCBlock
        case existentialMetatype
        case `extension`
        case explicitClosure
        case extendedExistentialTypeShape
        case extensionAttachedMacroExpansion
        case extensionDescriptor
        case fieldOffset
        case firstElementMarker
        case freestandingMacroExpansion
        case fullObjCResilientClassStub
        case fullTypeMetadata
        case function
        case functionSignatureSpecialization
        case functionSignatureSpecializationParam
        case functionSignatureSpecializationReturn
        case functionSignatureSpecializationParamKind
        case functionSignatureSpecializationParamPayload
        case functionType
        case genericPartialSpecialization
        case genericPartialSpecializationNotReAbstracted
        case genericProtocolWitnessTable
        case genericProtocolWitnessTableInstantiationFunction
        case genericSpecialization
        case genericSpecializationInResilienceDomain
        case genericSpecializationPrespecialized
        case genericSpecializationNotReAbstracted
        case genericSpecializationParam
        case genericTypeMetadataPattern
        case genericTypeParamDecl
        case getter
        case global
        case globalActorFunctionType
        case globalGetter
        case globalVariableOnceDeclList
        case globalVariableOnceToken
        case globalVariableOnceFunction
        case hasSymbolQuery
        case identifier
        case implConvention
        case implDifferentiabilityKind
        case implErrorResult
        case implEscaping
        case implErasedIsolation
        case implSendingResult
        case implParameterResultDifferentiability
        case implParameterSending
        case implFunctionAttribute
        case implFunctionConvention
        case implFunctionConventionName
        case implFunctionType
        case implCoroutineKind
        case implicitClosure
        case implInvocationSubstitutions
        case implParameter
        case implPatternSubstitutions
        case implResult
        case implYield
        case index
        case indexSubset
        case infixOperator
        case initAccessor
        case initializer
        case inlinedGenericFunction
        case inOut
        case integer
        case isolated
        case isolatedDeallocator
        case isolatedAnyFunctionType
        case nonIsolatedCallerFunctionType
        case isSerialized
        case iVarDestroyer
        case iVarInitializer
        case keyPathEqualsThunkHelper
        case keyPathGetterThunkHelper
        case keyPathHashThunkHelper
        case keyPathSetterThunkHelper
        case keyPathAppliedMethodThunkHelper
        case keyPathUnappliedMethodThunkHelper
        case labelList
        case lazyProtocolWitnessTableAccessor
        case lazyProtocolWitnessTableCacheVariable
        case localDeclName
        case macro
        case macroExpansionLoc
        case macroExpansionUniqueName
        case materializeForSet
        case memberAttachedMacroExpansion
        case memberAttributeAttachedMacroExpansion
        case mergedFunction
        case metaclass
        case metadataInstantiationCache
        case metatype
        case metatypeRepresentation
        case methodDescriptor
        case methodLookupFunction
        case modifyAccessor
        case modify2Accessor
        case module
        case moduleDescriptor
        case nativeOwningAddressor
        case nativeOwningMutableAddressor
        case nativePinningAddressor
        case nativePinningMutableAddressor
        case negativeInteger
        case noDerivative
        case noEscapeFunctionType
        case nominalTypeDescriptor
        case nominalTypeDescriptorRecord
        case noncanonicalSpecializedGenericTypeMetadata
        case noncanonicalSpecializedGenericTypeMetadataCache
        case nonObjCAttribute
        case nonUniqueExtendedExistentialTypeShapeSymbolicReference
        case number
        case objCAttribute
        case objCAsyncCompletionHandlerImpl
        case objCBlock
        case objCMetadataUpdateFunction
        case objCResilientClassStub
        case objectiveCProtocolSymbolicReference
        case opaqueReturnType
        case opaqueReturnTypeIndex
        case opaqueReturnTypeOf
        case opaqueReturnTypeParent
        case opaqueType
        case opaqueTypeDescriptor
        case opaqueTypeDescriptorAccessor
        case opaqueTypeDescriptorAccessorImpl
        case opaqueTypeDescriptorAccessorKey
        case opaqueTypeDescriptorAccessorVar
        case opaqueTypeDescriptorRecord
        case opaqueTypeDescriptorSymbolicReference
        case otherNominalType
        case outlinedAssignWithCopy
        case outlinedAssignWithCopyNoValueWitness
        case outlinedAssignWithTake
        case outlinedAssignWithTakeNoValueWitness
        case outlinedBridgedMethod
        case outlinedConsume
        case outlinedCopy
        case outlinedDestroy
        case outlinedDestroyNoValueWitness
        case outlinedEnumGetTag
        case outlinedEnumProjectDataForLoad
        case outlinedEnumTagStore
        case outlinedInitializeWithCopy
        case outlinedInitializeWithCopyNoValueWitness
        case outlinedInitializeWithTake
        case outlinedRelease
        case outlinedRetain
        case outlinedVariable
        case outlinedReadOnlyObject
        case owned
        case owningAddressor
        case owningMutableAddressor
        case pack
        case packElement
        case packElementLevel
        case packExpansion
        case packProtocolConformance
        case partialApplyForwarder
        case partialApplyObjCForwarder
        case peerAttachedMacroExpansion
        case postfixOperator
        case prefixOperator
        case predefinedObjCAsyncCompletionHandlerImpl
        case privateDeclName
        case propertyDescriptor
        case propertyWrapperBackingInitializer
        case propertyWrapperInitFromProjectedValue
        case `protocol`
        case protocolConformance
        case protocolConformanceDescriptorRecord
        case protocolConformanceRefInTypeModule
        case protocolConformanceRefInProtocolModule
        case protocolConformanceRefInOtherModule
        case protocolConformanceDescriptor
        case protocolDescriptor
        case protocolDescriptorRecord
        case protocolList
        case protocolListWithAnyObject
        case protocolListWithClass
        case protocolRequirementsBaseDescriptor
        case protocolSelfConformanceDescriptor
        case protocolSelfConformanceWitness
        case protocolSelfConformanceWitnessTable
        case protocolSymbolicReference
        case protocolWitness
        case protocolWitnessTable
        case protocolWitnessTableAccessor
        case protocolWitnessTablePattern
        case reabstractionThunk
        case reabstractionThunkHelper
        case reabstractionThunkHelperWithGlobalActor
        case reabstractionThunkHelperWithSelf
        case readAccessor
        case read2Accessor
        case reflectionMetadataAssocTypeDescriptor
        case reflectionMetadataBuiltinDescriptor
        case reflectionMetadataFieldDescriptor
        case reflectionMetadataSuperclassDescriptor
        case relatedEntityDeclName
        case resilientProtocolWitnessTable
        case retroactiveConformance
        case returnType
        case sending
        case sendingResultFunctionType
        case setter
        case shared
        case silBoxImmutableField
        case silBoxLayout
        case silBoxMutableField
        case silBoxType
        case silBoxTypeWithLayout
        case silPackDirect
        case silPackIndirect
        case silThunkIdentity
        case silThunkHopToMainActorIfNeeded
        case specializationPassID
        case `static`
        case structure
        case `subscript`
        case suffix
        case sugaredOptional
        case sugaredArray
        case sugaredDictionary
        case sugaredParen
        case symbolicExtendedExistentialType
        case typeSymbolicReference
        case thinFunctionType
        case throwsAnnotation
        case tuple
        case tupleElement
        case tupleElementName
        case type
        case typeAlias
        case typedThrowsAnnotation
        case typeList
        case typeMangling
        case typeMetadata
        case typeMetadataAccessFunction
        case typeMetadataCompletionFunction
        case typeMetadataDemanglingCache
        case typeMetadataInstantiationCache
        case typeMetadataInstantiationFunction
        case typeMetadataLazyCache
        case typeMetadataSingletonInitializationCache
        case uncurriedFunctionType
        case uniquable
        case uniqueExtendedExistentialTypeShapeSymbolicReference
        case unknownIndex
        case unmanaged
        case unowned
        case unsafeAddressor
        case unsafeMutableAddressor
        case valueWitness
        case valueWitnessTable
        case variable
        case variadicMarker
        case vTableAttribute // note: old mangling only
        case vTableThunk
        case weak
        case willSet
    }
}

extension Node.Kind {
    public var isDeclName: Bool {
        switch self {
        case .identifier,
             .localDeclName,
             .privateDeclName,
             .relatedEntityDeclName: fallthrough
        case .prefixOperator,
             .postfixOperator,
             .infixOperator: fallthrough
        case .typeSymbolicReference,
             .protocolSymbolicReference,
             .objectiveCProtocolSymbolicReference: return true
        default: return false
        }
    }

    public var isContext: Bool {
        switch self {
        case .allocator,
             .anonymousContext,
             .autoDiffFunction,
             .class,
             .constructor,
             .curryThunk,
             .deallocator,
             .defaultArgumentInitializer: fallthrough
        case .destructor,
             .didSet,
             .dispatchThunk,
             .enum,
             .explicitClosure,
             .extension,
             .function: fallthrough
        case .getter,
             .globalGetter,
             .iVarInitializer,
             .iVarDestroyer,
             .implicitClosure: fallthrough
        case .initializer,
             .initAccessor,
             .isolatedDeallocator,
             .materializeForSet,
             .modifyAccessor,
             .modify2Accessor: fallthrough
        case .module,
             .nativeOwningAddressor: fallthrough
        case .nativeOwningMutableAddressor,
             .nativePinningAddressor,
             .nativePinningMutableAddressor,
             .opaqueReturnTypeOf: fallthrough
        case .otherNominalType,
             .owningAddressor,
             .owningMutableAddressor,
             .propertyWrapperBackingInitializer: fallthrough
        case .propertyWrapperInitFromProjectedValue,
             .protocol,
             .protocolSymbolicReference,
             .readAccessor: fallthrough
        case .read2Accessor,
             .setter,
             .static: fallthrough
        case .structure,
             .subscript,
             .typeSymbolicReference,
             .typeAlias,
             .unsafeAddressor,
             .unsafeMutableAddressor: fallthrough
        case .variable,
             .willSet: return true
        default: return false
        }
    }

    public var isAnyGeneric: Bool {
        switch self {
        case .structure,
             .class,
             .enum,
             .protocol,
             .protocolSymbolicReference,
             .otherNominalType,
             .typeAlias,
             .typeSymbolicReference,
             .objectiveCProtocolSymbolicReference: return true
        default: return false
        }
    }

    public var isEntity: Bool {
        return self == .type || isContext
    }

    public var isRequirement: Bool {
        switch self {
        case .dependentGenericParamPackMarker,
             .dependentGenericParamValueMarker,
             .dependentGenericSameTypeRequirement,
             .dependentGenericSameShapeRequirement: fallthrough
        case .dependentGenericLayoutRequirement,
             .dependentGenericConformanceRequirement,
             .dependentGenericInverseConformanceRequirement: return true
        default: return false
        }
    }

    public var isFunctionAttr: Bool {
        switch self {
        case .functionSignatureSpecialization,
             .genericSpecialization,
             .genericSpecializationPrespecialized,
             .inlinedGenericFunction: fallthrough
        case .genericSpecializationNotReAbstracted,
             .genericPartialSpecialization: fallthrough
        case .genericPartialSpecializationNotReAbstracted,
             .genericSpecializationInResilienceDomain,
             .objCAttribute,
             .nonObjCAttribute: fallthrough
        case .dynamicAttribute,
             .directMethodReferenceAttribute,
             .vTableAttribute,
             .partialApplyForwarder: fallthrough
        case .partialApplyObjCForwarder,
             .outlinedVariable,
             .outlinedReadOnlyObject,
             .outlinedBridgedMethod,
             .mergedFunction: fallthrough
        case .distributedThunk,
             .distributedAccessor: fallthrough
        case .dynamicallyReplaceableFunctionImpl,
             .dynamicallyReplaceableFunctionKey,
             .dynamicallyReplaceableFunctionVar: fallthrough
        case .asyncFunctionPointer,
             .asyncAwaitResumePartialFunction,
             .asyncSuspendResumePartialFunction: fallthrough
        case .accessibleFunctionRecord,
             .backDeploymentThunk,
             .backDeploymentFallback: fallthrough
        case .hasSymbolQuery: return true
        default: return false
        }
    }
}

extension Node.Kind {
    public var isMacroExpansion: Bool {
        switch self {
        case .accessorAttachedMacroExpansion: return true
        case .memberAttributeAttachedMacroExpansion: return true
        case .freestandingMacroExpansion: return true
        case .memberAttachedMacroExpansion: return true
        case .peerAttachedMacroExpansion: return true
        case .conformanceAttachedMacroExpansion: return true
        case .extensionAttachedMacroExpansion: return true
        case .macroExpansionLoc: return true
        default: return false
        }
    }
}

extension Node.Kind {
    public var isExistentialType: Bool {
        switch self {
        case .existentialMetatype,
             .protocolList,
             .protocolListWithClass,
             .protocolListWithAnyObject: return true
        default: return false
        }
    }
}

extension Node.Kind: CustomStringConvertible {
    public var description: String {
        rawValue.capitalizingFirstLetter
    }
}


extension Sequence where Element == Node.Kind {
    public static var requirementKinds: [Node.Kind] {
        return [
            .dependentGenericParamPackMarker,
            .dependentGenericParamValueMarker,
            .dependentGenericSameTypeRequirement,
            .dependentGenericSameShapeRequirement,
            .dependentGenericLayoutRequirement,
            .dependentGenericConformanceRequirement,
            .dependentGenericInverseConformanceRequirement
        ]
    }
}

extension Node {
    package var identifier: String? {
        if let node = children.at(1), node.kind == .identifier {
            return node.text
        } else if let node = children.at(1), node.kind == .privateDeclName {
            return node.children.at(1)?.text
        } else if let node = first(of: .prefixOperator, .postfixOperator, .infixOperator) {
            return node.text
        } else if let node = first(of: .identifier) {
            return node.text
        } else if let node = first(of: .privateDeclName) {
            return node.children.at(1)?.text
        } else {
            return nil
        }
    }
}

extension Node {
    package func isKind(of kinds: Node.Kind...) -> Bool {
        return kinds.contains(kind)
    }
}
