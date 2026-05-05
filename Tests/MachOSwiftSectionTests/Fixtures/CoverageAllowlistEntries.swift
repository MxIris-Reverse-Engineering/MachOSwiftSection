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
            members: ["valueWitnessTable"],
            reason: .runtimeOnly(detail: "marker protocol on runtime metadata")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "MetadataWrapper",
            members: ["init", "pointer", "kind"],
            reason: .runtimeOnly(detail: "wraps live runtime metadata pointer")
        ),
        // MetadataRequest is covered as a real InProcess test in Phase C5
        // (bit-packing invariants exercised under `usingInProcessOnly`); no
        // sentinel entry remains.
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "MetadataResponse",
            members: ["metadata"],
            reason: .runtimeOnly(detail: "returned by runtime metadata accessor functions")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "MetadataAccessorFunction",
            members: ["init", "address", "invoke"],
            reason: .runtimeOnly(detail: "function pointer to runtime metadata accessor")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "SingletonMetadataPointer",
            members: ["init", "pointer", "metadata", "layout", "offset"],
            reason: .runtimeOnly(detail: "trailing payload appended only to descriptors carrying the `hasSingletonMetadataPointer` bit (cross-module canonical metadata caching); SymbolTestsCore declares no descriptor that fires this bit, so no live entry exists. Phase C5 considered conversion and kept sentinel.")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "MetadataBounds",
            members: ["init", "negativeSizeInWords", "positiveSizeInWords", "layout", "offset"],
            reason: .runtimeOnly(detail: "computed by runtime, not in section data; only constructed synthetically via the memberwise initialiser. Phase C5 considered conversion and kept sentinel — same rationale as `ClassMetadataBounds`, which has no runtime derivation path from a class metadata pointer (only static factories).")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "MetadataBoundsProtocol",
            members: ["negativeSizeInWords", "positiveSizeInWords", "addressPointInBytes", "totalSizeInBytes"],
            reason: .runtimeOnly(detail: "marker protocol on runtime-computed bounds")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ClassMetadataBounds",
            members: ["init", "immediateMembers", "negativeSizeInWords", "positiveSizeInWords", "layout", "offset"],
            reason: .runtimeOnly(detail: "computed by runtime from ClassDescriptor + parent chain")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ClassMetadataBoundsProtocol",
            members: ["immediateMembers", "negativeSizeInWords", "positiveSizeInWords", "adjustForSubclass", "forAddressPointAndSize", "forSwiftRootClass"],
            reason: .runtimeOnly(detail: "marker protocol on runtime-computed class bounds")
        ),
        // StoredClassMetadataBounds is covered as a real InProcess test in
        // Phase B2 against `ResilientClassFixtures.ResilientChild`'s
        // descriptor (the runtime allocates the bounds slot when the class
        // is loaded). No sentinel entry remains.
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
            members: ["isaPointer", "cacheData0", "cacheData1", "data"],
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
            reason: .runtimeOnly(detail: "Swift class with embedded ObjC metadata for dispatch; `layout`/`offset` covered via InProcess in Phase C4, remaining members scanner-attributed via marker protocols")
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
        // ExistentialTypeMetadata, ExistentialMetatypeMetadata,
        // ExtendedExistentialTypeMetadata, and ExtendedExistentialTypeShape
        // are covered as real InProcess tests in Phase C3 (no sentinel entries
        // remain). NonUniqueExtendedExistentialTypeShape stays sentinel because
        // its non-unique form is only emitted statically by the compiler before
        // runtime deduplication; runtime metadata always points at the unique
        // form, so it's not reachable through `InProcessMetadataPicker`.
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "NonUniqueExtendedExistentialTypeShape",
            members: ["existentialType", "layout", "offset"],
            reason: .runtimeOnly(detail: "non-unique shape form is only reachable from the compiler-emitted static record before runtime dedup; runtime metadata always points at the unique form")
        ),
        // Tuple/function/metatype/opaque/fixed-array/heap
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "TupleTypeMetadata",
            members: ["init"],
            reason: .runtimeOnly(detail: "tuple metadata is allocated lazily by the runtime; covered via InProcess `layout`/`offset`/`elements` tests")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "Element",
            members: ["init"],
            reason: .runtimeOnly(detail: "TupleTypeMetadata.Element nested struct; lives in runtime tuple metadata")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "FunctionTypeMetadata",
            members: ["init"],
            reason: .runtimeOnly(detail: "function-type metadata is uniqued at runtime; covered via InProcess `layout`/`offset` tests")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "MetatypeMetadata",
            members: ["init"],
            reason: .runtimeOnly(detail: "metatype metadata is per-type runtime singleton; covered via InProcess")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "OpaqueMetadata",
            members: ["init", "kind", "instanceType", "layout", "offset"],
            reason: .runtimeOnly(detail: "Swift Builtin opaque metadata; covered via InProcess")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "FixedArrayTypeMetadata",
            members: ["init", "kind", "count", "element", "layout", "offset"],
            reason: .runtimeOnly(detail: "InlineArray<N, T> runtime metadata; covered via InProcess on Swift 6.2+")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "GenericBoxHeapMetadata",
            members: ["init", "kind", "valueWitnessTable", "offsetOfBoxHeader", "captureOffset", "boxedType", "layout", "offset"],
            reason: .runtimeOnly(detail: "swift_allocBox-allocated; not feasible to construct stably from tests")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "HeapLocalVariableMetadata",
            members: ["init", "kind", "offsetToFirstCapture", "captureDescription", "layout", "offset"],
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
            reason: .runtimeOnly(detail: "metadata layout prefix; `layout`/`offset` covered via MachOImage in Phase C5, `destroy` scanner-attributed via the prefix-protocol layout")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "TypeMetadataHeader",
            members: ["init", "destroy", "valueWitnessTable"],
            reason: .runtimeOnly(detail: "metadata layout prefix")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "TypeMetadataHeaderBase",
            members: ["destroy", "valueWitnessTable", "layout", "offset"],
            reason: .runtimeOnly(detail: "marker protocol on type-metadata layout prefix")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "TypeMetadataLayoutPrefix",
            members: ["destroy", "valueWitnessTable", "layout", "offset"],
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
            members: ["init", "size", "stride", "flags", "extraInhabitantCount", "description", "debugDescription"],
            reason: .runtimeOnly(detail: "value-witness-table layout slice; covered via InProcess")
        ),
        // Foreign metadata initialization
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ForeignMetadataInitialization",
            members: ["init", "completionFunction", "layout", "offset"],
            reason: .runtimeOnly(detail: "foreign-metadata callback installed by runtime")
        ),
    ].flatMap { $0 }

    // MARK: - needsFixtureExtension

    private static let needsFixtureExtensionEntries: [CoverageAllowlistEntry] = [
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "MethodDefaultOverrideDescriptor",
            members: ["originalMethodDescriptor", "replacementMethodDescriptor", "implementationSymbols", "layout", "offset"],
            reason: .needsFixtureExtension(detail: "MethodDefaultOverrideTable requires experimental CoroutineAccessors (read2/modify2) on a resilient open class; macOS Swift runtime does not yet export _swift_deletedCalleeAllocatedCoroutineMethodErrorTwc, so the fixture cannot be built. Defer until ABI stabilizes.")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "MethodDefaultOverrideTableHeader",
            members: ["init", "numEntries"],
            reason: .needsFixtureExtension(detail: "MethodDefaultOverrideTable requires experimental CoroutineAccessors (read2/modify2) on a resilient open class; macOS Swift runtime does not yet export _swift_deletedCalleeAllocatedCoroutineMethodErrorTwc, so the fixture cannot be built. Defer until ABI stabilizes.")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "OverrideTableHeader",
            members: ["init", "numEntries"],
            reason: .needsFixtureExtension(detail: "init is synthesized memberwise init; numEntries is reached transitively via layout.numEntries (already exercised by the real OverrideTableHeader suite on Classes.SubclassTest).")
        ),
        // ResilientSuperclass is covered as a real cross-reader test in
        // Phase B2 against `ResilientClassFixtures.ResilientChild` (parent
        // `SymbolTestsHelper.ResilientBase`, cross-module). No sentinel
        // entry remains.
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
            members: ["init", "accessor", "layout", "offset"],
            reason: .needsFixtureExtension(detail: "no @_specialize(exported:) generic in SymbolTestsCore — Phase B5")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "CanonicalSpecializedMetadatasCachingOnceToken",
            members: ["init", "token", "layout", "offset"],
            reason: .needsFixtureExtension(detail: "no @_specialize(exported:) generic in SymbolTestsCore — Phase B5")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "CanonicalSpecializedMetadatasListCount",
            members: ["init", "count", "rawValue"],
            reason: .needsFixtureExtension(detail: "no @_specialize(exported:) generic in SymbolTestsCore — Phase B5")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "CanonicalSpecializedMetadatasListEntry",
            members: ["init", "metadata", "layout", "offset"],
            reason: .needsFixtureExtension(detail: "no @_specialize(exported:) generic in SymbolTestsCore — Phase B5")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ForeignClassMetadata",
            members: ["init", "kind", "name", "superclass", "reserved", "classDescriptor", "layout", "offset"],
            reason: .needsFixtureExtension(detail: "no foreign class import in SymbolTestsCore — Phase B6")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ForeignReferenceTypeMetadata",
            members: ["init", "kind", "name", "classDescriptor", "layout", "offset"],
            reason: .needsFixtureExtension(detail: "no foreign reference type in SymbolTestsCore — Phase B6")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "OpaqueType",
            members: ["descriptor", "genericContext", "invertedProtocols", "underlyingTypeArgumentMangledNames"],
            reason: .needsFixtureExtension(detail: "opaque-type descriptors in SymbolTestsCore aren't reachable through swift.contextDescriptors on current toolchain")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "OpaqueTypeDescriptor",
            members: ["layout", "offset"],
            reason: .needsFixtureExtension(detail: "opaque-type descriptor not reachable from SymbolTestsCore section walks; suite uses synthetic memberwise instance")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "OpaqueTypeDescriptorProtocol",
            members: ["numUnderlyingTypeArugments"],
            reason: .needsFixtureExtension(detail: "opaque-type descriptor not reachable; protocol extension exercised on synthetic descriptor")
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
            members: ["init"],
            reason: .pureDataUtility(detail: "memberwise initializer not surfaced by the public-member scanner")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ContextDescriptorKindSpecificFlags",
            members: ["init", "rawValue"],
            reason: .pureDataUtility(detail: "raw bitfield over kind-specific flag word")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "AnonymousContextDescriptorFlags",
            members: ["init"],
            reason: .pureDataUtility(detail: "memberwise initializer not surfaced by the public-member scanner")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "TypeContextDescriptorFlags",
            members: ["init", "metadataInitialization", "hasCanonicalMetadataPrespecializations"],
            reason: .pureDataUtility(detail: "memberwise initializer + accessors not exercised by the cross-reader Suite")
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
            members: ["init"],
            reason: .pureDataUtility(detail: "memberwise initializer not surfaced by the public-member scanner")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "MethodDescriptorKind",
            members: ["init", "rawValue", "description"],
            reason: .pureDataUtility(detail: "method descriptor kind enum")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ProtocolDescriptorFlags",
            members: ["init", "rawValue", "hasClassConstraint", "isResilient", "specialProtocol", "dispatchStrategy", "classConstraint", "isSwift", "needsProtocolWitnessTable", "specialProtocolKind"],
            reason: .pureDataUtility(detail: "raw bitfield over protocol descriptor flags")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ProtocolContextDescriptorFlags",
            members: ["init", "isClassConstrained", "specialProtocol"],
            reason: .pureDataUtility(detail: "memberwise initializer + accessors not exercised by the cross-reader Suite")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ProtocolRequirementFlags",
            members: ["init", "extraDiscriminator"],
            reason: .pureDataUtility(detail: "memberwise initializer + accessors not exercised by the cross-reader Suite")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ProtocolRequirementKind",
            members: ["init", "rawValue", "description"],
            reason: .pureDataUtility(detail: "protocol requirement kind enum")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "GenericContextDescriptorFlags",
            members: ["init", "rawValue", "hasTypePacks", "hasConditionalInvertedRequirements", "hasConditionalInvertedProtocols", "hasValues"],
            reason: .pureDataUtility(detail: "raw bitfield over generic context flags")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "GenericRequirementFlags",
            members: ["init", "rawValue", "hasKeyArgument", "isPackRequirement", "isValueRequirement", "kind"],
            reason: .pureDataUtility(detail: "raw bitfield over generic requirement flags")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "GenericEnvironmentFlags",
            members: ["init", "rawValue", "numGenericParameterLevels", "numberOfGenericParameterLevels", "numberOfGenericRequirements"],
            reason: .pureDataUtility(detail: "raw bitfield over generic environment flags")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "FieldRecordFlags",
            members: ["init", "rawValue", "isVar", "isArtificial", "isIndirectCase", "isVariadic"],
            reason: .pureDataUtility(detail: "raw bitfield over field record flags")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ProtocolConformanceFlags",
            members: ["init", "rawValue", "kind", "isRetroactive", "isSynthesizedNonUnique", "numConditionalRequirements", "numConditionalPackShapeDescriptors", "hasResilientWitnesses", "hasGenericWitnessTable", "isGlobalActorIsolated", "hasGlobalActorIsolation", "hasNonDefaultSerialExecutorIsIsolatingCurrentContext", "isConformanceOfProtocol", "typeReferenceKind"],
            reason: .pureDataUtility(detail: "raw bitfield over protocol conformance flags")
        ),
        // ExistentialTypeFlags + ExtendedExistentialTypeShapeFlags are
        // covered as real InProcess tests in Phase C3 (no sentinel entries
        // remain).
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "FunctionTypeFlags",
            members: ["init", "init(rawValue:)", "rawValue", "numParameters", "convention", "isThrowing", "isAsync", "isEscaping", "isSendable", "hasParameterFlags", "hasGlobalActor", "hasThrownError", "hasExtendedFlags", "isDifferentiable"],
            reason: .pureDataUtility(detail: "raw bitfield over function type flags")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "ValueWitnessFlags",
            members: ["init", "rawValue", "alignmentMask", "isNonPOD", "isNonInline", "hasExtraInhabitants", "hasSpareBits", "isNonBitwiseTakable", "isIncomplete", "alignment", "hasEnumWitnesses", "inComplete", "isBitwiseBorrowable", "isBitwiseTakable", "isCopyable", "isInlineStorage", "isNonBitwiseBorrowable", "isNonCopyable", "isPOD", "maxNumExtraInhabitants"],
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
            typeName: "EnumTagCounts",
            members: ["numTags", "numTagBytes"],
            reason: .pureDataUtility(detail: "result struct of pure function getEnumTagCounts; covered via literal-baseline assertions")
        ),
        CoverageAllowlistHelpers.sentinelGroup(
            typeName: "InvertibleProtocolSet",
            members: ["init", "rawValue", "contains", "isSuppressedByDefault", "copyable", "escapable", "hasCopyable", "hasEscapable"],
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
