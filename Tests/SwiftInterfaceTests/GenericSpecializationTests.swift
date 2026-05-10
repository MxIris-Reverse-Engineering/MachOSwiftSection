import Foundation
import Testing
import MachOKit
import Dependencies
@_spi(Internals) import MachOSymbols
@_spi(Internals) import MachOCaches
@_spi(Support) @testable import SwiftInterface
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport
@testable import SwiftDump
@testable @_spi(Internals) import SwiftInspection
@testable import Demangling
import OrderedCollections

@Suite(.serialized)
struct GenericSpecializationTests {
    // MARK: - Fixture types
    //
    // All generic-shape fixtures live on the outer suite so that the
    // file-scope conditional `Copyable` / `Escapable` extensions at the
    // bottom of this file can keep referencing them via the canonical
    // paths (e.g. `GenericSpecializationTests.NestedInvertedOuter
    // .NestedInvertedMiddle.NestedInvertedInner`). Most fixtures are
    // looked up by mangled-name substring on the binary at runtime, so
    // the only Swift-side requirement is that the type be present
    // somewhere in the test image.

    struct TestGenericStruct<A: Collection, B: Equatable, C: Hashable> where A.Element: Hashable, A.Element: Decodable, A.Element: Encodable {
        let a: A
        let b: B
        let c: C
    }

    struct TestUnconstrainedStruct<A> {
        let a: A
    }

    struct TestSingleProtocolStruct<A: Hashable> {
        let a: A
    }

    struct TestMultiProtocolStruct<A: Hashable & Decodable & Encodable> {
        let a: A
    }

    struct TestClassConstraintStruct<A: AnyObject> {
        let a: A
    }

    final class TestRefClass {}

    struct TestNestedAssociatedStruct<A: Sequence> where A.Element: Sequence, A.Element.Element: Hashable {
        let a: A
    }

    struct TestDualAssociatedStruct<A: Sequence, B: Sequence> where A.Element: Hashable, B.Element: Hashable {
        let a: A
        let b: B
    }

    struct TestMixedConstraintsStruct<A: Collection, B: Hashable> where A.Element: Hashable {
        let a: A
        let b: B
    }

    struct TestInvertedCopyableStruct<A: ~Copyable>: ~Copyable {
        let a: A
    }

    /// Two-level nested generic. **Baseline** — single-level parent nesting
    /// happens to produce the right `(depth, index)` mapping because
    /// `parentParameters.last.count` and `parentParameters.flatMap.count`
    /// coincide when there is only one parent generic context. The matching
    /// test should keep passing on the current implementation.
    struct NestedGenericTwoLevelOuter<A: Hashable> {
        struct NestedGenericTwoLevelInner<B: Equatable> {
            let a: A
            let b: B
        }
    }

    /// Three-level nested generic — one type parameter per level, each with
    /// a different protocol constraint. Exercises **P0.1** (the
    /// `currentRequirements` flatMap miscount in `GenericContext.swift:50`)
    /// and **P0.2** (the `buildParameters` (depth, index) iteration over the
    /// cumulative `allParameters` in `GenericSpecializer.swift:131`).
    struct NestedGenericThreeLevelOuter<A: Hashable> {
        struct NestedGenericThreeLevelMiddle<B: Equatable> {
            struct NestedGenericThreeLevelInner<C: Comparable> {
                let a: A
                let b: B
                let c: C
            }
        }
    }

    /// Three-level nested generic with `~Copyable` on every type parameter.
    /// Each layer's `InvertedProtocols` requirement records the suppressed
    /// parameter via a *flat* `genericParamIndex` set by Swift's
    /// `lib/IRGen/GenMeta.cpp:7488-7501` — `sig->getGenericParamOrdinal(genericParam)`
    /// returns the parameter's position across **every** depth.
    ///
    /// Expected:
    ///   "A"   → flat index 0 → invertibleProtocols == .copyable
    ///   "A1"  → flat index 1 → invertibleProtocols == .copyable
    ///   "A2"  → flat index 2 → invertibleProtocols == .copyable
    struct NestedInvertedOuter<A: ~Copyable>: ~Copyable {
        struct NestedInvertedMiddle<B: ~Copyable>: ~Copyable {
            struct NestedInvertedInner<C: ~Copyable>: ~Copyable {
                var a: A
                var b: B
                var c: C
            }
        }
    }

    struct TestTypePackStruct<each T> {
        let value: (repeat each T)
    }

    /// Fixture with three generic parameters whose associated-type chains
    /// can resolve to overlapping leaf metadata (A=[Int], B=String,
    /// C=[Int] makes A.Element and C.Element both Int). Used by the
    /// PWT-ordering invariant tests.
    struct TestTriAssociatedSameLeafStruct<A: Sequence, B: Sequence, C: Sequence>
        where A.Element: Hashable, B.Element: Hashable, C.Element: Hashable
    {
        let a: A
        let b: B
        let c: C
    }

    struct TestNonGenericStruct {
        let value: Int
    }

    enum TestInvertedEscapableEnum<A: ~Escapable>: ~Escapable {}

    enum TestInvertedDualEnum<A: ~Copyable & ~Escapable>: ~Copyable & ~Escapable {}

    enum TestGenericEnum<A: Hashable> {
        case some(A)
        case none
    }

    final class TestGenericClass<A: Hashable> {
        let a: A
        init(a: A) { self.a = a }
    }

    // Fixtures used by the baseClass-requirement preflight tests. The
    // class shapes mirror a tiny three-level inheritance chain so a single
    // suite can pin (a) a successful direct match, (b) a successful
    // multi-step superclass walk, and (c) a failed walk on an unrelated
    // class, all without dragging external frameworks into the test image.
    class TestRequirementBaseClass {
        var baseField: Int = 0
        init() {}
    }

    class TestRequirementSubClass: TestRequirementBaseClass {}

    final class TestRequirementGrandChildClass: TestRequirementSubClass {}

    final class TestRequirementUnrelatedClass {}

    /// `<A: TestRequirementBaseClass>` — single-parameter struct used to
    /// drive the baseClass requirement through both `runtimePreflight`
    /// (subclass / non-subclass / non-class checks) and `specialize`
    /// (the metadata accessor is happy with any class because baseClass
    /// has `hasKeyArgument == false`).
    struct TestBaseClassRequirementStruct<A: TestRequirementBaseClass> {
        let a: A
    }

    /// Helper protocol carrying an associated type used as the RHS of the
    /// sameType-requirement fixture below. Lives in this test file because
    /// it is a Swift-6-language-mode workaround: every shape of sameType
    /// that the language *will* accept (`A == B`, `A == Int`,
    /// `B == A` even when nested) is rejected as redundant or
    /// non-generic, so the fixture is forced into the only remaining
    /// shape — `A == B.Element` — which keeps both sides in the same
    /// generic context without making either side trivially equivalent.
    protocol TestSameTypeAssocCarrier {
        associatedtype Element
    }

    /// `<A, B: TestSameTypeAssocCarrier> where A == B.Element` — fixture
    /// used by the sameType preflight tests. The LHS is a direct generic
    /// parameter, so `collectRequirements` attaches the resulting
    /// `.sameType` record to `A`'s requirement list (the side that the
    /// preflight check inspects). The RHS is an associated-type access
    /// path which exercises the dedicated downgrade-to-warning branch in
    /// `runtimeSameTypeCheck`.
    struct TestSameTypeViaAssocStruct<A, B: TestSameTypeAssocCarrier> where A == B.Element {
        let a: A
        let b: B
    }

    /// Two unrelated protocols both declaring `associatedtype Element`.
    /// The companion `DualElementStruct` fixture pins the Swift compiler's
    /// GenericSignature minimization invariant — see the matching test
    /// `dualProtocolSameNamedAssociatedTypeIsCanonicalized`.
    protocol PWithElement {
        associatedtype Element: Hashable
        func produceElement() -> Element
    }

    protocol QWithElement {
        associatedtype Element: Comparable
        func consumeElement(_: Element)
    }

    struct DualElementStruct<A: PWithElement & QWithElement> where A.Element: Codable {
        let value: A
    }

    // MARK: - Make Request
    //
    // `makeRequest` and request-shape inspection. Tests here verify the
    // structure of the produced `SpecializationRequest` (parameters,
    // requirements, candidates, invertible-protocol flags, associated-type
    // path aggregation). End-to-end specialization is in the `Specialize`
    // suite below.

    @Suite("Make Request")
    struct MakeRequest: GenericSpecializationTestingEnvironment {
        @Test func basicShape() async throws {
            let descriptor = try structDescriptor(named: "TestGenericStruct")

            let specializer = GenericSpecializer(
                machO: machO,
                conformanceProvider: IndexerConformanceProvider(indexer: try await indexer)
            )
            let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

            // Should have 3 parameters: A, B, C
            #expect(request.parameters.count == 3)

            // Check parameter names follow depth/index naming convention
            #expect(request.parameters[0].name == "A")
            #expect(request.parameters[1].name == "B")
            #expect(request.parameters[2].name == "C")

            // Check requirements exist
            #expect(request.parameters[0].hasProtocolRequirements) // A: Collection
            #expect(request.parameters[1].hasProtocolRequirements) // B: Equatable
            #expect(request.parameters[2].hasProtocolRequirements) // C: Hashable

            // Check associated type requirements
            #expect(!request.associatedTypeRequirements.isEmpty)
        }

        @Test func rejectsNonGenericType() throws {
            let descriptor = try structDescriptor(named: "TestNonGenericStruct")
            let specializer = GenericSpecializer(
                machO: machO,
                conformanceProvider: EmptyConformanceProvider()
            )

            do {
                _ = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))
                Issue.record("expected notGenericType to be thrown for a fixture without generic context")
            } catch let error as GenericSpecializer<MachOImage>.SpecializerError {
                switch error {
                case .notGenericType:
                    return
                default:
                    Issue.record("expected notGenericType, got \(error)")
                }
            }
        }

        @Test func rejectsTypePackParameter() throws {
            let descriptor = try structDescriptor(named: "TestTypePackStruct")

            let specializer = GenericSpecializer(
                machO: machO,
                conformanceProvider: EmptyConformanceProvider()
            )

            do {
                _ = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))
                Issue.record("P3: makeRequest must reject a fixture containing a TypePack parameter")
            } catch let error as GenericSpecializer<MachOImage>.SpecializerError {
                switch error {
                case .unsupportedGenericParameter(let kind):
                    #expect(kind == .typePack)
                default:
                    Issue.record("P3: expected unsupportedGenericParameter, got \(error)")
                }
            }
        }

        @Test func excludeGenericsFiltersGenericCandidates() async throws {
            let descriptor = try structDescriptor(named: "TestSingleProtocolStruct")
            let specializer = GenericSpecializer(indexer: try await indexer)

            let defaultRequest = try specializer.makeRequest(
                for: TypeContextDescriptorWrapper.struct(descriptor)
            )
            let defaultHasGenericCandidate = defaultRequest.parameters[0].candidates.contains { $0.isGeneric }
            #expect(defaultHasGenericCandidate, "P7 baseline: default candidate list should include generic candidates")

            let filteredRequest = try specializer.makeRequest(
                for: TypeContextDescriptorWrapper.struct(descriptor),
                candidateOptions: .excludeGenerics
            )
            let filteredHasGenericCandidate = filteredRequest.parameters[0].candidates.contains { $0.isGeneric }
            #expect(!filteredHasGenericCandidate, "P7: excludeGenerics must drop every isGeneric candidate")
            #expect(!filteredRequest.parameters[0].candidates.isEmpty,
                    "P7: there are still non-generic Hashable conformers (Int, String, …) — the filter must not empty the list")
        }

        @Test func noInvertedRequirementYieldsNil() async throws {
            let descriptor = try structDescriptor(named: "TestGenericStruct")

            let specializer = GenericSpecializer(indexer: try await indexer)
            let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

            #expect(request.parameters.count == 3)
            for parameter in request.parameters {
                #expect(parameter.invertibleProtocols == nil)
            }
        }

        @Test func invertedCopyableExposed() async throws {
            let descriptor = try structDescriptor(named: "TestInvertedCopyableStruct")

            let specializer = GenericSpecializer(indexer: try await indexer)
            let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

            #expect(request.parameters.count == 1)

            let invertible = try #require(request.parameters[0].invertibleProtocols)
            // ~Copyable only: the set encodes which protocols are suppressed, so
            // the parameter declaring `~Copyable` (and not `~Escapable`) must
            // produce exactly `[.copyable]` — using `==` instead of `contains`
            // catches a regression where extra bits leak into the set.
            #expect(invertible == .copyable)

            // Specialize with a Copyable type (Int) — the conditional Copyable
            // extension makes the struct itself Copyable when A is Copyable, so
            // the metadata accessor should succeed.
            let result = try specializer.specialize(request, with: ["A": .metatype(Int.self)])
            let structMetadata = try #require(result.resolveMetadata().struct)
            #expect(try structMetadata.fieldOffsets() == [0])
        }

        @Test func invertedEscapableExposed() async throws {
            let descriptor = try enumDescriptor(named: "TestInvertedEscapableEnum")
            let specializer = GenericSpecializer(
                machO: machO,
                conformanceProvider: EmptyConformanceProvider()
            )
            let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.enum(descriptor))

            #expect(request.parameters.count == 1)
            let invertible = try #require(request.parameters[0].invertibleProtocols)
            #expect(invertible == .escapable, "single ~Escapable should produce exactly the Escapable bit")
        }

        @Test func invertedDualCopyableAndEscapable() async throws {
            let descriptor = try enumDescriptor(named: "TestInvertedDualEnum")
            let specializer = GenericSpecializer(
                machO: machO,
                conformanceProvider: EmptyConformanceProvider()
            )
            let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.enum(descriptor))

            #expect(request.parameters.count == 1)
            let invertible = try #require(request.parameters[0].invertibleProtocols)
            // Set equality — both bits must be present and nothing else.
            #expect(invertible == InvertibleProtocolSet([.copyable, .escapable]))
        }

        @Test func nestedAssociatedTypeShape() async throws {
            let (descriptor, genericContext) = try genericStructFixture(named: "TestNestedAssociatedStruct")

            // 1 metadata + 3 PWT (A:Sequence, A.Element:Sequence, A.Element.Element:Hashable)
            #expect(genericContext.header.numKeyArguments == 4)

            let specializer = GenericSpecializer(indexer: try await indexer)
            let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

            #expect(request.parameters.count == 1)
            #expect(request.parameters[0].protocolRequirements.count == 1)

            // Two associated requirements: A.Element and A.Element.Element
            #expect(request.associatedTypeRequirements.count == 2)

            let pathByDepth = request.associatedTypeRequirements.map(\.path)
            // The single-level path "[Element]" must exist (A.Element: Sequence)
            #expect(pathByDepth.contains(["Element"]))
            // The two-level path "[Element, Element]" must exist (A.Element.Element: Hashable)
            #expect(pathByDepth.contains(["Element", "Element"]))
        }

        // P8 reproduction: AssociatedTypeRequirement aggregates by (param, path).
        //
        // Pre-fix every individual constraint emitted its own
        // `AssociatedTypeRequirement` even when several constraints shared
        // the same `(parameterName, path)` — `requirements: [Requirement]`
        // was always a singleton array, despite the field being plural.
        // Consumers had to re-group by hand. Post-fix the build pass
        // aggregates by key and preserves canonical (binary) order inside
        // each entry.
        @Test func associatedTypeRequirementsAggregatedByPath() async throws {
            // TestGenericStruct has three constraints on A.Element (Hashable,
            // Decodable, Encodable). Pre-fix `associatedTypeRequirements` would
            // hold three entries with `path == ["Element"]` each carrying one
            // requirement. Post-fix it should hold a single entry whose
            // `requirements` array carries all three.
            let descriptor = try structDescriptor(named: "TestGenericStruct")
            let specializer = GenericSpecializer(
                machO: machO,
                conformanceProvider: EmptyConformanceProvider()
            )
            let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

            let elementEntries = request.associatedTypeRequirements.filter {
                $0.parameterName == "A" && $0.path == ["Element"]
            }
            #expect(
                elementEntries.count == 1,
                "P8: A.Element constraints must collapse into one AssociatedTypeRequirement, got \(elementEntries.count) entries"
            )
            let aggregate = try #require(elementEntries.first)
            #expect(
                aggregate.requirements.count == 3,
                "P8: aggregated entry should carry all three protocols (Hashable / Decodable / Encodable), got \(aggregate.requirements.count)"
            )
            let names = aggregate.requirements.compactMap { req -> String? in
                if case .protocol(let info) = req { return info.protocolName.name }
                return nil
            }
            // Canonical order is alphabetical-by-protocol within the same LHS.
            #expect(names == names.sorted(), "P8: aggregated requirements must preserve canonical (alphabetical-by-protocol) order")
        }

        // ABI invariant: when two unrelated protocols both declare
        // `associatedtype Element` and a generic parameter conforms to
        // BOTH, `A.Element` references in the emitted requirements
        // canonicalize to a SINGLE declaring protocol (RequirementMachine's
        // reduction order; empirically the lexicographically earlier
        // protocol). The binary never emits two distinct LHS forms
        // (`A.[P:Element]` vs `A.[Q:Element]`).
        //
        // This invariant lets `AssociatedTypeRequirementKey = (parameterName,
        // [stepName])` aggregate by name without losing protocol identity:
        // there is only ever one protocol tag per (parameter, name) in the
        // canonical signature, so two requirements landing on the same path
        // genuinely describe constraints on the same dependent member type.
        @Test func dualProtocolSameNamedAssociatedTypeIsCanonicalized() throws {
            let descriptor = try structDescriptor(named: "DualElementStruct")
            let genericContext = try #require(try descriptor.genericContext(in: machO))

            // Walk every requirement's LHS, collecting the declaring protocol
            // identity for any `A.Element`-rooted dependent member type.
            var protocolIdentities: Set<String> = []
            var elementRequirementCount = 0
            for req in genericContext.requirements {
                let mangled = try req.paramMangledName(in: machO)
                let node = try MetadataReader.demangleType(for: mangled, in: machO)
                guard let path = GenericSpecializer<MachOImage>.extractAssociatedPath(of: node),
                      !path.steps.isEmpty,
                      path.baseParamName == "A",
                      path.steps.first?.name == "Element" else {
                    continue
                }
                elementRequirementCount += 1
                protocolIdentities.insert(
                    path.steps[0].protocolNode.print(using: .interfaceTypeBuilderOnly)
                )
            }

            // Sanity: with `where A.Element: Codable`, the binary emits two
            // requirements (Decodable + Encodable, the two real PWT-bearing
            // protocols Codable expands to). If this number changes, the
            // fixture's invariant has shifted in a way the test author should
            // re-verify.
            #expect(elementRequirementCount == 2)

            // The actual claim: every `A.Element` requirement references the
            // SAME declaring protocol after canonicalization.
            #expect(
                protocolIdentities.count == 1,
                "GenericSignature minimization should pick one canonical protocol for A.Element; saw \(protocolIdentities)"
            )
        }
    }

    // MARK: - Specialize
    //
    // End-to-end pipeline tests that drive `makeRequest` → `specialize` →
    // metadata accessor → field-offset verification. Each test pins a
    // specific fixture shape (unconstrained, single protocol, multi
    // protocol, class constraint, nested associated, etc.) plus the
    // configuration knobs (`metadataRequest`, candidate options, argument
    // case routing).

    @Suite("Specialize")
    struct Specialize: GenericSpecializationTestingEnvironment {
        @Test func manualAccessorMatchesSpecializerWitnessOrder() async throws {
            let descriptor = try inProcessStructDescriptor(named: "TestGenericStruct")

            let genericContext = try #require(try descriptor.genericContext())

            #expect(genericContext.header.numKeyArguments == 9)

            let AMetatype = [Int].self
            let AProtocol = (any Collection).self

            let BMetatype = Double.self
            let BProtocol = (any Equatable).self

            let CMetatype = Data.self
            let CProtocol = (any Hashable).self

            let AMetadata = try Metadata.createInProcess(AMetatype)
            let BMetadata = try Metadata.createInProcess(BMetatype)
            let CMetadata = try Metadata.createInProcess(CMetatype)

            let specializer = GenericSpecializer(indexer: try await indexer)

            let associatedTypeWitnesses = try specializer.resolveAssociatedTypeWitnesses(for: .struct(descriptor), substituting: [
                "A": AMetadata,
                "B": BMetadata,
                "C": CMetadata,
            ])

            let metadataAccessorFunction = try #require(try descriptor.metadataAccessorFunction())
            let metadata = try metadataAccessorFunction(
                request: .completeAndBlocking, metadatas: [
                    AMetadata,
                    BMetadata,
                    CMetadata,
                ], witnessTables: [
                    #require(try RuntimeFunctions.conformsToProtocol(metatype: AMetatype, protocolType: AProtocol)),
                    #require(try RuntimeFunctions.conformsToProtocol(metatype: BMetatype, protocolType: BProtocol)),
                    #require(try RuntimeFunctions.conformsToProtocol(metatype: CMetatype, protocolType: CProtocol)),
                ] + associatedTypeWitnesses
            )
            try #expect(#require(metadata.value.resolve().struct).fieldOffsets() == [0, 8, 16])
        }

        @Test func threeParameter() async throws {
            let descriptor = try structDescriptor(named: "TestGenericStruct")

            let specializer = GenericSpecializer(indexer: try await indexer)
            let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

            let selection: SpecializationSelection = [
                "A": .metatype([Int].self),
                "B": .metatype(Double.self),
                "C": .metatype(Data.self),
            ]

            let result = try specializer.specialize(request, with: selection)

            // Verify resolved arguments
            #expect(result.resolvedArguments.count == 3)
            #expect(result.resolvedArguments[0].parameterName == "A")
            #expect(result.resolvedArguments[1].parameterName == "B")
            #expect(result.resolvedArguments[2].parameterName == "C")

            // A: Collection requires a PWT
            #expect(result.resolvedArguments[0].hasWitnessTables)
            // B: Equatable requires a PWT
            #expect(result.resolvedArguments[1].hasWitnessTables)
            // C: Hashable requires a PWT
            #expect(result.resolvedArguments[2].hasWitnessTables)

            // Verify we can resolve metadata
            let metadata = try result.resolveMetadata()
            let structMetadata = try #require(metadata.struct)
            let fieldOffsets = try structMetadata.fieldOffsets()
            #expect(fieldOffsets == [0, 8, 16])
        }

        @Test func unconstrainedParameter() async throws {
            let (descriptor, genericContext) = try genericStructFixture(named: "TestUnconstrainedStruct")

            // 1 metadata, 0 PWT
            #expect(genericContext.header.numKeyArguments == 1)

            let specializer = GenericSpecializer(indexer: try await indexer)
            let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

            #expect(request.parameters.count == 1)
            #expect(request.parameters[0].name == "A")
            #expect(!request.parameters[0].hasProtocolRequirements)
            #expect(request.associatedTypeRequirements.isEmpty)

            let result = try specializer.specialize(request, with: ["A": .metatype(Int.self)])
            #expect(result.resolvedArguments.count == 1)
            #expect(!result.resolvedArguments[0].hasWitnessTables)

            let metadata = try result.resolveMetadata()
            let structMetadata = try #require(metadata.struct)
            #expect(try structMetadata.fieldOffsets() == [0])
        }

        @Test func singleProtocolParameter() async throws {
            let (descriptor, genericContext) = try genericStructFixture(named: "TestSingleProtocolStruct")

            // 1 metadata + 1 PWT (Hashable)
            #expect(genericContext.header.numKeyArguments == 2)

            let specializer = GenericSpecializer(indexer: try await indexer)
            let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

            #expect(request.parameters.count == 1)
            #expect(request.parameters[0].hasProtocolRequirements)
            #expect(request.parameters[0].protocolRequirements.count == 1)
            #expect(request.associatedTypeRequirements.isEmpty)

            let result = try specializer.specialize(request, with: ["A": .metatype(Int.self)])
            #expect(result.resolvedArguments.count == 1)
            #expect(result.resolvedArguments[0].hasWitnessTables)

            let metadata = try result.resolveMetadata()
            let structMetadata = try #require(metadata.struct)
            #expect(try structMetadata.fieldOffsets() == [0])
        }

        @Test func multiProtocolParameter() async throws {
            let (descriptor, genericContext) = try genericStructFixture(named: "TestMultiProtocolStruct")

            // 1 metadata + 3 PWT (Hashable, Decodable, Encodable)
            #expect(genericContext.header.numKeyArguments == 4)

            let specializer = GenericSpecializer(indexer: try await indexer)
            let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

            #expect(request.parameters.count == 1)
            #expect(request.parameters[0].protocolRequirements.count == 3)
            #expect(request.associatedTypeRequirements.isEmpty)

            let result = try specializer.specialize(request, with: ["A": .metatype(Int.self)])
            #expect(result.resolvedArguments[0].witnessTables.count == 3)

            let metadata = try result.resolveMetadata()
            let structMetadata = try #require(metadata.struct)
            #expect(try structMetadata.fieldOffsets() == [0])
        }

        @Test func classConstraint() async throws {
            let (descriptor, genericContext) = try genericStructFixture(named: "TestClassConstraintStruct")

            // 1 metadata, no PWT (layout requirement does not require WT)
            #expect(genericContext.header.numKeyArguments == 1)

            let specializer = GenericSpecializer(indexer: try await indexer)
            let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

            #expect(request.parameters.count == 1)
            // Layout requirement is recorded but does not need a witness table
            #expect(!request.parameters[0].hasProtocolRequirements)
            let hasLayout = request.parameters[0].requirements.contains { req in
                if case .layout = req { return true }
                return false
            }
            #expect(hasLayout)

            let result = try specializer.specialize(request, with: ["A": .metatype(TestRefClass.self)])
            #expect(!result.resolvedArguments[0].hasWitnessTables)

            let metadata = try result.resolveMetadata()
            let structMetadata = try #require(metadata.struct)
            #expect(try structMetadata.fieldOffsets() == [0])
        }

        @Test func nestedAssociatedType() async throws {
            let descriptor = try structDescriptor(named: "TestNestedAssociatedStruct")

            let specializer = GenericSpecializer(indexer: try await indexer)
            let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

            // A = [[Int]] satisfies: Sequence, Element=[Int] is a Sequence, Element.Element=Int is Hashable
            let result = try specializer.specialize(request, with: ["A": .metatype([[Int]].self)])
            #expect(result.resolvedArguments.count == 1)

            let metadata = try result.resolveMetadata()
            let structMetadata = try #require(metadata.struct)
            // Single field of type [[Int]] occupies one pointer slot
            #expect(try structMetadata.fieldOffsets() == [0])
        }

        @Test func dualAssociated() async throws {
            let (descriptor, genericContext) = try genericStructFixture(named: "TestDualAssociatedStruct")

            // 2 metadata + 4 PWT (A:Sequence, B:Sequence, A.Element:Hashable, B.Element:Hashable)
            #expect(genericContext.header.numKeyArguments == 6)

            let specializer = GenericSpecializer(indexer: try await indexer)
            let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

            #expect(request.parameters.count == 2)
            #expect(request.parameters[0].protocolRequirements.count == 1) // A: Sequence
            #expect(request.parameters[1].protocolRequirements.count == 1) // B: Sequence
            #expect(request.associatedTypeRequirements.count == 2)

            let pathByParam = Dictionary(grouping: request.associatedTypeRequirements, by: \.parameterName)
            #expect(pathByParam["A"]?.first?.path == ["Element"])
            #expect(pathByParam["B"]?.first?.path == ["Element"])

            // A = [Int] (Element = Int), B = [String] (Element = Character).
            let result = try specializer.specialize(request, with: [
                "A": .metatype([Int].self),
                "B": .metatype([String].self),
            ])

            #expect(result.resolvedArguments.count == 2)
            #expect(result.resolvedArguments[0].witnessTables.count == 1)
            #expect(result.resolvedArguments[1].witnessTables.count == 1)

            let metadata = try result.resolveMetadata()
            let structMetadata = try #require(metadata.struct)
            // [Int] occupies 8 bytes, [String] occupies 8 bytes (Array storage pointer)
            #expect(try structMetadata.fieldOffsets() == [0, 8])
        }

        @Test func mixedConstraints() async throws {
            let (descriptor, genericContext) = try genericStructFixture(named: "TestMixedConstraintsStruct")

            // 2 metadata + 3 PWT (A:Collection, B:Hashable, A.Element:Hashable)
            #expect(genericContext.header.numKeyArguments == 5)

            let specializer = GenericSpecializer(indexer: try await indexer)
            let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

            #expect(request.parameters.count == 2)
            #expect(request.parameters[0].name == "A")
            #expect(request.parameters[1].name == "B")
            #expect(request.parameters[0].protocolRequirements.count == 1) // Collection
            #expect(request.parameters[1].protocolRequirements.count == 1) // Hashable
            #expect(request.associatedTypeRequirements.count == 1)
            #expect(request.associatedTypeRequirements[0].parameterName == "A")
            #expect(request.associatedTypeRequirements[0].path == ["Element"])

            let result = try specializer.specialize(request, with: [
                "A": .metatype([Int].self),
                "B": .metatype(String.self),
            ])
            #expect(result.resolvedArguments[0].witnessTables.count == 1) // A: Collection
            #expect(result.resolvedArguments[1].witnessTables.count == 1) // B: Hashable

            let metadata = try result.resolveMetadata()
            let structMetadata = try #require(metadata.struct)
            // [Int] is one pointer (8 bytes), String is 16 bytes
            // a at offset 0, b at offset 8
            #expect(try structMetadata.fieldOffsets() == [0, 8])
        }

        @Test func configurableMetadataRequest() async throws {
            let descriptor = try structDescriptor(named: "TestGenericStruct")

            let specializer = GenericSpecializer(indexer: try await indexer)
            let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

            let selection: SpecializationSelection = [
                "A": .metatype([Int].self),
                "B": .metatype(Double.self),
                "C": .metatype(Data.self),
            ]

            // Default request (existing behaviour)
            let defaultResult = try specializer.specialize(request, with: selection)
            let defaultOffsets = try #require(defaultResult.resolveMetadata().struct).fieldOffsets()

            // Explicit non-blocking complete request
            let nonBlocking = MetadataRequest(state: .complete, isBlocking: false)
            let explicitResult = try specializer.specialize(
                request,
                with: selection,
                metadataRequest: nonBlocking
            )
            let explicitOffsets = try #require(explicitResult.resolveMetadata().struct).fieldOffsets()

            #expect(defaultOffsets == [0, 8, 16])
            #expect(explicitOffsets == defaultOffsets)
        }

        @Test func enumDescriptor() async throws {
            let descriptor = try enumDescriptor(named: "TestGenericEnum")
            let specializer = GenericSpecializer(indexer: try await indexer)
            let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.enum(descriptor))

            #expect(request.parameters.count == 1)
            #expect(request.parameters[0].name == "A")
            #expect(request.parameters[0].hasProtocolRequirements,
                    "A: Hashable must surface as a protocol requirement")
            #expect(request.parameters[0].protocolRequirements.count == 1)

            let result = try specializer.specialize(request, with: ["A": .metatype(Int.self)])
            #expect(result.resolvedArguments.count == 1)
            #expect(result.resolvedArguments[0].hasWitnessTables)

            // The resolved metadata must be an enum metadata kind, not a
            // struct/class one — this is the assertion that proves the
            // wrapper.enum case routed through the pipeline correctly.
            let wrapper = try result.resolveMetadata()
            _ = try #require(wrapper.enum,
                             "expected MetadataWrapper.enum, got \(wrapper)")
        }

        @Test func classDescriptor() async throws {
            let descriptor = try classDescriptor(named: "TestGenericClass")
            let specializer = GenericSpecializer(indexer: try await indexer)
            let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.class(descriptor))

            #expect(request.parameters.count == 1)
            #expect(request.parameters[0].name == "A")
            #expect(request.parameters[0].hasProtocolRequirements,
                    "A: Hashable must surface as a protocol requirement")
            #expect(request.parameters[0].protocolRequirements.count == 1)

            let result = try specializer.specialize(request, with: ["A": .metatype(Int.self)])
            #expect(result.resolvedArguments.count == 1)
            #expect(result.resolvedArguments[0].hasWitnessTables)

            // The resolved metadata must be a class metadata kind.
            let wrapper = try result.resolveMetadata()
            _ = try #require(wrapper.class,
                             "expected MetadataWrapper.class, got \(wrapper)")
        }

        @Test func argumentMetadataPathProducesSameMetadata() async throws {
            let descriptor = try structDescriptor(named: "TestSingleProtocolStruct")
            let specializer = GenericSpecializer(indexer: try await indexer)
            let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

            // Pre-resolved Metadata fed via `.metadata(...)` must produce a
            // metadata pointer indistinguishable from the same selection
            // expressed with `.metatype(...)` — both go through
            // `Metadata.createInProcess(_:)` for the metatype case, so the
            // comparison is identity at the pointer level.
            let intMetadata = try Metadata.createInProcess(Int.self)
            let viaMetadata = try specializer.specialize(request, with: ["A": .metadata(intMetadata)])
            let viaMetatype = try specializer.specialize(request, with: ["A": .metatype(Int.self)])

            let metadataA = try viaMetadata.metadata()
            let metadataB = try viaMetatype.metadata()
            #expect(metadataA == metadataB, "Argument.metadata path must reach the same generic-metadata cache slot as Argument.metatype")

            // And the resolved argument plumbing should record the supplied
            // metadata verbatim — the runtime PWT still has to be looked up,
            // so `hasWitnessTables` reflects the (single, Hashable) protocol.
            #expect(viaMetadata.resolvedArguments[0].metadata == intMetadata)
            #expect(viaMetadata.resolvedArguments[0].hasWitnessTables)
        }

        @Test func argumentCandidatePathSpecializesNonGenericCandidate() async throws {
            let descriptor = try structDescriptor(named: "TestSingleProtocolStruct")
            let specializer = GenericSpecializer(indexer: try await indexer)

            // Use `.excludeGenerics` so the parameter's candidate list only
            // surfaces directly-specializable types. Pin the candidate to
            // `Swift.Int` (matched via `currentName`) so the assertion below
            // can compare against the equivalent `.metatype(Int.self)` path —
            // an order-dependent `first { !$0.isGeneric }` would silently
            // degrade if the indexer's iteration shifted.
            let request = try specializer.makeRequest(
                for: TypeContextDescriptorWrapper.struct(descriptor),
                candidateOptions: .excludeGenerics
            )
            let intCandidate = try #require(
                request.parameters[0].candidates.first {
                    $0.typeName.currentName == "Int" && !$0.isGeneric
                },
                "expected Swift.Int candidate after .excludeGenerics"
            )

            let viaCandidate = try specializer.specialize(request, with: ["A": .candidate(intCandidate)])
            let viaMetatype = try specializer.specialize(request, with: ["A": .metatype(Int.self)])

            // Both paths must hit the same generic-metadata cache slot —
            // candidate resolution should be a thin wrapper over the metadata
            // accessor that `.metatype` already exercises.
            let candidateMetadata = try viaCandidate.metadata()
            let metatypeMetadata = try viaMetatype.metadata()
            #expect(
                candidateMetadata == metatypeMetadata,
                "Argument.candidate path must reach the same metadata pointer as Argument.metatype for the same concrete type"
            )

            #expect(viaCandidate.resolvedArguments.count == 1)
            #expect(viaCandidate.resolvedArguments[0].hasWitnessTables)
            let structMetadata = try #require(viaCandidate.resolveMetadata().struct)
            #expect(try structMetadata.fieldOffsets() == [0])
        }

        @Test func argumentSpecializedPathFeedsNestedSpecialization() async throws {
            let descriptor = try structDescriptor(named: "TestUnconstrainedStruct")
            let specializer = GenericSpecializer(indexer: try await indexer)
            let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

            // Step 1: build TestUnconstrainedStruct<Int>.
            let inner = try specializer.specialize(request, with: ["A": .metatype(Int.self)])
            let innerMetadata = try inner.metadata()

            // Step 2: feed `inner` back in as the outer's GP. Equivalent to
            // TestUnconstrainedStruct<TestUnconstrainedStruct<Int>>.
            let outer = try specializer.specialize(request, with: ["A": .specialized(inner)])
            let outerMetadata = try outer.metadata()

            // The two metadatas must differ — they parameterize the same
            // type with different concrete arguments.
            #expect(innerMetadata != outerMetadata, "outer and inner specializations resolve to distinct generic metadata slots")

            // The resolved argument records the inner's metadata verbatim.
            #expect(outer.resolvedArguments[0].metadata == innerMetadata)

            // Layout check: outer holds a single field of type
            // TestUnconstrainedStruct<Int>, which is itself a single Int
            // (8 bytes), so the outer field is at offset 0 and occupies one
            // pointer-sized slot.
            let structMetadata = try #require(outer.resolveMetadata().struct)
            #expect(try structMetadata.fieldOffsets() == [0])
        }

        @Test func genericCandidateFailFast() async throws {
            let descriptor = try structDescriptor(named: "TestSingleProtocolStruct")

            let specializer = GenericSpecializer(indexer: try await indexer)
            let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

            // Pin to specific stdlib types so a failure points clearly at either
            // the fail-fast logic (test body) or a fixture shift (#require message),
            // rather than the generic "no isGeneric candidate" mode the original
            // first-matching-any-candidate form would silently degrade into.
            // `currentName` strips the module prefix (e.g. "Swift.Int" → "Int").
            let genericCandidate = try #require(
                request.parameters[0].candidates.first { $0.typeName.currentName == "Array" && $0.isGeneric },
                "expected Swift.Array candidate flagged isGeneric"
            )
            let nonGenericCandidate = try #require(
                request.parameters[0].candidates.first { $0.typeName.currentName == "Int" && !$0.isGeneric },
                "expected Swift.Int candidate flagged non-generic"
            )

            // Non-generic candidate still resolves successfully.
            let okResult = try specializer.specialize(
                request,
                with: ["A": .candidate(nonGenericCandidate)]
            )
            _ = try okResult.resolveMetadata()

            // Generic candidate throws the new typed error.
            do {
                _ = try specializer.specialize(
                    request,
                    with: ["A": .candidate(genericCandidate)]
                )
                Issue.record("expected candidateRequiresNestedSpecialization to be thrown")
            } catch let GenericSpecializer<MachOImage>.SpecializerError.candidateRequiresNestedSpecialization(candidate, parameterCount) {
                #expect(candidate.typeName == genericCandidate.typeName)
                #expect(parameterCount >= 1)
            }
        }

        @Test func candidateErrorMessageMentionsSpecialized() async throws {
            let descriptor = try structDescriptor(named: "TestSingleProtocolStruct")

            let specializer = GenericSpecializer(indexer: try await indexer)
            let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

            let genericCandidate = try #require(
                request.parameters[0].candidates.first { $0.typeName.currentName == "Array" && $0.isGeneric },
                "expected Swift.Array candidate flagged isGeneric"
            )

            do {
                _ = try specializer.specialize(
                    request,
                    with: ["A": .candidate(genericCandidate)]
                )
                Issue.record("expected candidateRequiresNestedSpecialization to be thrown")
            } catch let error as GenericSpecializer<MachOImage>.SpecializerError {
                let description = try #require(error.errorDescription)
                #expect(description.contains("Argument.specialized"))
                #expect(description.contains("Array"))
                #expect(description.contains("generic"))
            }
        }
    }

    // MARK: - Nested Generics
    //
    // Tests covering generic contexts at depth ≥ 2. The bugs reproduced here
    // all stem from the same root: Swift's binary stores `parameters` and
    // `requirements` cumulatively at every level of a nested generic context
    // (see `swift/lib/IRGen/GenMeta.cpp:7263` — `canSig->forEachParam` walks
    // every visible GP including inherited ones, and `addGenericRequirements`
    // emits the full canonical signature). Single-level parent nesting works
    // correctly by accident (the math falls out the same when there is
    // exactly one parent generic context); the suite below pins behavior at
    // depth ≥ 2 plus the SwiftDump dumper and the inverted-protocol overlay.

    @Suite("Nested Generics")
    struct NestedGenerics: GenericSpecializationTestingEnvironment {
        @Test func twoLevelBaseline() throws {
            let descriptor = try structDescriptor(named: "NestedGenericTwoLevelInner")
            let genericContext = try #require(try descriptor.genericContext(in: machO))

            // Inner sees both A (inherited from Outer) and B (its own), stored
            // cumulatively.
            #expect(genericContext.header.numParams == 2)
            #expect(genericContext.parameters.count == 2)
            #expect(genericContext.requirements.count == 2)
            #expect(genericContext.parentParameters.count == 1)
            #expect(genericContext.parentParameters.first?.count == 1)
            #expect(genericContext.currentParameters.count == 1)
            #expect(genericContext.currentRequirements.count == 1)

            let specializer = GenericSpecializer(
                machO: machO,
                conformanceProvider: EmptyConformanceProvider()
            )
            let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

            // Two parameters with demangler-canonical names "A" and "A1".
            #expect(request.parameters.count == 2)
            #expect(request.parameters.map(\.name) == ["A", "A1"])
            #expect(request.parameters[0].protocolRequirements.count == 1) // A: Hashable
            #expect(request.parameters[1].protocolRequirements.count == 1) // A1 (= B): Equatable
        }

        @Test func threeLevelCurrentRequirementsKeepsInnerRequirement() throws {
            let descriptor = try structDescriptor(named: "NestedGenericThreeLevelInner")
            let genericContext = try #require(try descriptor.genericContext(in: machO))

            // Sanity — the binary stores parameters and requirements cumulatively.
            #expect(genericContext.parameters.count == 3)     // [A, B, C]
            #expect(genericContext.requirements.count == 3)   // [A:Hashable, B:Equatable, C:Comparable]
            #expect(genericContext.parentParameters.count == 2)
            #expect(genericContext.parentParameters.first?.count == 1) // Outer cumulative = [A]
            #expect(genericContext.parentParameters.last?.count == 2)  // Middle cumulative = [A, B]
            #expect(genericContext.currentParameters.count == 1)       // [C]

            // P0.1 — `currentRequirements` should be `[C: Comparable]` (1 entry).
            // The current impl drops `parentRequirements.flatMap{$0}.count = 1 + 2 = 3`
            // entries from a 3-element cumulative array, leaving an empty list.
            // Correct behaviour mirrors `currentParameters`: drop only
            // `parentRequirements.last?.count` entries.
            #expect(
                genericContext.currentRequirements.count == 1,
                "P0.1: currentRequirements should be [C: Comparable]; flatMap-over-cumulative-parents over-drops at depth ≥ 2."
            )
        }

        @Test func threeLevelMakeRequestProducesCanonicalParameterNames() throws {
            let descriptor = try structDescriptor(named: "NestedGenericThreeLevelInner")

            let specializer = GenericSpecializer(
                machO: machO,
                conformanceProvider: EmptyConformanceProvider()
            )
            let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

            // P0.2 — `makeRequest` should expose exactly 3 type parameters whose
            // canonical names match what the demangler produces for the binary's
            // `qd_X` / `qd0_X` mangling:
            //   "A"   (depth 0, idx 0) — Outer's A   (mangled `x`)
            //   "A1"  (depth 1, idx 0) — Middle's B  (mangled `qd_0`)
            //   "A2"  (depth 2, idx 0) — Inner's C   (mangled `qd0_0`)
            //
            // The current impl iterates `allParameters` directly. Because the
            // middle entry `[A, B]` is *cumulative* rather than newly-introduced,
            // the loop emits an extra `Parameter` and shifts Middle's B to a wrong
            // (depth, index). Concretely, names come out as ["A", "A1", "B1", "A2"].
            let names = request.parameters.map(\.name)
            #expect(
                request.parameters.count == 3,
                "P0.2: expected 3 generic parameters, got \(request.parameters.count) named \(names)."
            )
            #expect(
                names == ["A", "A1", "A2"],
                "P0.2: expected canonical names [A, A1, A2], got \(names)."
            )

            var parametersByName: [String: SpecializationRequest.Parameter] = [:]
            for parameter in request.parameters {
                parametersByName[parameter.name] = parameter
            }

            // Each canonical parameter should carry exactly one direct protocol
            // requirement. Under the bug, "A" sees A:Hashable twice (cumulative
            // parent merge duplicates it), "A1" sees Middle's B (correctly), and
            // "A2" sees nothing — Inner's C: Comparable is silently dropped by
            // the buggy `currentRequirements` and never reaches `mergedRequirements`.
            #expect(parametersByName["A"]?.protocolRequirements.count == 1)
            #expect(parametersByName["A1"]?.protocolRequirements.count == 1)
            #expect(parametersByName["A2"]?.protocolRequirements.count == 1)
        }

        // P2: nested generic specialize() end-to-end coverage.
        //
        // The aa07d74 fix added `makeRequest` assertions for ≥ 3-level
        // nested generics, but never actually called `specialize` on one.
        // This test closes that gap by driving the full pipeline (request →
        // specialize → metadata accessor → field offsets) on the
        // `NestedGenericThreeLevelInner` fixture.
        @Test func threeLevelSpecializeEndToEnd() async throws {
            let descriptor = try structDescriptor(named: "NestedGenericThreeLevelInner")
            let specializer = GenericSpecializer(indexer: try await indexer)
            let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

            let result = try specializer.specialize(request, with: [
                "A": .metatype(Int.self),       // outer's A: Hashable
                "A1": .metatype(Double.self),   // middle's B: Equatable
                "A2": .metatype(String.self),   // inner's C: Comparable
            ])

            #expect(result.resolvedArguments.count == 3)
            #expect(result.resolvedArguments[0].parameterName == "A")
            #expect(result.resolvedArguments[1].parameterName == "A1")
            #expect(result.resolvedArguments[2].parameterName == "A2")
            // Each direct GP requirement contributes exactly one PWT.
            #expect(result.resolvedArguments.allSatisfy { $0.witnessTables.count == 1 })

            let structMetadata = try #require(result.resolveMetadata().struct)
            let fieldOffsets = try structMetadata.fieldOffsets()
            // Layout: a(Int) at 0, b(Double) at 8, c(String) at 16. String
            // occupies 16 bytes but the field offset is the start address.
            #expect(fieldOffsets == [0, 8, 16])
        }

        // P5 reproduction: SwiftDump cumulative-parameter dump.
        //
        // `dumpGenericParameters(isDumpCurrentLevel: false)` was iterating
        // `allParameters`, whose parent levels are stored cumulatively. At
        // depth ≥ 2 that would re-emit each inherited parameter (e.g. for
        // our three-level `NestedGenericThreeLevelInner`, the dump produced
        // `<A, A, B1, A2>` — `A` re-appearing at depth 1, and Middle's `B`
        // misnamed `B1` because the loop counted offsets by depth-cumulative
        // position rather than per-level introduction). Post-fix the dumper
        // walks per-level "newly introduced" slices, emitting exactly
        // `<A, A1, A2>` to match the demangler's canonical naming.
        @Test func threeLevelDumpAllLevelsHasNoDuplicates() async throws {
            let descriptor = try structDescriptor(named: "NestedGenericThreeLevelInner")
            let genericContext = try #require(try descriptor.genericContext(in: machO))

            let dumped = try await genericContext.dumpGenericParameters(
                in: machO,
                isDumpCurrentLevel: false
            ).string

            // Expected demangler-canonical order: A, A1, A2.
            let expectedNames = ["A", "A1", "A2"]
            for name in expectedNames {
                #expect(
                    dumped.contains(name),
                    "P5: dump must include `\(name)` (got `\(dumped)`)"
                )
            }

            // The pre-fix output `<A, A, B1, A2>` contained `B1` (Middle's `B`
            // miscounted), and the bare `A` token was present *twice*. Both
            // are tell-tale signs of cumulative parent re-emission.
            #expect(
                !dumped.contains("B1"),
                "P5: pre-fix cumulative iteration produced a phantom `B1` token (got `\(dumped)`)"
            )

            // Catch the duplicate-`A` regression: a properly de-cumulated dump
            // emits `A` once. The dump output has the form `A, A1, A2` (or
            // similar) — split on `,` and trim, then count tokens equal to
            // bare `A`. The lookbehind regex form would be cleaner but Swift
            // Regex doesn't support lookbehind yet.
            let tokens = dumped
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            let bareACount = tokens.filter { $0 == "A" }.count
            #expect(
                bareACount == 1,
                "P5: bare `A` must appear once; pre-fix cumulative iteration produced \(bareACount) occurrences in tokens \(tokens)"
            )
        }

        @Test func threeLevelInvertedProtocolsPerLevel() throws {
            let descriptor = try structDescriptor(named: "NestedInvertedInner")

            let specializer = GenericSpecializer(
                machO: machO,
                conformanceProvider: EmptyConformanceProvider()
            )
            let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

            // P0.2 prerequisite — without it the parameter list is malformed
            // before we can even probe invertibleProtocols. We still run the
            // P0.3 assertions below via lookup-by-name so that whichever P0 is
            // fixed first surfaces a clean diagnostic.
            let names = request.parameters.map(\.name)
            #expect(request.parameters.count == 3, "P0.2 prerequisite: got names \(names)")
            #expect(names == ["A", "A1", "A2"], "P0.2 prerequisite: got names \(names)")

            var parametersByName: [String: SpecializationRequest.Parameter] = [:]
            for parameter in request.parameters {
                parametersByName[parameter.name] = parameter
            }

            // P0.3 — every parameter is declared `~Copyable`.
            #expect(
                parametersByName["A"]?.invertibleProtocols == .copyable,
                "Outer's A (flat index 0) is `~Copyable`."
            )
            #expect(
                parametersByName["A1"]?.invertibleProtocols == .copyable,
                "Middle's B (canonical A1, flat index 1) is `~Copyable`."
            )
            #expect(
                parametersByName["A2"]?.invertibleProtocols == .copyable,
                "P0.3: Inner's C (canonical A2, flat index 2) is `~Copyable`; collectInvertibleProtocols looks it up at flat index 3 because of the cumulative parent count."
            )
        }

        // M3 closure: three-level nested ~Copyable specialize end-to-end.
        //
        // `threeLevelInvertedProtocolsPerLevel` covers `makeRequest` for
        // the same fixture, asserting that every per-level
        // `invertibleProtocols` set comes out as `.copyable`. This test
        // closes the gap by running the full pipeline (request →
        // specialize → metadata accessor → field offsets) and verifying
        // the conditional `extension … : Copyable where A: Copyable, B:
        // Copyable, C: Copyable` chain is wired up correctly: binding
        // every parameter to a Copyable type lets the metadata accessor
        // produce a non-nil metadata pointer with the same field layout
        // as the non-inverted three-level fixture.
        @Test func threeLevelInvertedSpecializeEndToEnd() async throws {
            let descriptor = try structDescriptor(named: "NestedInvertedInner")
            let specializer = GenericSpecializer(indexer: try await indexer)
            let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

            let result = try specializer.specialize(request, with: [
                "A": .metatype(Int.self),       // outer's A: ~Copyable, bound to Copyable Int
                "A1": .metatype(Double.self),   // middle's B: ~Copyable, bound to Copyable Double
                "A2": .metatype(String.self),   // inner's C: ~Copyable, bound to Copyable String
            ])

            #expect(result.resolvedArguments.count == 3)
            #expect(result.resolvedArguments.map(\.parameterName) == ["A", "A1", "A2"])
            // None of the three GPs has a witness-table-bearing protocol
            // requirement (they only declare `~Copyable`, which is a
            // capability suppression rather than a constraint).
            #expect(result.resolvedArguments.allSatisfy { !$0.hasWitnessTables })

            // Layout matches the non-inverted three-level fixture:
            // a(Int) at 0, b(Double) at 8, c(String) at 16.
            let structMetadata = try #require(result.resolveMetadata().struct)
            #expect(try structMetadata.fieldOffsets() == [0, 8, 16])
        }
    }

    // MARK: - Validation
    //
    // `validate(selection:for:)` is the cheap static-only pass plus the
    // public static constructors of `SpecializationValidation`. The
    // runtime-aware companion `runtimePreflight` lives in its own suite
    // so this group stays focused on argument-shape errors / warnings.

    @Suite("Validation")
    struct Validation: GenericSpecializationTestingEnvironment {
        @Test func reportsMissingArguments() throws {
            let descriptor = try structDescriptor(named: "TestGenericStruct")

            let specializer = GenericSpecializer(
                machO: machO,
                conformanceProvider: EmptyConformanceProvider()
            )
            let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

            // Test missing arguments
            let emptySelection: SpecializationSelection = [:]
            let validation = specializer.validate(selection: emptySelection, for: request)
            #expect(!validation.isValid)
            #expect(validation.errors.count == 3) // Missing A, B, C

            // Test valid selection
            let validSelection: SpecializationSelection = [
                "A": .metatype([Int].self),
                "B": .metatype(Double.self),
                "C": .metatype(Data.self),
            ]
            let validValidation = specializer.validate(selection: validSelection, for: request)
            #expect(validValidation.isValid)
        }

        // M8: validate() reports extra-argument warnings.
        //
        // `validate(selection:for:)` is the cheap static-only pass and
        // must not silently accept arguments for parameters the request
        // does not declare. Missing arguments surface as errors;
        // arguments for unknown parameters surface as `.extraArgument`
        // warnings (the selection is still considered valid —
        // `isValid == true` — because the extra entry is forwarded to
        // no-one and cannot break the accessor call).
        @Test func emitsExtraArgumentWarning() throws {
            let descriptor = try structDescriptor(named: "TestSingleProtocolStruct")
            let specializer = GenericSpecializer(
                machO: machO,
                conformanceProvider: EmptyConformanceProvider()
            )
            let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

            // `TestSingleProtocolStruct<A: Hashable>` declares a single GP "A".
            // Adding "Z" to the selection should surface as a warning, not an
            // error, and leave `isValid` unchanged.
            let selection: SpecializationSelection = [
                "A": .metatype(Int.self),
                "Z": .metatype(String.self),
            ]
            let validation = specializer.validate(selection: selection, for: request)

            #expect(validation.isValid, "extra arguments are warnings, not errors")
            #expect(validation.errors.isEmpty)
            let hasExtra = validation.warnings.contains { warning in
                if case .extraArgument(let name) = warning { return name == "Z" }
                return false
            }
            #expect(hasExtra, "validate must emit .extraArgument warning for a parameter not declared by the request")
        }

        // Bug reproduction #15: validate doesn't distinguish associated-type
        // path from a typo.
        //
        // `validate` flags any selection key not in `request.parameters` as
        // `.extraArgument`. A user who mistakenly tries to set an
        // associated-type path (`"A.Element"`) gets the same generic
        // warning as someone who typo'd `"Z"`. The path is structured (it
        // appears in `associatedTypeRequirements[*].fullPath`) so a more
        // specific warning is possible.
        @Test func givesSpecificWarningForAssociatedTypePath() async throws {
            let descriptor = try structDescriptor(named: "TestNestedAssociatedStruct")
            let specializer = GenericSpecializer(
                machO: machO,
                conformanceProvider: EmptyConformanceProvider()
            )
            let request = try specializer.makeRequest(
                for: TypeContextDescriptorWrapper.struct(descriptor)
            )

            // Sanity: this fixture has A.Element as a real associated-type path.
            #expect(request.associatedTypeRequirements.contains { $0.fullPath == "A.Element" })

            let selection: SpecializationSelection = [
                "A": .metatype([[Int]].self),
                "A.Element": .metatype(Int.self),
            ]
            let validation = specializer.validate(selection: selection, for: request)
            #expect(validation.isValid, "associated-type path is a warning, not an error")

            let hasSpecific = validation.warnings.contains { warning in
                if case .associatedTypePathInSelection(let path) = warning {
                    return path == "A.Element"
                }
                return false
            }
            #expect(
                hasSpecific,
                "validate must distinguish an associated-type path (derived; not user-supplied) from a generic extra argument; got \(validation.warnings)"
            )
        }

        // S3: SpecializationValidation static constructor coverage.
        //
        // `Builder` is the canonical construction path for the
        // specializer's own `validate` / `runtimePreflight` (which need
        // to accumulate a mix of errors and warnings). The three statics
        // below are the ergonomic alternative for *terminal* construction
        // in external callers — code that already knows whether
        // validation passed and doesn't need the builder's append loop.
        // None of the specializer's internal call sites use them; the
        // tests pin the public surface so it doesn't drift.

        @Test func validStaticHasNoErrorsOrWarnings() throws {
            let validation = SpecializationValidation.valid
            #expect(validation.isValid)
            #expect(validation.errors.isEmpty)
            #expect(validation.warnings.isEmpty)
        }

        @Test func failedStaticWithSingleErrorIsInvalid() throws {
            let validation = SpecializationValidation.failed(.missingArgument(parameterName: "A"))
            #expect(!validation.isValid)
            #expect(validation.errors.count == 1)
            #expect(validation.warnings.isEmpty)
            if case .missingArgument(let name) = validation.errors[0] {
                #expect(name == "A")
            } else {
                Issue.record("expected .missingArgument, got \(validation.errors[0])")
            }
        }

        @Test func failedStaticWithMultipleErrorsIsInvalid() throws {
            let validation = SpecializationValidation.failed([
                .missingArgument(parameterName: "A"),
                .missingArgument(parameterName: "B"),
            ])
            #expect(!validation.isValid)
            #expect(validation.errors.count == 2)
            #expect(validation.warnings.isEmpty)
        }
    }

    // MARK: - Runtime Preflight
    //
    // `runtimePreflight(selection:for:)` exercises actual `Metadata` to
    // catch protocol-conformance and class-layout mismatches before the
    // accessor call. Pre-fix `validate` only checked missing/extra
    // arguments; type-shape errors had to wait until `specialize` failed
    // inside `RuntimeFunctions.conformsToProtocol` with the much vaguer
    // `witnessTableNotFound`.

    @Suite("Runtime Preflight")
    struct RuntimePreflight: GenericSpecializationTestingEnvironment {
        @Test func catchesProtocolMismatch() async throws {
            // TestSingleProtocolStruct<A: Hashable>. Picking a Function type for
            // A (Functions don't conform to Hashable) must trip the preflight.
            let descriptor = try structDescriptor(named: "TestSingleProtocolStruct")
            let specializer = GenericSpecializer(indexer: try await indexer)
            let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

            let badSelection: SpecializationSelection = ["A": .metatype((() -> Void).self)]

            let preflight = specializer.runtimePreflight(selection: badSelection, for: request)
            #expect(!preflight.isValid)
            let hasProtocolError = preflight.errors.contains { error in
                if case .protocolRequirementNotSatisfied(_, let proto, _) = error {
                    return proto.contains("Hashable")
                }
                return false
            }
            #expect(hasProtocolError, "P6: preflight must report Hashable mismatch for () -> Void")

            // And the user-facing `specialize` should now throw with the same
            // diagnostic instead of letting it surface as `witnessTableNotFound`.
            do {
                _ = try specializer.specialize(request, with: badSelection)
                Issue.record("P6: specialize must reject the bad selection")
            } catch let error as GenericSpecializer<MachOImage>.SpecializerError {
                if case .specializationFailed(let reason) = error {
                    #expect(reason.contains("Hashable"))
                } else {
                    Issue.record("P6: expected specializationFailed, got \(error)")
                }
            }
        }

        @Test func catchesLayoutMismatch() async throws {
            // TestClassConstraintStruct<A: AnyObject>. Picking a value type for A
            // must trip the layout check.
            let descriptor = try structDescriptor(named: "TestClassConstraintStruct")
            let specializer = GenericSpecializer(indexer: try await indexer)
            let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

            let badSelection: SpecializationSelection = ["A": .metatype(Int.self)]

            let preflight = specializer.runtimePreflight(selection: badSelection, for: request)
            #expect(!preflight.isValid)
            let hasLayoutError = preflight.errors.contains { error in
                if case .layoutRequirementNotSatisfied = error {
                    return true
                }
                return false
            }
            #expect(hasLayoutError, "P6: preflight must report layout mismatch for a value type passed where AnyObject is required")
        }

        // Bug reproduction #4: runtimePreflight silently passes when the
        // indexer is missing a required protocol.
        //
        // When the protocol referenced by a parameter requirement isn't
        // in the indexer, `runtimePreflight` skips the conformance check
        // entirely — it can't construct the protocol descriptor to call
        // `swift_conformsToProtocol`. The fix surfaces this as a typed
        // warning so the user knows to add another sub-indexer instead
        // of getting a misleading `witnessTableNotFound` from `specialize`.
        @Test func surfacesIndexerMissingProtocolWarning() async throws {
            // Build an indexer that has the test image but NOT libswiftCore —
            // so `Hashable` (defined in libswiftCore) won't be found.
            let bareIndexer = SwiftInterfaceIndexer(in: machO)
            try await bareIndexer.prepare()

            // Sanity: `TestSingleProtocolStruct<A: Hashable>` is in `machO`,
            // so makeRequest still works (descriptors are read directly from
            // the binary, not from the indexer).
            let descriptor = try structDescriptor(named: "TestSingleProtocolStruct")
            let specializer = GenericSpecializer(indexer: bareIndexer)
            let request = try specializer.makeRequest(
                for: TypeContextDescriptorWrapper.struct(descriptor)
            )
            #expect(request.parameters.count == 1)
            #expect(request.parameters[0].protocolRequirements.count == 1)

            // Pass a fully valid Hashable conformer. The bug: with libswiftCore
            // missing from the indexer, preflight has no way to look up the
            // protocol descriptor, so it skips the conformance check. That's
            // fine on its own — but the user has no signal that validation is
            // incomplete.
            let preflight = specializer.runtimePreflight(
                selection: ["A": .metatype(Int.self)],
                for: request
            )

            // Expect a warning informing the user that a protocol couldn't be
            // checked because it's not in the indexer.
            let hasMissingProtocolWarning = preflight.warnings.contains { warning in
                if case .protocolNotInIndexer(_, let proto) = warning {
                    return proto.contains("Hashable")
                }
                return false
            }
            #expect(
                hasMissingProtocolWarning,
                "preflight must warn when a parameter's protocol requirement is missing from the indexer; got warnings=\(preflight.warnings), errors=\(preflight.errors)"
            )
        }

        // Bug reproduction #5: runtimePreflight skips .specialized.
        //
        // The pre-fix `runtimePreflight` had `.specialized` in its
        // skip-list, claiming it required running an accessor to obtain
        // the metadata. But a `SpecializationResult` already holds a
        // resolved metadata pointer — there's no accessor to run. The
        // skip silently let through specialized arguments whose result
        // type didn't satisfy the target's protocol requirements.
        // Failure surfaced inside `specialize` as the much vaguer
        // `witnessTableNotFound`.
        @Test func catchesProtocolMismatchOnSpecializedArgument() async throws {
            let unconstrainedDescriptor = try structDescriptor(named: "TestUnconstrainedStruct")
            let specializer = GenericSpecializer(indexer: try await indexer)
            let unconstrainedRequest = try specializer.makeRequest(
                for: TypeContextDescriptorWrapper.struct(unconstrainedDescriptor)
            )

            // `TestUnconstrainedStruct<Int>` does NOT conform to Hashable —
            // the struct itself has no Hashable conformance, regardless of A.
            let unconstrainedResult = try specializer.specialize(
                unconstrainedRequest,
                with: ["A": .metatype(Int.self)]
            )

            // Now feed it where Hashable is required.
            let singleDescriptor = try structDescriptor(named: "TestSingleProtocolStruct")
            let singleRequest = try specializer.makeRequest(
                for: TypeContextDescriptorWrapper.struct(singleDescriptor)
            )

            let badSelection: SpecializationSelection = ["A": .specialized(unconstrainedResult)]

            let preflight = specializer.runtimePreflight(selection: badSelection, for: singleRequest)
            #expect(!preflight.isValid, "preflight must catch Hashable mismatch on .specialized argument")

            let hasProtocolError = preflight.errors.contains { error in
                if case .protocolRequirementNotSatisfied(_, let proto, _) = error {
                    return proto.contains("Hashable")
                }
                return false
            }
            #expect(hasProtocolError, "expected protocolRequirementNotSatisfied for Hashable")

            // And `specialize` should reject with the same diagnostic, not the
            // vaguer `witnessTableNotFound` it surfaced before the fix.
            do {
                _ = try specializer.specialize(singleRequest, with: badSelection)
                Issue.record("specialize must reject the bad .specialized argument")
            } catch let error as GenericSpecializer<MachOImage>.SpecializerError {
                if case .specializationFailed(let reason) = error {
                    #expect(reason.contains("Hashable"))
                } else {
                    Issue.record("expected specializationFailed, got \(error)")
                }
            }
        }

        // MARK: baseClass requirement coverage
        //
        // Pre-fix `runtimePreflight` skipped every `.baseClass` record
        // (the joint `case .protocol, .sameType, .baseClass: continue`
        // arm), so a struct selection or an unrelated-class selection on
        // `<T: TestRequirementBaseClass>` fell through to the metadata
        // accessor — the runtime then rejected the type with a generic
        // failure deep inside `swift_getGenericMetadata`. The tests below
        // pin the new typed behaviour: typed errors for the bad cases,
        // silent success for the good ones, plus a sanity check that the
        // requirement itself is exposed by `makeRequest`.

        @Test func baseClassRequirementSurfacesInRequest() async throws {
            let descriptor = try structDescriptor(named: "TestBaseClassRequirementStruct")
            let specializer = GenericSpecializer(indexer: try await indexer)
            let request = try specializer.makeRequest(
                for: TypeContextDescriptorWrapper.struct(descriptor)
            )

            #expect(request.parameters.count == 1)
            let parameter = request.parameters[0]
            let baseClassRequirement = parameter.requirements.first { requirement in
                if case .baseClass = requirement { return true }
                return false
            }
            try #require(
                baseClassRequirement != nil,
                "makeRequest must surface .baseClass(...) for `<A: TestRequirementBaseClass>`"
            )

            // baseClass is not a key argument — the metadata accessor only
            // takes one slot (A's metadata) regardless of the class chain.
            #expect(request.keyArgumentCount == 1)
        }

        @Test func baseClassPreflightAcceptsDirectSubclass() async throws {
            let descriptor = try structDescriptor(named: "TestBaseClassRequirementStruct")
            let specializer = GenericSpecializer(indexer: try await indexer)
            let request = try specializer.makeRequest(
                for: TypeContextDescriptorWrapper.struct(descriptor)
            )

            let selection: SpecializationSelection = [
                "A": .metatype(GenericSpecializationTests.TestRequirementSubClass.self)
            ]
            let preflight = specializer.runtimePreflight(selection: selection, for: request)
            #expect(preflight.isValid, "direct subclass must pass baseClass preflight, got \(preflight.errors)")
            #expect(preflight.errors.isEmpty)

            // End-to-end specialize must also succeed for the same selection —
            // baseClass adds no key argument, so the accessor call still
            // takes a single metadata.
            let result = try specializer.specialize(request, with: selection)
            _ = try #require(result.resolveMetadata().struct)
        }

        @Test func baseClassPreflightAcceptsBaseClassItself() async throws {
            let descriptor = try structDescriptor(named: "TestBaseClassRequirementStruct")
            let specializer = GenericSpecializer(indexer: try await indexer)
            let request = try specializer.makeRequest(
                for: TypeContextDescriptorWrapper.struct(descriptor)
            )

            // The base class trivially satisfies its own requirement —
            // covers the pointer-equality short circuit before the
            // superclass walk starts.
            let selection: SpecializationSelection = [
                "A": .metatype(GenericSpecializationTests.TestRequirementBaseClass.self)
            ]
            let preflight = specializer.runtimePreflight(selection: selection, for: request)
            #expect(preflight.isValid, "base class must satisfy `T: BaseClass` trivially, got \(preflight.errors)")
        }

        @Test func baseClassPreflightAcceptsTransitiveSubclass() async throws {
            let descriptor = try structDescriptor(named: "TestBaseClassRequirementStruct")
            let specializer = GenericSpecializer(indexer: try await indexer)
            let request = try specializer.makeRequest(
                for: TypeContextDescriptorWrapper.struct(descriptor)
            )

            // Grandchild forces preflight to walk more than one superclass
            // hop before pointer-matching the expected base.
            let selection: SpecializationSelection = [
                "A": .metatype(GenericSpecializationTests.TestRequirementGrandChildClass.self)
            ]
            let preflight = specializer.runtimePreflight(selection: selection, for: request)
            #expect(
                preflight.isValid,
                "transitive subclass must pass baseClass preflight (multi-step superclass chain walk), got \(preflight.errors)"
            )
        }

        @Test func baseClassPreflightRejectsUnrelatedClass() async throws {
            let descriptor = try structDescriptor(named: "TestBaseClassRequirementStruct")
            let specializer = GenericSpecializer(indexer: try await indexer)
            let request = try specializer.makeRequest(
                for: TypeContextDescriptorWrapper.struct(descriptor)
            )

            let selection: SpecializationSelection = [
                "A": .metatype(GenericSpecializationTests.TestRequirementUnrelatedClass.self)
            ]
            let preflight = specializer.runtimePreflight(selection: selection, for: request)
            #expect(!preflight.isValid, "unrelated class must fail baseClass preflight")
            let hasBaseClassError = preflight.errors.contains { error in
                if case .baseClassRequirementNotSatisfied(let param, let baseClass, _) = error {
                    return param == "A" && baseClass.contains("TestRequirementBaseClass")
                }
                return false
            }
            #expect(
                hasBaseClassError,
                "preflight must report .baseClassRequirementNotSatisfied for an unrelated class, got \(preflight.errors)"
            )
        }

        @Test func baseClassRequirementNarrowsCandidates() async throws {
            let descriptor = try structDescriptor(named: "TestBaseClassRequirementStruct")
            let specializer = GenericSpecializer(indexer: try await indexer)
            let request = try specializer.makeRequest(
                for: TypeContextDescriptorWrapper.struct(descriptor)
            )

            let parameter = try #require(request.parameters.first)

            // Sanity: the baseClass requirement is on the parameter and
            // its extracted TypeName resolves through the conformance
            // provider to a non-empty subclass list. This isolates a
            // failure to "subclass map didn't recognise the constraint
            // RHS" before checking the user-facing candidate filtering.
            let baseClassTypeName = try #require(
                GenericSpecializer<MachOImage>.baseClassConstraintTypeName(
                    in: parameter.requirements
                ),
                "expected baseClassConstraintTypeName to project the .baseClass requirement to a class TypeName"
            )
            let subclasses = specializer.conformanceProvider.subclasses(of: baseClassTypeName)
            #expect(
                !subclasses.isEmpty,
                "subclasses(of: \(baseClassTypeName.name)) returned empty — narrowing falls back to 'do not narrow'"
            )

            let candidateNames = Set(parameter.candidates.map { $0.typeName.currentName })

            // Must include the base class itself plus the two known
            // subclasses (the BFS over the parent → child map walks
            // multiple levels).
            #expect(
                candidateNames.contains("TestRequirementBaseClass"),
                "baseClass-narrowed candidate list must include the base class itself, got \(candidateNames)"
            )
            #expect(
                candidateNames.contains("TestRequirementSubClass"),
                "baseClass-narrowed candidate list must include direct subclass, got \(candidateNames)"
            )
            #expect(
                candidateNames.contains("TestRequirementGrandChildClass"),
                "baseClass-narrowed candidate list must include transitive subclass, got \(candidateNames)"
            )

            // Must NOT include unrelated classes / value types — the whole
            // point of narrowing.
            #expect(
                !candidateNames.contains("TestRequirementUnrelatedClass"),
                "baseClass-narrowed candidate list must exclude unrelated classes, got \(candidateNames)"
            )
            #expect(
                !candidateNames.contains("Int"),
                "baseClass-narrowed candidate list must exclude value types, got \(candidateNames)"
            )
        }

        @Test func baseClassPreflightRejectsValueType() async throws {
            let descriptor = try structDescriptor(named: "TestBaseClassRequirementStruct")
            let specializer = GenericSpecializer(indexer: try await indexer)
            let request = try specializer.makeRequest(
                for: TypeContextDescriptorWrapper.struct(descriptor)
            )

            // Int is a struct — selectedKind is not class-like, so the
            // check fails before the superclass walk even starts.
            let selection: SpecializationSelection = ["A": .metatype(Int.self)]
            let preflight = specializer.runtimePreflight(selection: selection, for: request)
            #expect(!preflight.isValid, "value type must fail baseClass preflight")
            let hasBaseClassError = preflight.errors.contains { error in
                if case .baseClassRequirementNotSatisfied(let param, _, _) = error {
                    return param == "A"
                }
                return false
            }
            #expect(
                hasBaseClassError,
                "preflight must report .baseClassRequirementNotSatisfied for a non-class type, got \(preflight.errors)"
            )
        }

        // MARK: sameType requirement coverage
        //
        // Swift 6 rejects every shape of `where LHS == RHS` that would let
        // us pin both `directGenericParamName` (GP-vs-GP) and the
        // concrete-type branch in source: `A == B` is "makes equivalent",
        // `A == Int` is "makes 'A' non-generic", and even nested `B == A`
        // is "makes equivalent" because the inner generic context sees A
        // as cumulative. The single shape that survives the language
        // diagnostic is `A == B.Element`, which is what the fixture above
        // uses. preflight on that shape exercises the
        // associated-type-path branch — the typed downgrade to a
        // `.sameTypeRequirementResolutionSkipped` warning. The other two
        // branches (GP-vs-GP, GP-vs-concrete) live behind the diagnostic
        // wall; they are reachable from binaries built in Swift-5 mode
        // (e.g. SymbolTestsCore's `SameTypeRequirementTest`) but cannot
        // be constructed inline in this test file's Swift-6 source.

        @Test func sameTypeRequirementSurfacesInRequest() async throws {
            let descriptor = try structDescriptor(named: "TestSameTypeViaAssocStruct")
            let specializer = GenericSpecializer(indexer: try await indexer)
            let request = try specializer.makeRequest(
                for: TypeContextDescriptorWrapper.struct(descriptor)
            )

            // The .sameType record attaches to LHS A's requirement list
            // because `collectRequirements` only keeps requirements whose
            // LHS is a direct GP — A is, B.Element is not.
            let parameterA = try #require(
                request.parameters.first { $0.name == "A" },
                "expected parameter A in TestSameTypeViaAssocStruct"
            )
            let hasSameType = parameterA.requirements.contains { requirement in
                if case .sameType = requirement { return true }
                return false
            }
            #expect(
                hasSameType,
                "makeRequest must surface .sameType(...) for `where A == B.Element` on parameter A, got requirements: \(parameterA.requirements)"
            )
        }

        // The unified constraint check resolves both LHS and RHS through
        // `swift_getTypeByMangledNameInContext` (the same routine Swift's
        // own `_checkGenericRequirements` uses,
        // `swift/stdlib/public/runtime/ProtocolConformance.cpp:1846`), so
        // a `where A == B.Element` requirement is verified by substitution
        // — not deferred to a downgrade warning. The two tests below pin
        // the consistent and inconsistent shapes of that verification.

        @Test func sameTypeAssociatedPathPreflightAcceptsConsistentSelection() async throws {
            let descriptor = try structDescriptor(named: "TestSameTypeViaAssocStruct")
            let specializer = GenericSpecializer(indexer: try await indexer)
            let request = try specializer.makeRequest(
                for: TypeContextDescriptorWrapper.struct(descriptor)
            )

            // A == B.Element with B.Element == Int and A == Int → consistent.
            struct CarrierWithIntElement: TestSameTypeAssocCarrier {
                typealias Element = Int
            }
            let selection: SpecializationSelection = [
                "A": .metatype(Int.self),
                "B": .metatype(CarrierWithIntElement.self),
            ]
            let preflight = specializer.runtimePreflight(selection: selection, for: request)

            let hasMismatchError = preflight.errors.contains { error in
                if case .sameTypeRequirementNotSatisfied = error { return true }
                return false
            }
            #expect(
                !hasMismatchError,
                "consistent `A == B.Element` selection must pass preflight, got errors: \(preflight.errors)"
            )

            // The unified path must successfully resolve B.Element via
            // runtime substitution rather than downgrade to a warning —
            // i.e. it actually verified the equality, didn't skip it.
            let hasResolutionSkipped = preflight.warnings.contains { warning in
                if case .sameTypeRequirementResolutionSkipped = warning { return true }
                return false
            }
            #expect(
                !hasResolutionSkipped,
                "preflight must resolve `B.Element` via runtime substitution, not downgrade to a warning"
            )
        }

        @Test func sameTypeAssociatedPathPreflightRejectsInconsistentSelection() async throws {
            let descriptor = try structDescriptor(named: "TestSameTypeViaAssocStruct")
            let specializer = GenericSpecializer(indexer: try await indexer)
            let request = try specializer.makeRequest(
                for: TypeContextDescriptorWrapper.struct(descriptor)
            )

            // A == B.Element required, but A=String / B.Element=Int — the
            // unified pass must catch this even though the LHS is a direct
            // GP and RHS is an associated-type access path (the case
            // pre-refactor preflight downgraded to a warning).
            struct CarrierWithIntElement: TestSameTypeAssocCarrier {
                typealias Element = Int
            }
            let selection: SpecializationSelection = [
                "A": .metatype(String.self),
                "B": .metatype(CarrierWithIntElement.self),
            ]
            let preflight = specializer.runtimePreflight(selection: selection, for: request)

            #expect(!preflight.isValid, "inconsistent `A == B.Element` selection must fail preflight")
            let hasMismatchError = preflight.errors.contains { error in
                if case .sameTypeRequirementNotSatisfied = error { return true }
                return false
            }
            #expect(
                hasMismatchError,
                "preflight must report .sameTypeRequirementNotSatisfied for A=String / B.Element=Int, got errors: \(preflight.errors)"
            )
        }
    }

    // MARK: - Invariants
    //
    // Tests pinning the binary-encoded ordering invariants that the
    // specializer relies on. PWT slot order must match
    // `compareDependentTypes` (`swift/lib/AST/GenericSignature.cpp:846`):
    // GP-rooted requirements rank before nested-type-rooted ones, and
    // within each block by parameter (depth, index). Diverging from that
    // order routes the metadata accessor to a different cache slot or
    // mis-feeds individual PWT slots.

    @Suite("Invariants")
    struct Invariants: GenericSpecializationTestingEnvironment {
        // Associated-type PWT order with same-leaf interleaving.
        //
        // Regression coverage for the previously-buggy
        // `GenericSpecializer.resolveAssociatedTypeWitnesses`. An earlier
        // implementation returned `OrderedDictionary<Metadata, [PWT]>`
        // keyed by the *leaf* metadata of each requirement chain, and
        // `specialize` flattened it via `dict.values.flatMap { $0 }`. Per
        // `OrderedDictionary` semantics, updating an existing key keeps
        // it in its original position — so when two distinct chains
        // resolved to the *same* leaf metadata but a third chain *in
        // between* resolved to a different one, the flattened PWT list
        // broke the binary's `compareDependentTypes` order.
        //
        // For the fixture below specialized with A=[Int], B=String, C=[Int]:
        //   A.Element = Int       (M_Int)
        //   B.Element = Character (M_Char)
        //   C.Element = Int       (M_Int — same as A.Element)
        //
        // Binary canonical order is parameter-declaration order:
        //   [Int_Hashable, Char_Hashable, Int_Hashable]
        //
        // Pre-fix flatten produced the buggy
        //   [Int_Hashable, Int_Hashable, Char_Hashable]
        // — the slot the runtime reserved for B.Element's Hashable PWT
        // got Int's Hashable PWT instead, mis-routing any associated-
        // type Hashable lookup performed on the specialized type.
        // `fieldOffsets()` was invariant under the re-ordering (PWT slot
        // widths are uniform), so no other test caught it. Post-fix the
        // function returns a flat `[ProtocolWitnessTable]` collected in
        // `mergedRequirements` iteration order — which is itself the
        // binary's canonical order.
        @Test func associatedWitnessOrderingPreservesBinaryOrder() async throws {
            // `resolveAssociatedTypeWitnesses` calls `genericContext()` (the
            // in-process overload), so the descriptor must be an in-process
            // pointer wrapper.
            let descriptor = try inProcessStructDescriptor(named: "TestTriAssociatedSameLeafStruct")

            let specializer = GenericSpecializer(indexer: try await indexer)

            // Bind A and C to the same array type so their A.Element /
            // C.Element chains both resolve to Int's metadata; B is bound to
            // String so its B.Element chain resolves to Character — distinct
            // from Int. This is the exact configuration that exposes the
            // pre-fix leaf-grouping bug.
            let aMetadata = try Metadata.createInProcess([Int].self)
            let bMetadata = try Metadata.createInProcess(String.self)
            let cMetadata = try Metadata.createInProcess([Int].self)

            let resolvedWitnesses = try specializer.resolveAssociatedTypeWitnesses(
                for: TypeContextDescriptorWrapper.struct(descriptor),
                substituting: [
                    "A": aMetadata,
                    "B": bMetadata,
                    "C": cMetadata,
                ]
            )

            let intHashablePWT = try #require(
                try RuntimeFunctions.conformsToProtocol(
                    metatype: Int.self,
                    protocolType: (any Hashable).self
                ),
                "Int must conform to Hashable in the test process"
            )
            let charHashablePWT = try #require(
                try RuntimeFunctions.conformsToProtocol(
                    metatype: Character.self,
                    protocolType: (any Hashable).self
                ),
                "Character must conform to Hashable in the test process"
            )

            // Binary requirement order — A.Element, B.Element, C.Element —
            // per `compareDependentTypes`. All three share depth 0 and rank
            // by parameter index, so the canonical order is exactly
            // declaration order.
            let expectedBinaryOrder: [ProtocolWitnessTable] = [
                intHashablePWT,   // A.Element = Int
                charHashablePWT,  // B.Element = Character
                intHashablePWT,   // C.Element = Int
            ]
            #expect(
                resolvedWitnesses == expectedBinaryOrder,
                "resolveAssociatedTypeWitnesses must emit PWTs in canonical (binary) requirement order. Pre-fix leaf-keyed `OrderedDictionary` flatten produced [Int_Hashable, Int_Hashable, Char_Hashable] for this fixture, mis-feeding slot 2 (binary reserves it for B.Element: Hashable) with Int's PWT."
            )
        }

        @Test func specializeMatchesManualBinaryOrder() async throws {
            // End-to-end companion to `associatedWitnessOrderingPreservesBinaryOrder`:
            // build the metadata via the API and via a hand-rolled call to
            // the metadata accessor with witness tables in canonical
            // (binary) order, and verify the runtime returns the same
            // metadata pointer for both. Swift's generic-metadata cache keys
            // on the entire `(generic args, witness tables)` tuple — feeding
            // the accessor witness tables in a non-canonical order routes
            // the call to a different cache slot (or, worse, populates a
            // freshly allocated metadata whose internal associated-type
            // witness routing is wrong).
            //
            // Note: `makeRequest` resolves the descriptor via the *file-context*
            // `genericContext(in: machO)` overload, while
            // `metadataAccessorFunction()` (no-arg) reads in-process — so we
            // need a file-form descriptor for `makeRequest` and an
            // in-process pointer wrapper for the manual accessor call.
            let descriptor = try structDescriptor(named: "TestTriAssociatedSameLeafStruct")
            let inProcessDescriptor = descriptor.asPointerWrapper(in: machO)
            let specializer = GenericSpecializer(indexer: try await indexer)
            let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))

            let aArrayInt = [Int].self
            let bString = String.self
            let cArrayInt = [Int].self

            let aMetadata = try Metadata.createInProcess(aArrayInt)
            let bMetadata = try Metadata.createInProcess(bString)
            let cMetadata = try Metadata.createInProcess(cArrayInt)

            let aSequencePWT = try #require(
                try RuntimeFunctions.conformsToProtocol(metatype: aArrayInt, protocolType: (any Sequence).self),
                "[Int] must conform to Sequence"
            )
            let bSequencePWT = try #require(
                try RuntimeFunctions.conformsToProtocol(metatype: bString, protocolType: (any Sequence).self),
                "String must conform to Sequence"
            )
            let cSequencePWT = try #require(
                try RuntimeFunctions.conformsToProtocol(metatype: cArrayInt, protocolType: (any Sequence).self),
                "[Int] must conform to Sequence"
            )
            let intHashablePWT = try #require(
                try RuntimeFunctions.conformsToProtocol(metatype: Int.self, protocolType: (any Hashable).self),
                "Int must conform to Hashable"
            )
            let charHashablePWT = try #require(
                try RuntimeFunctions.conformsToProtocol(metatype: Character.self, protocolType: (any Hashable).self),
                "Character must conform to Hashable"
            )

            // Manual call: witness tables in canonical (binary) order.
            // Direct-GP block: A:Sequence, B:Sequence, C:Sequence.
            // Associated block: A.Element:Hashable, B.Element:Hashable,
            // C.Element:Hashable.
            let accessor = try #require(
                try inProcessDescriptor.metadataAccessorFunction(),
                "TestTriAssociatedSameLeafStruct must have a metadata accessor function"
            )
            let manualResponse = try accessor(
                request: .completeAndBlocking,
                metadatas: [aMetadata, bMetadata, cMetadata],
                witnessTables: [
                    aSequencePWT,
                    bSequencePWT,
                    cSequencePWT,
                    intHashablePWT,   // A.Element
                    charHashablePWT,  // B.Element
                    intHashablePWT,   // C.Element
                ]
            )
            let manualMetadata = try manualResponse.value.resolve().metadata

            // API call.
            let apiResult = try specializer.specialize(request, with: [
                "A": .metatype(aArrayInt),
                "B": .metatype(bString),
                "C": .metatype(cArrayInt),
            ])
            let apiMetadata = try apiResult.metadata()

            // The runtime's generic-metadata cache returns the same
            // metadata pointer iff the `(args, PWTs)` tuple matches.
            // Pre-fix `specialize` flattens its leaf-keyed dict to
            //   [aSequence, bSequence, cSequence, Int_H, Int_H, Char_H]
            // instead of the canonical
            //   [aSequence, bSequence, cSequence, Int_H, Char_H, Int_H]
            // — different cache key, divergent metadata pointer.
            #expect(
                manualMetadata == apiMetadata,
                "specialize() must produce the same metadata pointer the runtime returns when invoked manually with witness tables in canonical (binary) order; divergence indicates an incorrect PWT order in the API path."
            )
        }
    }

    // MARK: - Error Paths
    //
    // Typed-error coverage. `SpecializerError` /
    // `AssociatedTypeResolutionError` carry the diagnostic messages that
    // surface to callers when a specialization fails for reasons not
    // catchable by the static `validate` pass — corrupt descriptors,
    // missing infrastructure, key-argument count mismatches, etc.

    @Suite("Error Paths")
    struct ErrorPaths: GenericSpecializationTestingEnvironment {
        // Bug reproduction #1: specialize doesn't self-check
        // keyArgumentCount.
        //
        // The accessor takes `numKeyArguments` slots: `parameters.count`
        // metadatas + `protocol-PWTs + assoc-PWTs`. If our parameter
        // discovery or PWT collection ever miscounts (regression in
        // `buildParameters` / `collectRequirements` /
        // `buildAssociatedTypeRequirements`), we'd send the wrong number
        // of args to the accessor and fail opaquely deep in the runtime.
        // Adding a count assertion converts that silent failure into a
        // typed `specializationFailed` with a clear message.
        @Test func specializeRejectsMismatchedKeyArgumentCount() async throws {
            let descriptor = try structDescriptor(named: "TestSingleProtocolStruct")
            let specializer = GenericSpecializer(indexer: try await indexer)
            let realRequest = try specializer.makeRequest(
                for: TypeContextDescriptorWrapper.struct(descriptor)
            )

            // Tampered request: claims a different keyArgumentCount than
            // parameters/requirements actually total.
            let tamperedRequest = SpecializationRequest(
                typeDescriptor: realRequest.typeDescriptor,
                parameters: realRequest.parameters,
                associatedTypeRequirements: realRequest.associatedTypeRequirements,
                keyArgumentCount: realRequest.keyArgumentCount + 5
            )

            do {
                _ = try specializer.specialize(tamperedRequest, with: ["A": .metatype(Int.self)])
                Issue.record("specialize must reject mismatched keyArgumentCount before invoking the accessor")
            } catch let error as GenericSpecializer<MachOImage>.SpecializerError {
                if case .specializationFailed(let reason) = error {
                    #expect(
                        reason.lowercased().contains("key argument") || reason.lowercased().contains("count"),
                        "error message should mention key argument count, got: \(reason)"
                    )
                } else {
                    Issue.record("expected specializationFailed, got \(error)")
                }
            }
        }

        // G1: AssociatedTypeResolutionError coverage — missingIndexer.
        //
        // `AssociatedTypeResolutionError` carries the diagnostic
        // information for every typed failure path through
        // `resolveAssociatedTypeWitnesses`. Tests in this suite pin the
        // most common construction triggers — a specializer built without
        // an indexer, and a `substituting:` map that omits one of the
        // parameters that requirement chains root into. The remaining
        // cases (`missingAssociatedTypeIndex`,
        // `conformingTypeDoesNotConformToProtocol`, etc.) are reachable
        // only by deliberately corrupting fixture state and are deferred.
        @Test func resolveAssociatedTypeWitnessesThrowsWhenIndexerIsMissing() throws {
            let descriptor = try inProcessStructDescriptor(named: "TestNestedAssociatedStruct")
            let specializerWithoutIndexer = GenericSpecializer(
                machO: machO,
                conformanceProvider: EmptyConformanceProvider()
            )

            do {
                _ = try specializerWithoutIndexer.resolveAssociatedTypeWitnesses(
                    for: TypeContextDescriptorWrapper.struct(descriptor),
                    substituting: ["A": try Metadata.createInProcess([[Int]].self)]
                )
                Issue.record("expected missingIndexer to throw")
            } catch let error as GenericSpecializer<MachOImage>.AssociatedTypeResolutionError {
                if case .missingIndexer = error {
                    return
                }
                Issue.record("expected missingIndexer, got \(error)")
            }
        }

        @Test func resolveAssociatedTypeWitnessesThrowsWhenSubstitutionMissesBaseParameter() async throws {
            let descriptor = try inProcessStructDescriptor(named: "TestNestedAssociatedStruct")
            let specializer = GenericSpecializer(indexer: try await indexer)

            do {
                _ = try specializer.resolveAssociatedTypeWitnesses(
                    for: TypeContextDescriptorWrapper.struct(descriptor),
                    substituting: [:]
                )
                Issue.record("expected missingConformingTypeMetadata to throw")
            } catch let error as GenericSpecializer<MachOImage>.AssociatedTypeResolutionError {
                if case .missingConformingTypeMetadata(let genericParam, _) = error {
                    #expect(genericParam == "A")
                    return
                }
                Issue.record("expected missingConformingTypeMetadata, got \(error)")
            }
        }

        // G2: candidateResolutionFailed coverage.
        //
        // `resolveCandidate` checks `guard let indexer` first; without
        // an indexer the call must surface as a typed
        // `candidateResolutionFailed` with the offending candidate in
        // the payload. Exercising this path requires a request built
        // with an indexer-backed specializer (so `findCandidates` can
        // populate the candidate list) and a *separate* specializer
        // without `indexer` for the `specialize` call.
        @Test func candidatePathThrowsCandidateResolutionFailedWhenIndexerIsMissing() async throws {
            let descriptor = try structDescriptor(named: "TestSingleProtocolStruct")
            let indexerSpecializer = GenericSpecializer(indexer: try await indexer)
            let request = try indexerSpecializer.makeRequest(
                for: TypeContextDescriptorWrapper.struct(descriptor),
                candidateOptions: .excludeGenerics
            )
            let intCandidate = try #require(
                request.parameters[0].candidates.first {
                    $0.typeName.currentName == "Int" && !$0.isGeneric
                },
                "expected Swift.Int candidate after .excludeGenerics"
            )

            // The two-arg initializer leaves `indexer` nil, so the
            // conformance-provider plumbing for `findCandidates` still works
            // (we reuse the indexer's provider) but `resolveCandidate` finds
            // no indexer and bails out cleanly.
            let indexerlessSpecializer = GenericSpecializer(
                machO: machO,
                conformanceProvider: IndexerConformanceProvider(indexer: try await indexer)
            )

            do {
                _ = try indexerlessSpecializer.specialize(
                    request,
                    with: ["A": .candidate(intCandidate)]
                )
                Issue.record("expected candidateResolutionFailed when indexer is nil")
            } catch let error as GenericSpecializer<MachOImage>.SpecializerError {
                if case .candidateResolutionFailed(let candidate, let reason) = error {
                    #expect(candidate.typeName == intCandidate.typeName)
                    #expect(reason.lowercased().contains("indexer"))
                    return
                }
                Issue.record("expected candidateResolutionFailed, got \(error)")
            }
        }
    }

    // MARK: - Models
    //
    // Coverage of the data types around `GenericSpecializer` —
    // `SpecializationSelection` (Builder + dictionary literal),
    // `SpecializationResult` convenience accessors, the
    // `extractAssociatedPath` parser helper, and the
    // `CompositeConformanceProvider` adapter. These tests exercise the
    // public API surface independent of any single specialization run.

    @Suite("Models")
    struct Models: GenericSpecializationTestingEnvironment {
        @Test func selectionBuilderBasic() throws {
            let selection = SpecializationSelection.builder()
                .set("A", to: [Int].self)
                .set("B", to: String.self)
                .build()

            #expect(selection.hasArgument(for: "A"))
            #expect(selection.hasArgument(for: "B"))
            #expect(!selection.hasArgument(for: "C"))
            #expect(selection.selectedParameterNames.count == 2)
        }

        // G4: SpecializationSelection.Builder overload coverage.
        //
        // `selectionBuilderBasic` covers `set(_:to:Any.Type)`. The
        // overloads for `Metadata` / `Candidate` / `SpecializationResult`
        // and `remove(_:)` are public API surfaces with no other callers,
        // so each gets a minimal round-trip pin: build → subscript →
        // case-extract → assert.

        @Test func selectionBuilderMetadataOverloadStoresMetadataArgument() throws {
            let intMetadata = try Metadata.createInProcess(Int.self)
            let selection = SpecializationSelection.builder()
                .set("A", to: intMetadata)
                .build()
            let argument = try #require(selection["A"])
            guard case .metadata(let stored) = argument else {
                Issue.record("expected .metadata case, got \(argument)")
                return
            }
            #expect(stored == intMetadata)
        }

        @Test func selectionBuilderCandidateOverloadStoresCandidateArgument() async throws {
            let descriptor = try structDescriptor(named: "TestSingleProtocolStruct")
            let specializer = GenericSpecializer(indexer: try await indexer)
            let request = try specializer.makeRequest(
                for: TypeContextDescriptorWrapper.struct(descriptor),
                candidateOptions: .excludeGenerics
            )
            let candidate = try #require(
                request.parameters[0].candidates.first {
                    $0.typeName.currentName == "Int" && !$0.isGeneric
                },
                "expected Swift.Int candidate after .excludeGenerics"
            )

            let selection = SpecializationSelection.builder()
                .set("A", to: candidate)
                .build()
            let argument = try #require(selection["A"])
            guard case .candidate(let stored) = argument else {
                Issue.record("expected .candidate case, got \(argument)")
                return
            }
            #expect(stored.typeName == candidate.typeName)
            #expect(stored.isGeneric == candidate.isGeneric)
        }

        @Test func selectionBuilderSpecializedOverloadStoresSpecializedArgument() async throws {
            let descriptor = try structDescriptor(named: "TestUnconstrainedStruct")
            let specializer = GenericSpecializer(indexer: try await indexer)
            let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))
            let inner = try specializer.specialize(request, with: ["A": .metatype(Int.self)])

            let selection = SpecializationSelection.builder()
                .set("A", to: inner)
                .build()
            let argument = try #require(selection["A"])
            guard case .specialized(let stored) = argument else {
                Issue.record("expected .specialized case, got \(argument)")
                return
            }
            let storedMetadata = try stored.metadata()
            let innerMetadata = try inner.metadata()
            #expect(storedMetadata == innerMetadata)
        }

        @Test func selectionBuilderRemoveDropsArgument() throws {
            let intMetadata = try Metadata.createInProcess(Int.self)
            let builder = SpecializationSelection.builder()
                .set("A", to: intMetadata)
                .set("B", to: String.self)
            builder.remove("A")
            let selection = builder.build()
            #expect(!selection.hasArgument(for: "A"))
            #expect(selection.hasArgument(for: "B"))
        }

        // G5: SpecializationResult convenience accessor coverage.
        //
        // `argument(for:)` and `valueWitnessTable()` are public
        // conveniences that route through `resolveMetadata()`. The smoke
        // tests below pin the lookup-by-name path and the in-process VWT
        // overload against a fixture whose layout we already know. There
        // is intentionally no file-context VWT overload — see
        // `SpecializationResult.swift` for the rationale.

        @Test func resultArgumentForLooksUpByParameterName() async throws {
            let descriptor = try structDescriptor(named: "TestGenericStruct")
            let specializer = GenericSpecializer(indexer: try await indexer)
            let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))
            let result = try specializer.specialize(request, with: [
                "A": .metatype([Int].self),
                "B": .metatype(Double.self),
                "C": .metatype(Data.self),
            ])

            let argA = try #require(result.argument(for: "A"))
            #expect(argA.parameterName == "A")
            #expect(argA.metadata == result.resolvedArguments[0].metadata)

            #expect(
                result.argument(for: "Z") == nil,
                "argument(for:) should return nil for an unknown parameter name"
            )
        }

        @Test func resultValueWitnessTableResolvesSizeForSimpleStruct() async throws {
            let descriptor = try structDescriptor(named: "TestUnconstrainedStruct")
            let specializer = GenericSpecializer(indexer: try await indexer)
            let request = try specializer.makeRequest(for: TypeContextDescriptorWrapper.struct(descriptor))
            let result = try specializer.specialize(request, with: ["A": .metatype(Int.self)])

            // TestUnconstrainedStruct<Int> has a single Int field — 8 bytes
            // on any 64-bit Apple platform.
            let vwt = try result.valueWitnessTable()
            #expect(vwt.layout.size == 8)
        }

        // Bug reproduction #3: extractAssociatedPath returns nil for a
        // bare ProtocolSymbolicReference.
        //
        // The Swift demangler in `popAssocTypeName`
        // (`swift/lib/Demangling/Demangler.cpp:2832-2845`) accepts three
        // protocol-shaped nodes for the second child of
        // `DependentAssociatedTypeRef`:
        //   - `.type` (when the symbolic-ref resolver succeeded and
        //     returned a wrapped tree)
        //   - `.protocolSymbolicReference` (resolver returned nil)
        //   - `.objectiveCProtocolSymbolicReference` (resolver returned nil)
        //
        // The pre-fix `extractAssociatedPath` only accepted `.type`. The
        // other two — which arise when MetadataReader's resolver fails —
        // fell through to a `nil` return, which then became a silent
        // `continue` in `buildAssociatedTypeRequirements` or a typed
        // `unknownParamNodeStructure` error in
        // `resolveAssociatedTypeWitnesses`.
        @Test func extractAssociatedPathHandlesBareProtocolSymbolicReference() throws {
            // Build the LHS for a hypothetical `A.Element: …` requirement
            // whose protocol child failed to resolve symbolically. The tree
            // mirrors what the demangler emits when the resolver returns nil:
            //   .type
            //     .dependentMemberType
            //       .type → .dependentGenericParamType (depth=0, index=0)
            //       .dependentAssociatedTypeRef
            //         .identifier "Element"
            //         .protocolSymbolicReference 42      ← bare, NOT in .type
            let bareSymbolicRef = Node.create(kind: .protocolSymbolicReference, index: 42)
            let nameNode = Node.create(kind: .identifier, text: "Element")
            let assocRef = Node.create(kind: .dependentAssociatedTypeRef, children: [
                nameNode,
                bareSymbolicRef,
            ])
            let baseDepth = Node.create(kind: .index, index: 0)
            let baseIndex = Node.create(kind: .index, index: 0)
            let baseGP = Node.create(kind: .dependentGenericParamType, children: [baseDepth, baseIndex])
            let dependent = Node.create(kind: .dependentMemberType, children: [
                Node.create(kind: .type, children: [baseGP]),
                assocRef,
            ])
            let outer = Node.create(kind: .type, children: [dependent])

            let path = GenericSpecializer<MachOImage>.extractAssociatedPath(of: outer)

            // Goal of the fix: even when the protocol child is a bare
            // symbolic ref, the path structure is still recoverable
            // (baseParamName + step name). Downstream resolution may still
            // fail at the protocol-descriptor lookup, but the parsing layer
            // shouldn't punt to nil.
            let recovered = try #require(
                path,
                "extractAssociatedPath must recover the parameter/name pair even when the protocol child is a bare ProtocolSymbolicReference; demangler legitimately emits this when its resolver returns nil"
            )
            #expect(recovered.baseParamName == "A")
            #expect(recovered.steps.map(\.name) == ["Element"])
        }

        // S5: extractAssociatedPath ObjC symbolic-ref coverage.
        //
        // `extractAssociatedPath` accepts three protocol-shaped node
        // kinds for the second child of `DependentAssociatedTypeRef`:
        // `.type`, `.protocolSymbolicReference`, and
        // `.objectiveCProtocolSymbolicReference`. The Swift case is
        // pinned by the test above; this test covers the symmetric ObjC
        // fallback path.
        @Test func extractAssociatedPathHandlesBareObjCProtocolSymbolicReference() throws {
            let bareObjCSymbolicRef = Node.create(kind: .objectiveCProtocolSymbolicReference, index: 99)
            let nameNode = Node.create(kind: .identifier, text: "Element")
            let assocRef = Node.create(kind: .dependentAssociatedTypeRef, children: [
                nameNode,
                bareObjCSymbolicRef,
            ])
            let baseDepth = Node.create(kind: .index, index: 0)
            let baseIndex = Node.create(kind: .index, index: 0)
            let baseGP = Node.create(kind: .dependentGenericParamType, children: [baseDepth, baseIndex])
            let dependent = Node.create(kind: .dependentMemberType, children: [
                Node.create(kind: .type, children: [baseGP]),
                assocRef,
            ])
            let outer = Node.create(kind: .type, children: [dependent])

            let path = GenericSpecializer<MachOImage>.extractAssociatedPath(of: outer)
            let recovered = try #require(
                path,
                "extractAssociatedPath must accept .objectiveCProtocolSymbolicReference identically to .protocolSymbolicReference"
            )
            #expect(recovered.baseParamName == "A")
            #expect(recovered.steps.map(\.name) == ["Element"])
        }

        // S1: CompositeConformanceProvider coverage.
        //
        // Two pin tests for the dedupe / first-hit semantics declared in
        // `CompositeConformanceProvider`'s implementation:
        //   - Composing `[Empty, Real]` must behave identically to
        //     `Real` alone (empty contributes nothing).
        //   - Composing `[Real, Real]` must dedupe across providers —
        //     the `seen.insert(...)` guards in `types(conformingTo:)`,
        //     `conformances(of:)`, and `allTypeNames` exist precisely
        //     so callers can stack providers without producing duplicate
        //     entries when they overlap.

        @Test func compositeConformanceProviderEmptyPlusRealActsLikeReal() async throws {
            let real = IndexerConformanceProvider(indexer: try await indexer)
            let composite = CompositeConformanceProvider(providers: [
                EmptyConformanceProvider(),
                real,
            ])

            #expect(composite.allTypeNames.count == real.allTypeNames.count)

            let sampleType = try #require(real.allTypeNames.first)
            // First-hit semantics: empty has no entry, real does, so the
            // composite must return real's value for `typeDefinition` and
            // `imagePath`.
            #expect(composite.typeDefinition(for: sampleType) != nil)
            #expect(composite.imagePath(for: sampleType) == real.imagePath(for: sampleType))
        }

        @Test func compositeConformanceProviderDedupsAcrossDuplicateProviders() async throws {
            let single = IndexerConformanceProvider(indexer: try await indexer)
            let composite = CompositeConformanceProvider(providers: [single, single])

            // Same provider twice must collapse to one provider's worth of
            // results — verifies the `seen` set on every list-returning
            // method, not just `allTypeNames`.
            #expect(composite.allTypeNames.count == single.allTypeNames.count)

            let sampleType = try #require(
                single.allTypeNames.first { !single.conformances(of: $0).isEmpty },
                "expected at least one type with at least one conformance in the indexer"
            )
            let sampleProto = try #require(
                single.conformances(of: sampleType).first,
                "expected at least one conformance for the sample type"
            )

            #expect(composite.types(conformingTo: sampleProto).count
                    == single.types(conformingTo: sampleProto).count,
                    "types(conformingTo:) must dedupe across providers")
            #expect(composite.conformances(of: sampleType).count
                    == single.conformances(of: sampleType).count,
                    "conformances(of:) must dedupe across providers")
            #expect(composite.doesType(sampleType, conformTo: sampleProto),
                    "doesType returns true if any provider says yes")
        }
    }
}

// MARK: - Conditional Copyable / Escapable extensions

extension GenericSpecializationTests.TestInvertedCopyableStruct: Copyable where A: Copyable {}

extension GenericSpecializationTests.NestedInvertedOuter: Copyable where A: Copyable {}
extension GenericSpecializationTests.NestedInvertedOuter.NestedInvertedMiddle: Copyable where A: Copyable, B: Copyable {}
extension GenericSpecializationTests.NestedInvertedOuter.NestedInvertedMiddle.NestedInvertedInner: Copyable where A: Copyable, B: Copyable, C: Copyable {}

extension GenericSpecializationTests.TestInvertedEscapableEnum: Escapable where A: Escapable {}

// Note: `TestInvertedDualEnum` deliberately ships *without* conditional
// `Copyable` / `Escapable` extensions. The fixture's purpose is to
// expose the *regular* invertible-protocol record on its single GP
// (the binary's `<A: ~Copyable & ~Escapable>` declaration), which is
// what `Parameter.invertibleProtocols` reads. Adding the conditional
// extensions back in produces malformed descriptors under the current
// toolchain — the iteration over `typeContextDescriptors` throws when
// it tries to read one of them. If/when that toolchain bug is fixed,
// the conditional extensions can be reinstated to also exercise the
// merged-requirement path through `conditionalInvertibleProtocolsRequirements`.
