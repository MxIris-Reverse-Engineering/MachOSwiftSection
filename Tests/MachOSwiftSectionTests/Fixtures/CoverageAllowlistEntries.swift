import Foundation
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Public members of `Sources/MachOSwiftSection/Models/` that are intentionally
/// not under cross-reader fixture coverage. Each entry MUST carry either a
/// legacy exemption reason or a typed `SentinelReason`. The Coverage Invariant
/// Test treats listed entries as if they had been tested.
///
/// Categories:
///
///   - `legacyExempt`: scanner blind spots (e.g., `@MemberwiseInit` synthesized
///     init visible to `@testable` but not to the SwiftSyntax scanner).
///
///   - `.sentinel(.runtimeOnly(...))`: type is allocated by the Swift runtime
///     at type-load time and is never serialized into the fixture's Mach-O.
///     Covered via `InProcessMetadataPicker` + single-reader assertions in
///     Phase C; suite is allowed to skip cross-reader assertions.
///
///   - `.sentinel(.needsFixtureExtension(...))`: SymbolTestsCore lacks a
///     sample that surfaces this metadata shape. Should be eliminated by
///     Phase B; entries removed when each fixture file lands.
///
///   - `.sentinel(.pureDataUtility(...))`: pure raw-value enum / marker
///     protocol / pure-data utility. Sentinel status is intended to be
///     permanent; future follow-ups may pin rawValue literals.
enum CoverageAllowlistEntries {
    static let entries: [CoverageAllowlistEntry] = legacyEntries + sentinelEntries

    /// Pre-existing entries from PR #85 that aren't strictly sentinel-only.
    private static let legacyEntries: [CoverageAllowlistEntry] = [
        CoverageAllowlistEntry(
            typeName: "ProtocolDescriptorRef",
            memberName: "init(storage:)",
            reason: "synthesized memberwise initializer (visible via @testable)"
        ),
    ]

    /// All current sentinel-only suite methods (88 suites, ~277 methods).
    /// Phase B and Phase C remove entries here as suites are converted to
    /// real cross-reader / InProcess single-reader tests.
    private static let sentinelEntries: [CoverageAllowlistEntry] = (
        runtimeOnlyEntries
        + needsFixtureExtensionEntries
        + pureDataUtilityEntries
    )

    // MARK: - runtimeOnly

    private static let runtimeOnlyEntries: [CoverageAllowlistEntry] = [
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "Metadata",
            members: ["init", "kind", "valueWitnessTable"],
            reason: .runtimeOnly(detail: "abstract Metadata pointer; concrete kind dispatched at runtime")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "FullMetadata",
            members: ["init", "metadata", "header"],
            reason: .runtimeOnly(detail: "metadata layout prefix not serialized in section data")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "MetadataProtocol",
            members: ["kind", "valueWitnessTable"],
            reason: .runtimeOnly(detail: "marker protocol on runtime metadata")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "MetadataWrapper",
            members: ["init", "pointer", "kind"],
            reason: .runtimeOnly(detail: "wraps live runtime metadata pointer")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "MetadataRequest",
            members: ["init", "rawValue", "state", "isBlocking", "isNonBlocking"],
            reason: .runtimeOnly(detail: "passed to runtime metadata accessor functions")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "MetadataResponse",
            members: ["metadata", "state"],
            reason: .runtimeOnly(detail: "returned by runtime metadata accessor functions")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "MetadataAccessorFunction",
            members: ["init", "address", "invoke"],
            reason: .runtimeOnly(detail: "function pointer to runtime metadata accessor")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "SingletonMetadataPointer",
            members: ["init", "pointer", "metadata"],
            reason: .runtimeOnly(detail: "runtime singleton metadata cache pointer")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "MetadataBounds",
            members: ["init", "negativeSizeInWords", "positiveSizeInWords"],
            reason: .runtimeOnly(detail: "computed by runtime, not in section data")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "MetadataBoundsProtocol",
            members: ["negativeSizeInWords", "positiveSizeInWords"],
            reason: .runtimeOnly(detail: "marker protocol on runtime-computed bounds")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ClassMetadataBounds",
            members: ["init", "immediateMembers", "negativeSizeInWords", "positiveSizeInWords"],
            reason: .runtimeOnly(detail: "computed by runtime from ClassDescriptor + parent chain")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ClassMetadataBoundsProtocol",
            members: ["immediateMembers", "negativeSizeInWords", "positiveSizeInWords"],
            reason: .runtimeOnly(detail: "marker protocol on runtime-computed class bounds")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "StoredClassMetadataBounds",
            members: ["init", "immediateMembers", "bounds"],
            reason: .runtimeOnly(detail: "filled in by runtime at class-loading time")
        ),
        // Type-flavored runtime metadata (B/C-eligible ones go here too;
        // C will convert them when InProcessMetadataPicker provides pointers)
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "StructMetadata",
            members: ["init", "kind", "description", "fieldOffsetVectorOffset"],
            reason: .runtimeOnly(detail: "live runtime metadata pointer; covered via InProcess in Phase C")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "StructMetadataProtocol",
            members: ["description", "fieldOffsetVectorOffset"],
            reason: .runtimeOnly(detail: "marker protocol on StructMetadata")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "EnumMetadata",
            members: ["init", "kind", "description"],
            reason: .runtimeOnly(detail: "live runtime metadata; covered via InProcess in Phase C")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "EnumMetadataProtocol",
            members: ["description"],
            reason: .runtimeOnly(detail: "marker protocol on EnumMetadata")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ClassMetadata",
            members: ["init", "kind", "superclass", "flags", "instanceAddressPoint", "instanceSize", "instanceAlignMask", "classSize", "classAddressPoint", "description", "iVarDestroyer"],
            reason: .runtimeOnly(detail: "live class metadata; covered via InProcess in Phase C")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ClassMetadataObjCInterop",
            members: ["init", "isaPointer", "superclass", "cacheData0", "cacheData1", "data", "flags", "instanceAddressPoint", "instanceSize", "instanceAlignMask", "classSize", "classAddressPoint", "description", "iVarDestroyer"],
            reason: .runtimeOnly(detail: "live ObjC-interop class metadata; covered via InProcess in Phase C")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "AnyClassMetadata",
            members: ["init", "kind", "isaPointer", "superclass"],
            reason: .runtimeOnly(detail: "any-class metadata; covered via InProcess in Phase C")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "AnyClassMetadataObjCInterop",
            members: ["init", "isaPointer", "superclass", "cacheData0", "cacheData1", "data"],
            reason: .runtimeOnly(detail: "any-class metadata with ObjC interop; covered via InProcess in Phase C")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "AnyClassMetadataProtocol",
            members: ["isaPointer", "superclass"],
            reason: .runtimeOnly(detail: "marker protocol on AnyClassMetadata")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "AnyClassMetadataObjCInteropProtocol",
            members: ["isaPointer", "superclass", "cacheData0", "cacheData1", "data"],
            reason: .runtimeOnly(detail: "marker protocol on AnyClassMetadataObjCInterop")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "FinalClassMetadataProtocol",
            members: ["isaPointer", "superclass", "flags"],
            reason: .runtimeOnly(detail: "marker protocol on final class metadata")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "DispatchClassMetadata",
            members: ["init", "kind", "isaPointer", "superclass", "data", "ivar1", "flags"],
            reason: .runtimeOnly(detail: "Swift class with embedded ObjC metadata for dispatch; covered via InProcess")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ValueMetadata",
            members: ["init", "kind", "description"],
            reason: .runtimeOnly(detail: "value-type metadata (struct/enum); covered via InProcess in Phase C")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ValueMetadataProtocol",
            members: ["description"],
            reason: .runtimeOnly(detail: "marker protocol on ValueMetadata")
        ),
        // Existentials
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ExistentialTypeMetadata",
            members: ["init", "kind", "flags", "numberOfWitnessTables", "numberOfProtocols", "isClassConstrained", "isErrorExistential", "superclassConstraint", "protocols"],
            reason: .runtimeOnly(detail: "live existential metadata; covered via InProcess in Phase C")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ExistentialMetatypeMetadata",
            members: ["init", "kind", "instanceType", "flags"],
            reason: .runtimeOnly(detail: "live existential metatype; covered via InProcess in Phase C")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ExtendedExistentialTypeMetadata",
            members: ["init", "kind", "shape", "genericArguments"],
            reason: .runtimeOnly(detail: "Swift 5.7+ extended existential metadata; covered via InProcess")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ExtendedExistentialTypeShape",
            members: ["init", "flags", "existentialType", "requirementSignatureHeader", "typeExpression", "suggestedValueWitnesses"],
            reason: .runtimeOnly(detail: "Shape descriptor stored alongside extended existential metadata at runtime")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "NonUniqueExtendedExistentialTypeShape",
            members: ["init", "uniqueShape", "specializedShape"],
            reason: .runtimeOnly(detail: "non-uniqued shape variant computed at runtime")
        ),
        // Tuple/function/metatype/opaque/fixed-array/heap
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "TupleTypeMetadata",
            members: ["init", "kind", "numberOfElements", "labels", "elements"],
            reason: .runtimeOnly(detail: "tuple metadata is allocated lazily by the runtime; covered via InProcess")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "Element",
            members: ["init", "type", "offset"],
            reason: .runtimeOnly(detail: "TupleTypeMetadata.Element nested struct; lives in runtime tuple metadata")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "FunctionTypeMetadata",
            members: ["init", "kind", "flags", "result", "parameters", "parameterFlags"],
            reason: .runtimeOnly(detail: "function-type metadata is uniqued at runtime; covered via InProcess")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "MetatypeMetadata",
            members: ["init", "kind", "instanceType"],
            reason: .runtimeOnly(detail: "metatype metadata is per-type runtime singleton; covered via InProcess")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "OpaqueMetadata",
            members: ["init", "kind", "instanceType"],
            reason: .runtimeOnly(detail: "Swift Builtin opaque metadata; covered via InProcess")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "FixedArrayTypeMetadata",
            members: ["init", "kind", "count", "element"],
            reason: .runtimeOnly(detail: "InlineArray<N, T> runtime metadata; covered via InProcess on Swift 6.2+")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "GenericBoxHeapMetadata",
            members: ["init", "kind", "valueWitnessTable", "offsetOfBoxHeader", "captureOffset", "boxedType"],
            reason: .runtimeOnly(detail: "swift_allocBox-allocated; not feasible to construct stably from tests")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "HeapLocalVariableMetadata",
            members: ["init", "kind", "offsetToFirstCapture", "captureDescription"],
            reason: .runtimeOnly(detail: "captured by closures; not feasible to construct stably from tests")
        ),
        // Headers (live in metadata layout prefix)
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "HeapMetadataHeader",
            members: ["init", "destroy", "valueWitnessTable"],
            reason: .runtimeOnly(detail: "metadata layout prefix; readable via InProcess + offset")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "HeapMetadataHeaderPrefix",
            members: ["init", "destroy"],
            reason: .runtimeOnly(detail: "metadata layout prefix")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "TypeMetadataHeader",
            members: ["init", "destroy", "valueWitnessTable"],
            reason: .runtimeOnly(detail: "metadata layout prefix")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "TypeMetadataHeaderBase",
            members: ["destroy", "valueWitnessTable"],
            reason: .runtimeOnly(detail: "marker protocol on type-metadata layout prefix")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "TypeMetadataLayoutPrefix",
            members: ["destroy", "valueWitnessTable"],
            reason: .runtimeOnly(detail: "marker protocol on layout prefix")
        ),
        // Generic / VWT / runtime layer
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "GenericEnvironment",
            members: ["init", "flags", "genericParameters", "requirements"],
            reason: .runtimeOnly(detail: "generic environment is materialized at runtime")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "GenericWitnessTable",
            members: ["init", "witnessTableSizeInWords", "witnessTablePrivateSizeInWordsAndRequiresInstantiation", "instantiator", "privateData"],
            reason: .runtimeOnly(detail: "generic witness table allocated lazily by runtime")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ValueWitnessTable",
            members: ["init", "initializeBufferWithCopyOfBuffer", "destroy", "initializeWithCopy", "assignWithCopy", "initializeWithTake", "assignWithTake", "getEnumTagSinglePayload", "storeEnumTagSinglePayload", "size", "stride", "flags", "extraInhabitantCount"],
            reason: .runtimeOnly(detail: "value witness table is computed by runtime; covered via InProcess on stdlib types")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "TypeLayout",
            members: ["init", "size", "stride", "flags", "extraInhabitantCount"],
            reason: .runtimeOnly(detail: "value-witness-table layout slice; covered via InProcess")
        ),
        // Foreign metadata initialization
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ForeignMetadataInitialization",
            members: ["init", "completionFunction"],
            reason: .runtimeOnly(detail: "foreign-metadata callback installed by runtime")
        ),
    ].flatMap { $0 }

    // MARK: - needsFixtureExtension

    private static let needsFixtureExtensionEntries: [CoverageAllowlistEntry] = [
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "MethodDefaultOverrideDescriptor",
            members: ["originalMethodDescriptor", "replacementMethodDescriptor", "implementationSymbols", "layout", "offset"],
            reason: .needsFixtureExtension(detail: "no class with default-override table in SymbolTestsCore — Phase B1")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "MethodDefaultOverrideTableHeader",
            members: ["init", "numEntries"],
            reason: .needsFixtureExtension(detail: "no class with default-override table in SymbolTestsCore — Phase B1")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "OverrideTableHeader",
            members: ["init", "numEntries"],
            reason: .needsFixtureExtension(detail: "no class triggers method-override table in SymbolTestsCore — Phase B1")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ResilientSuperclass",
            members: ["init", "superclass", "layout", "offset"],
            reason: .needsFixtureExtension(detail: "no resilient class with explicit superclass reference — Phase B2")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ObjCClassWrapperMetadata",
            members: ["init", "kind", "objcClass"],
            reason: .needsFixtureExtension(detail: "no NSObject-derived class in SymbolTestsCore — Phase B3")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ObjCResilientClassStubInfo",
            members: ["init", "stub"],
            reason: .needsFixtureExtension(detail: "no Swift class inheriting resilient ObjC class — Phase B4")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "RelativeObjCProtocolPrefix",
            members: ["init", "isObjC", "rawValue"],
            reason: .needsFixtureExtension(detail: "no ObjC-prefix protocol references in SymbolTestsCore — Phase B3")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ObjCProtocolPrefix",
            members: ["init", "rawValue"],
            reason: .needsFixtureExtension(detail: "no ObjC-prefix protocol references in SymbolTestsCore — Phase B3")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "CanonicalSpecializedMetadataAccessorsListEntry",
            members: ["init", "accessor"],
            reason: .needsFixtureExtension(detail: "no @_specialize(exported:) generic in SymbolTestsCore — Phase B5")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "CanonicalSpecializedMetadatasCachingOnceToken",
            members: ["init", "token"],
            reason: .needsFixtureExtension(detail: "no @_specialize(exported:) generic in SymbolTestsCore — Phase B5")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "CanonicalSpecializedMetadatasListCount",
            members: ["init", "count"],
            reason: .needsFixtureExtension(detail: "no @_specialize(exported:) generic in SymbolTestsCore — Phase B5")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "CanonicalSpecializedMetadatasListEntry",
            members: ["init", "metadata"],
            reason: .needsFixtureExtension(detail: "no @_specialize(exported:) generic in SymbolTestsCore — Phase B5")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ForeignClassMetadata",
            members: ["init", "kind", "name", "superclass", "reserved"],
            reason: .needsFixtureExtension(detail: "no foreign class import in SymbolTestsCore — Phase B6")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ForeignReferenceTypeMetadata",
            members: ["init", "kind", "name"],
            reason: .needsFixtureExtension(detail: "no foreign reference type in SymbolTestsCore — Phase B6")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "GenericValueDescriptor",
            members: ["init", "type", "valueType"],
            reason: .needsFixtureExtension(detail: "no <let N: Int> value-generic type in SymbolTestsCore — Phase B7")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "GenericValueHeader",
            members: ["init", "numValues"],
            reason: .needsFixtureExtension(detail: "no <let N: Int> value-generic type in SymbolTestsCore — Phase B7")
        ),
    ].flatMap { $0 }

    // MARK: - pureDataUtility

    private static let pureDataUtilityEntries: [CoverageAllowlistEntry] = [
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ContextDescriptorFlags",
            members: ["init", "rawValue", "kind", "isGeneric", "isUnique", "version", "kindSpecificFlags"],
            reason: .pureDataUtility(detail: "raw bitfield over context descriptor flag word")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ContextDescriptorKindSpecificFlags",
            members: ["init", "rawValue"],
            reason: .pureDataUtility(detail: "raw bitfield over kind-specific flag word")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "AnonymousContextDescriptorFlags",
            members: ["init", "rawValue", "hasMangledName"],
            reason: .pureDataUtility(detail: "raw bitfield over anonymous descriptor flags")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "TypeContextDescriptorFlags",
            members: ["init", "rawValue", "metadataInitialization", "hasImportInfo", "hasCanonicalMetadataPrespecializations", "hasLayoutString"],
            reason: .pureDataUtility(detail: "raw bitfield over type-context flags")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ClassFlags",
            members: ["init", "rawValue", "hasResilientSuperclass", "hasOverrideTable", "hasVTable", "hasObjCResilientClassStub", "isActor", "isDefaultActor"],
            reason: .pureDataUtility(detail: "raw bitfield over class metadata flags")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ExtraClassDescriptorFlags",
            members: ["init", "rawValue", "hasObjCResilientClassStub"],
            reason: .pureDataUtility(detail: "raw bitfield over extra class descriptor flags")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "MethodDescriptorFlags",
            members: ["init", "rawValue", "isInstance", "isDynamic", "kind", "extraDiscriminator"],
            reason: .pureDataUtility(detail: "raw bitfield over method descriptor flags")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "MethodDescriptorKind",
            members: ["init", "rawValue"],
            reason: .pureDataUtility(detail: "method descriptor kind enum")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ProtocolDescriptorFlags",
            members: ["init", "rawValue", "hasClassConstraint", "isResilient", "specialProtocol", "dispatchStrategy"],
            reason: .pureDataUtility(detail: "raw bitfield over protocol descriptor flags")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ProtocolContextDescriptorFlags",
            members: ["init", "rawValue", "isClassConstrained", "isResilient", "specialProtocol"],
            reason: .pureDataUtility(detail: "raw bitfield over protocol-context flags")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ProtocolRequirementFlags",
            members: ["init", "rawValue", "kind", "isInstance", "extraDiscriminator"],
            reason: .pureDataUtility(detail: "raw bitfield over protocol requirement flags")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ProtocolRequirementKind",
            members: ["init", "rawValue"],
            reason: .pureDataUtility(detail: "protocol requirement kind enum")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "GenericContextDescriptorFlags",
            members: ["init", "rawValue", "hasTypePacks", "hasConditionalInvertedRequirements"],
            reason: .pureDataUtility(detail: "raw bitfield over generic context flags")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "GenericRequirementFlags",
            members: ["init", "rawValue", "hasKeyArgument", "isPackRequirement", "isValueRequirement", "kind"],
            reason: .pureDataUtility(detail: "raw bitfield over generic requirement flags")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "GenericEnvironmentFlags",
            members: ["init", "rawValue", "numGenericParameterLevels"],
            reason: .pureDataUtility(detail: "raw bitfield over generic environment flags")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "FieldRecordFlags",
            members: ["init", "rawValue", "isVar", "isArtificial"],
            reason: .pureDataUtility(detail: "raw bitfield over field record flags")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ProtocolConformanceFlags",
            members: ["init", "rawValue", "kind", "isRetroactive", "isSynthesizedNonUnique", "numConditionalRequirements", "numConditionalPackShapeDescriptors", "hasResilientWitnesses", "hasGenericWitnessTable", "isGlobalActorIsolated"],
            reason: .pureDataUtility(detail: "raw bitfield over protocol conformance flags")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ExistentialTypeFlags",
            members: ["init", "rawValue", "numProtocols", "numWitnessTables", "isClassConstraint", "isErrorExistential", "isObjCExistential"],
            reason: .pureDataUtility(detail: "raw bitfield over existential type flags")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ExtendedExistentialTypeShapeFlags",
            members: ["init", "rawValue", "specialKind", "hasGeneralizationSignature", "hasTypeExpression", "hasSuggestedValueWitnesses", "hasImplicitGenericParamsCount"],
            reason: .pureDataUtility(detail: "raw bitfield over extended existential shape flags")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "FunctionTypeFlags",
            members: ["init", "rawValue", "numParameters", "convention", "isThrowing", "isAsync", "isEscaping", "isSendable", "hasParameterFlags", "hasGlobalActor", "hasThrownError"],
            reason: .pureDataUtility(detail: "raw bitfield over function type flags")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ValueWitnessFlags",
            members: ["init", "rawValue", "alignmentMask", "isNonPOD", "isNonInline", "hasExtraInhabitants", "hasSpareBits", "isNonBitwiseTakable", "isIncomplete"],
            reason: .pureDataUtility(detail: "raw bitfield over value witness flags")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ContextDescriptorKind",
            members: ["init", "rawValue"],
            reason: .pureDataUtility(detail: "context descriptor kind enum")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "EnumFunctions",
            members: ["destroy", "initializeWithCopy", "destructiveInjectEnumTag", "destructiveProjectEnumValue", "getEnumTag"],
            reason: .pureDataUtility(detail: "enum-specific value witness function group; covered via VWT InProcess test")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "InvertibleProtocolSet",
            members: ["init", "rawValue", "contains", "isSuppressedByDefault"],
            reason: .pureDataUtility(detail: "raw bitset over invertible protocols")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "InvertibleProtocolsRequirementCount",
            members: ["init", "rawValue"],
            reason: .pureDataUtility(detail: "encoded count of invertible protocol requirements")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "TypeReference",
            members: ["init", "kind", "directType", "indirectType", "objCClassName"],
            reason: .pureDataUtility(detail: "discriminated union over type reference forms")
        ),
    ].flatMap { $0 }

    static var keys: Set<MethodKey> { Set(entries.map(\.key)) }

    /// Subset of `keys` whose entry kind is `.sentinel(...)`. Used by the
    /// Coverage Invariant Test for `liarSentinel` and `unmarkedSentinel`
    /// assertions.
    static var sentinelKeys: Set<MethodKey> {
        Set(entries.compactMap { entry in
            if case .sentinel = entry.kind { return entry.key } else { return nil }
        })
    }
}
