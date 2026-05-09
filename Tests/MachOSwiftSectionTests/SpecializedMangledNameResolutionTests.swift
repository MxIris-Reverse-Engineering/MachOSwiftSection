import Foundation
import Testing
import MachOKit
@testable import MachOSwiftSection
@testable import MachOTestingSupport

// MARK: - Specialized mangled-name resolution

/// Exercises `RuntimeFunctions.getTypeByMangledNameInContext(_:specializedFrom:in:)`
/// — the helper that resolves a field's mangled type name to a concrete
/// `Any.Type` by deriving the descriptor pointer and the inline
/// generic-arguments array from a specialized in-process metadata.
///
/// Fixtures come from `MachOTestingSupport.SpecializedMangledNameFixtures` so
/// the descriptors live in the shared support module and stay reusable across
/// future suites. Each test still touches `T<U>.self` before reading the
/// metadata back so the runtime materializes the per-instantiation metadata.
@Suite(.serialized)
struct SpecializedMangledNameResolutionTests {
    private typealias Fixtures = SpecializedMangledNameFixtures

    // MARK: - Helpers

    private var machO: MachOImage { .current() }

    /// Locates the struct descriptor whose name contains `nameContains`.
    /// Substring matching keeps the lookup tolerant of the module-qualified
    /// nested-type prefix that the linker writes into the binary.
    private func structDescriptor(named nameContains: String) throws -> StructDescriptor {
        try #require(
            try machO.swift.typeContextDescriptors.first {
                try $0.struct?.name(in: machO).contains(nameContains) == true
            }?.struct,
            "expected a struct descriptor whose name contains \"\(nameContains)\""
        )
    }

    /// Locates the enum descriptor whose name contains `nameContains`.
    private func enumDescriptor(named nameContains: String) throws -> EnumDescriptor {
        try #require(
            try machO.swift.typeContextDescriptors.first {
                try $0.enum?.name(in: machO).contains(nameContains) == true
            }?.enum,
            "expected an enum descriptor whose name contains \"\(nameContains)\""
        )
    }

    /// Locates the class descriptor whose name contains `nameContains`.
    private func classDescriptor(named nameContains: String) throws -> ClassDescriptor {
        try #require(
            try machO.swift.typeContextDescriptors.first {
                try $0.class?.name(in: machO).contains(nameContains) == true
            }?.class,
            "expected a class descriptor whose name contains \"\(nameContains)\""
        )
    }

    /// Reads the mangled type name of the field at `fieldIndex` inside the
    /// descriptor's field descriptor. Asserts the index is in range so the
    /// test fails with a clear message rather than a generic out-of-bounds
    /// trap if the fixture's field count drifts.
    private func fieldMangledTypeName<Descriptor: TypeContextDescriptorProtocol>(
        of descriptor: Descriptor,
        atFieldIndex fieldIndex: Int
    ) throws -> MangledName {
        let fieldDescriptor = try descriptor.fieldDescriptor(in: machO)
        let records = try fieldDescriptor.records(in: machO)
        try #require(
            fieldIndex < records.count,
            "expected at least \(fieldIndex + 1) field record(s); fixture had \(records.count)"
        )
        return try records[fieldIndex].mangledTypeName(in: machO)
    }

    // MARK: - Single generic parameter

    @Test("resolves a single generic parameter to Int")
    func resolvesSingleParameterToInt() throws {
        // Force per-instantiation metadata emission. `T<U>.self` is enough —
        // the runtime materializes the specialized metadata before returning
        // the metatype.
        _ = Fixtures.SingleParameterBox<Int>.self

        let descriptor = try structDescriptor(named: "SingleParameterBox")
        let fieldName = try fieldMangledTypeName(of: descriptor, atFieldIndex: 0)
        let specializedMetadata = try StructMetadata.createInProcess(Fixtures.SingleParameterBox<Int>.self)

        let resolvedType = try #require(
            try RuntimeFunctions.getTypeByMangledNameInContext(
                fieldName,
                specializedFrom: specializedMetadata,
                in: machO
            )
        )
        #expect(ObjectIdentifier(resolvedType) == ObjectIdentifier(Int.self))
    }

    @Test("resolves the same parameter to a different concrete type per specialization")
    func resolvesSingleParameterToString() throws {
        _ = Fixtures.SingleParameterBox<String>.self

        let descriptor = try structDescriptor(named: "SingleParameterBox")
        let fieldName = try fieldMangledTypeName(of: descriptor, atFieldIndex: 0)
        let specializedMetadata = try StructMetadata.createInProcess(Fixtures.SingleParameterBox<String>.self)

        let resolvedType = try #require(
            try RuntimeFunctions.getTypeByMangledNameInContext(
                fieldName,
                specializedFrom: specializedMetadata,
                in: machO
            )
        )
        #expect(ObjectIdentifier(resolvedType) == ObjectIdentifier(String.self))
    }

    // MARK: - Multiple generic parameters

    @Test("respects positional ordering of two generic parameters")
    func respectsPositionalOrderingForTwoParameters() throws {
        _ = Fixtures.TwoParameterPair<Int, String>.self

        let descriptor = try structDescriptor(named: "TwoParameterPair")
        let firstFieldName = try fieldMangledTypeName(of: descriptor, atFieldIndex: 0)
        let secondFieldName = try fieldMangledTypeName(of: descriptor, atFieldIndex: 1)
        let specializedMetadata = try StructMetadata.createInProcess(Fixtures.TwoParameterPair<Int, String>.self)

        let firstResolved = try #require(
            try RuntimeFunctions.getTypeByMangledNameInContext(
                firstFieldName,
                specializedFrom: specializedMetadata,
                in: machO
            )
        )
        let secondResolved = try #require(
            try RuntimeFunctions.getTypeByMangledNameInContext(
                secondFieldName,
                specializedFrom: specializedMetadata,
                in: machO
            )
        )
        #expect(ObjectIdentifier(firstResolved) == ObjectIdentifier(Int.self))
        #expect(ObjectIdentifier(secondResolved) == ObjectIdentifier(String.self))
    }

    @Test("flipping the parameter order yields the swapped resolution")
    func flippedTwoParameterOrderingResolvesCorrectly() throws {
        // `TwoParameterPair<String, Int>` shares the same unbound descriptor
        // as the previous test but with the substitutions reversed. The
        // helper must read the array in metadata order — not pull from a
        // cache keyed on the descriptor alone.
        _ = Fixtures.TwoParameterPair<String, Int>.self

        let descriptor = try structDescriptor(named: "TwoParameterPair")
        let firstFieldName = try fieldMangledTypeName(of: descriptor, atFieldIndex: 0)
        let secondFieldName = try fieldMangledTypeName(of: descriptor, atFieldIndex: 1)
        let specializedMetadata = try StructMetadata.createInProcess(Fixtures.TwoParameterPair<String, Int>.self)

        let firstResolved = try #require(
            try RuntimeFunctions.getTypeByMangledNameInContext(
                firstFieldName,
                specializedFrom: specializedMetadata,
                in: machO
            )
        )
        let secondResolved = try #require(
            try RuntimeFunctions.getTypeByMangledNameInContext(
                secondFieldName,
                specializedFrom: specializedMetadata,
                in: machO
            )
        )
        #expect(ObjectIdentifier(firstResolved) == ObjectIdentifier(String.self))
        #expect(ObjectIdentifier(secondResolved) == ObjectIdentifier(Int.self))
    }

    // MARK: - Generic parameters inside compound types

    @Test("substitutes the generic parameter inside Array<A>")
    func substitutesIntoArrayOfGenericParameter() throws {
        _ = Fixtures.GenericArrayWrapper<Double>.self

        let descriptor = try structDescriptor(named: "GenericArrayWrapper")
        let arrayFieldName = try fieldMangledTypeName(of: descriptor, atFieldIndex: 0)
        let countFieldName = try fieldMangledTypeName(of: descriptor, atFieldIndex: 1)
        let specializedMetadata = try StructMetadata.createInProcess(Fixtures.GenericArrayWrapper<Double>.self)

        let arrayResolved = try #require(
            try RuntimeFunctions.getTypeByMangledNameInContext(
                arrayFieldName,
                specializedFrom: specializedMetadata,
                in: machO
            )
        )
        let countResolved = try #require(
            try RuntimeFunctions.getTypeByMangledNameInContext(
                countFieldName,
                specializedFrom: specializedMetadata,
                in: machO
            )
        )
        // The Array<A> field substitutes A=Double → [Double]; the Int field
        // has no generic ref but should still resolve via the same path.
        #expect(ObjectIdentifier(arrayResolved) == ObjectIdentifier([Double].self))
        #expect(ObjectIdentifier(countResolved) == ObjectIdentifier(Int.self))
    }

    @Test("substitutes the generic parameter inside Optional<A>")
    func substitutesIntoOptionalOfGenericParameter() throws {
        _ = Fixtures.OptionalGenericFieldStruct<Bool>.self

        let descriptor = try structDescriptor(named: "OptionalGenericFieldStruct")
        let fieldName = try fieldMangledTypeName(of: descriptor, atFieldIndex: 0)
        let specializedMetadata = try StructMetadata.createInProcess(Fixtures.OptionalGenericFieldStruct<Bool>.self)

        let resolvedType = try #require(
            try RuntimeFunctions.getTypeByMangledNameInContext(
                fieldName,
                specializedFrom: specializedMetadata,
                in: machO
            )
        )
        #expect(ObjectIdentifier(resolvedType) == ObjectIdentifier(Bool?.self))
    }

    @Test("substitutes both parameters inside Dictionary<Key, Value>")
    func substitutesIntoDictionaryFieldOverBothParameters() throws {
        _ = Fixtures.DictionaryGenericFieldStruct<String, Int>.self

        let descriptor = try structDescriptor(named: "DictionaryGenericFieldStruct")
        let fieldName = try fieldMangledTypeName(of: descriptor, atFieldIndex: 0)
        let specializedMetadata = try StructMetadata.createInProcess(Fixtures.DictionaryGenericFieldStruct<String, Int>.self)

        let resolvedType = try #require(
            try RuntimeFunctions.getTypeByMangledNameInContext(
                fieldName,
                specializedFrom: specializedMetadata,
                in: machO
            )
        )
        // Dictionary<Key, Value> needs both substitutions; if the helper
        // dropped or swapped either one, we'd see a different concrete type.
        #expect(ObjectIdentifier(resolvedType) == ObjectIdentifier([String: Int].self))
    }

    // MARK: - Enum metadata

    @Test("works for enum metadata as well as struct metadata")
    func resolvesGenericParameterInsideEnumPayload() throws {
        _ = Fixtures.GenericResultEnum<Int, Fixtures.FixtureError>.self

        let descriptor = try enumDescriptor(named: "GenericResultEnum")
        let payloadFieldName = try fieldMangledTypeName(of: descriptor, atFieldIndex: 0)
        let specializedMetadata = try EnumMetadata.createInProcess(Fixtures.GenericResultEnum<Int, Fixtures.FixtureError>.self)

        let resolvedType = try #require(
            try RuntimeFunctions.getTypeByMangledNameInContext(
                payloadFieldName,
                specializedFrom: specializedMetadata,
                in: machO
            )
        )
        // Enum's first case is `success(A)` — the payload type record points
        // straight at A, which the runtime must substitute to Int.
        #expect(ObjectIdentifier(resolvedType) == ObjectIdentifier(Int.self))
    }

    // MARK: - Class metadata

    @Test("works for class metadata (non-resilient superclass — Swift root)")
    func resolvesGenericParameterInsideRootClass() throws {
        _ = Fixtures.GenericContainerClass<Int>.self

        let descriptor = try classDescriptor(named: "GenericContainerClass")
        let fieldName = try fieldMangledTypeName(of: descriptor, atFieldIndex: 0)
        let specializedMetadata = try ClassMetadataObjCInterop.createInProcess(Fixtures.GenericContainerClass<Int>.self)

        let resolvedType = try #require(
            try RuntimeFunctions.getTypeByMangledNameInContext(
                fieldName,
                specializedFrom: specializedMetadata,
                in: machO
            )
        )
        #expect(ObjectIdentifier(resolvedType) == ObjectIdentifier(Int.self))
    }

    @Test("class path respects positional ordering of two generic parameters")
    func resolvesTwoParameterClassPositionalOrdering() throws {
        _ = Fixtures.TwoParameterContainerClass<Int, String>.self

        let descriptor = try classDescriptor(named: "TwoParameterContainerClass")
        let firstFieldName = try fieldMangledTypeName(of: descriptor, atFieldIndex: 0)
        let secondFieldName = try fieldMangledTypeName(of: descriptor, atFieldIndex: 1)
        let specializedMetadata = try ClassMetadataObjCInterop.createInProcess(Fixtures.TwoParameterContainerClass<Int, String>.self)

        let firstResolved = try #require(
            try RuntimeFunctions.getTypeByMangledNameInContext(
                firstFieldName,
                specializedFrom: specializedMetadata,
                in: machO
            )
        )
        let secondResolved = try #require(
            try RuntimeFunctions.getTypeByMangledNameInContext(
                secondFieldName,
                specializedFrom: specializedMetadata,
                in: machO
            )
        )
        #expect(ObjectIdentifier(firstResolved) == ObjectIdentifier(Int.self))
        #expect(ObjectIdentifier(secondResolved) == ObjectIdentifier(String.self))
    }

    @Test("class path resolves the subclass's own generic parameter")
    func resolvesSubclassOwnGenericParameter() throws {
        _ = Fixtures.GenericSubclass<Int, String>.self

        let descriptor = try classDescriptor(named: "GenericSubclass")
        // Subclass declares `let childValue: B` — index 0 in *its* field list.
        // Parent fields are not part of the subclass's field descriptor.
        let fieldName = try fieldMangledTypeName(of: descriptor, atFieldIndex: 0)
        let specializedMetadata = try ClassMetadataObjCInterop.createInProcess(Fixtures.GenericSubclass<Int, String>.self)

        let resolvedType = try #require(
            try RuntimeFunctions.getTypeByMangledNameInContext(
                fieldName,
                specializedFrom: specializedMetadata,
                in: machO
            )
        )
        // `childValue: B` → B is the second declared param → String.
        #expect(ObjectIdentifier(resolvedType) == ObjectIdentifier(String.self))
    }

    // MARK: - Negative paths

    @Test("non-generic field still resolves through the bare overload")
    func nonGenericFieldResolvesThroughBareOverload() throws {
        _ = Fixtures.NonGenericIntStruct.self

        let descriptor = try structDescriptor(named: "NonGenericIntStruct")
        let fieldName = try fieldMangledTypeName(of: descriptor, atFieldIndex: 0)

        // The bare overload (no specialization context) must still work
        // for fully-resolved mangled names — verifies the parameter-forwarding
        // bug fix didn't break the nil-context case.
        let resolvedType = try #require(
            try RuntimeFunctions.getTypeByMangledNameInContext(fieldName, in: machO)
        )
        #expect(ObjectIdentifier(resolvedType) == ObjectIdentifier(Int.self))
    }

    @Test("a generic-bearing mangled name resolves to nil without specialization context")
    func genericMangledNameReturnsNilWithoutContext() throws {
        // Sanity-check the negative path: when we know the mangled name
        // references generic params but don't supply them, the runtime
        // returns nil instead of trapping. This both documents the API
        // contract and pins the parameter-forwarding fix — pre-fix, the
        // C parameters were dropped and the runtime received `nil` either
        // way, so any call with a generic mangled name would have failed
        // silently (matching this test) regardless of whether the caller
        // passed the context. Combined with `resolvesSingleParameterToInt`
        // — which fails pre-fix — this pair pins the regression.
        _ = Fixtures.SingleParameterBox<Int>.self
        let descriptor = try structDescriptor(named: "SingleParameterBox")
        let fieldName = try fieldMangledTypeName(of: descriptor, atFieldIndex: 0)

        let resolvedType = try RuntimeFunctions.getTypeByMangledNameInContext(fieldName, in: machO)
        #expect(resolvedType == nil)
    }

    // MARK: - Integration: distinct specializations stay distinct

    @Test("two specializations of the same struct yield distinct resolved field metatypes")
    func twoSpecializationsYieldDistinctFieldMetatypes() throws {
        _ = Fixtures.SingleParameterBox<Int>.self
        _ = Fixtures.SingleParameterBox<String>.self

        let descriptor = try structDescriptor(named: "SingleParameterBox")
        let fieldName = try fieldMangledTypeName(of: descriptor, atFieldIndex: 0)
        let intMetadata = try StructMetadata.createInProcess(Fixtures.SingleParameterBox<Int>.self)
        let stringMetadata = try StructMetadata.createInProcess(Fixtures.SingleParameterBox<String>.self)

        let intResolved = try #require(
            try RuntimeFunctions.getTypeByMangledNameInContext(
                fieldName,
                specializedFrom: intMetadata,
                in: machO
            )
        )
        let stringResolved = try #require(
            try RuntimeFunctions.getTypeByMangledNameInContext(
                fieldName,
                specializedFrom: stringMetadata,
                in: machO
            )
        )
        #expect(ObjectIdentifier(intResolved) == ObjectIdentifier(Int.self))
        #expect(ObjectIdentifier(stringResolved) == ObjectIdentifier(String.self))
        // Identity comparison guards against accidental metadata collapse
        // if the helper ever cached on (descriptor, mangledName) without
        // keying on the substitutions.
        #expect(ObjectIdentifier(intResolved) != ObjectIdentifier(stringResolved))
    }
}
