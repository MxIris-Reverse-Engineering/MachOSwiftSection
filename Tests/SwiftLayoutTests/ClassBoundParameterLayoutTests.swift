import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@_spi(Internals) import SwiftInspection
@testable import SwiftLayout
@testable import MachOTestingSupport
import MachOFixtureSupport
import Demangling

/// Validates the class-bound generic parameter path: a parameter constrained
/// to a class layout (`A: AnyObject`), a superclass (`A: LayoutAncestorClass`),
/// or a class-bound protocol (Swift or ObjC) is necessarily a single object
/// reference, so a generic type's fields — including the parameter-typed ones
/// — lay out exactly **without any specialization**. Ground truth is the
/// runtime field-offset vector of a concrete class instantiation, materialized
/// through the metadata accessor where the signature needs no witness table
/// (`AnyObject` layout constraints, ObjC protocols, superclass bounds are all
/// validation-only or table-free); the Swift class-bound protocol variant —
/// whose accessor *does* need a witness table — shares its exact field shape
/// with the accessor-validated `AnyObject` variant instead. Verified on the
/// in-process reader and the offline `MachOFile` reader.
@Suite
final class ClassBoundParameterLayoutTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {

    /// The concrete class fed to the metadata accessors as the generic
    /// argument. Any class works — every class instantiation of a class-bound
    /// parameter has the identical layout, which is the property under test.
    private final class RuntimeProbeElement {}

    /// Generic types whose unspecialized static layout must fully resolve and
    /// match the runtime offsets of a concrete class instantiation, obtained
    /// via the accessor with a single metatype argument (no witness tables in
    /// the signature).
    private static let accessorValidatedTypeShortNames = [
        "GenericStructLayoutRequirement",
        "GenericStructObjCProtocolRequirement",
        "GenericStructBaseClassRequirement",
        "GenericClassLayoutRequirement",
        "ClassBoundWrappedFieldStruct",
        "GenericStructWithClassBoundEnumField",
        "ClassBoundGenericSubclass",
    ]

    @MainActor
    @Test func classBoundParameterFieldsResolveUnspecialized() async throws {
        let machO = machOImage
        let calculator = try StaticLayoutCalculator(machO: machO)
        let fileCalculator = try StaticLayoutCalculator(machO: machOFile)

        for shortName in Self.accessorValidatedTypeShortNames {
            let qualifiedTypeName = "SymbolTestsCore.GenericFieldLayout.\(shortName)"
            let runtimeOffsets = try #require(
                try runtimeFieldOffsets(
                    ofGenericQualifiedTypeName: qualifiedTypeName,
                    argumentMetatype: RuntimeProbeElement.self,
                    in: machO
                ),
                "no runtime field-offset vector for \(qualifiedTypeName)"
            )
            // The static layout is computed *unspecialized* — no generic
            // arguments supplied — and must still match the instantiation.
            let aggregate = try fieldLayout(ofQualifiedTypeName: qualifiedTypeName, with: calculator, in: machO)
            assertFullyComputed(aggregate, equals: runtimeOffsets, typeName: qualifiedTypeName)

            let fileAggregate = try fieldLayout(ofQualifiedTypeName: qualifiedTypeName, with: fileCalculator, in: machOFile)
            assertFullyComputed(fileAggregate, equals: runtimeOffsets, typeName: "\(qualifiedTypeName) (MachOFile)")
        }
    }

    /// The Swift class-bound protocol constraint (`A: ClassBoundElementProtocol`)
    /// needs a witness table at instantiation, so its accessor cannot be driven
    /// by a metatype alone. Its fixture deliberately shares the exact field
    /// shape of the accessor-validated `AnyObject` variant — the two layouts
    /// must be identical, transitively pinning it to the runtime.
    @MainActor
    @Test func classBoundSwiftProtocolConstraintMatchesLayoutConstraintShape() async throws {
        let machO = machOImage
        let calculator = try StaticLayoutCalculator(machO: machO)

        let referenceQualifiedTypeName = "SymbolTestsCore.GenericFieldLayout.GenericStructLayoutRequirement"
        let referenceOffsets = try #require(
            try runtimeFieldOffsets(
                ofGenericQualifiedTypeName: referenceQualifiedTypeName,
                argumentMetatype: RuntimeProbeElement.self,
                in: machO
            )
        )
        let protocolConstrainedQualifiedTypeName = "SymbolTestsCore.GenericFieldLayout.GenericStructClassBoundSwiftProtocolRequirement"
        let aggregate = try fieldLayout(ofQualifiedTypeName: protocolConstrainedQualifiedTypeName, with: calculator, in: machO)
        assertFullyComputed(aggregate, equals: referenceOffsets, typeName: protocolConstrainedQualifiedTypeName)

        let fileCalculator = try StaticLayoutCalculator(machO: machOFile)
        let fileAggregate = try fieldLayout(ofQualifiedTypeName: protocolConstrainedQualifiedTypeName, with: fileCalculator, in: machOFile)
        assertFullyComputed(fileAggregate, equals: referenceOffsets, typeName: "\(protocolConstrainedQualifiedTypeName) (MachOFile)")
    }

    /// Two parameter-declaring levels, both class-bound: the cumulative
    /// requirement signature marks the inherited depth-0 parameter and the own
    /// depth-1 parameter. Runtime ground truth via the accessor with both
    /// metatype arguments (outermost first).
    @MainActor
    @Test func nestedGenericContextBindsClassBoundParametersAtBothDepths() async throws {
        let machO = machOImage
        let qualifiedTypeName = "SymbolTestsCore.GenericFieldLayout.ClassBoundOuter.ClassBoundInner"
        let runtimeOffsets = try #require(
            try Self.runtimeFieldOffsetsOfTwoParameterType(
                ofQualifiedTypeName: qualifiedTypeName,
                firstArgumentMetatype: RuntimeProbeElement.self,
                secondArgumentMetatype: RuntimeProbeElement.self,
                in: machO
            ),
            "no runtime field-offset vector for \(qualifiedTypeName)"
        )
        let calculator = try StaticLayoutCalculator(machO: machO)
        let aggregate = try fieldLayout(ofQualifiedTypeName: qualifiedTypeName, with: calculator, in: machO)
        assertFullyComputed(aggregate, equals: runtimeOffsets, typeName: qualifiedTypeName)

        let fileCalculator = try StaticLayoutCalculator(machO: machOFile)
        let fileAggregate = try fieldLayout(ofQualifiedTypeName: qualifiedTypeName, with: fileCalculator, in: machOFile)
        assertFullyComputed(fileAggregate, equals: runtimeOffsets, typeName: "\(qualifiedTypeName) (MachOFile)")
    }

    /// A class-bound generic class with an Objective-C ancestor: the ancestor's
    /// `class_ro_t` lives in libobjc, so the dependency closure supplies the
    /// start offset (`NSObject`'s instance size, 8) and the class-bound
    /// parameter supplies the field layouts — both without specialization.
    @MainActor
    @Test func classBoundParameterResolvesOnObjCAncestorClass() async throws {
        let machO = machOImage
        let qualifiedTypeName = "SymbolTestsCore.GenericFieldLayout.ClassBoundGenericNSObjectSubclass"
        let runtimeOffsets = try #require(
            try runtimeFieldOffsets(
                ofGenericQualifiedTypeName: qualifiedTypeName,
                argumentMetatype: RuntimeProbeElement.self,
                in: machO
            ),
            "no runtime field-offset vector for \(qualifiedTypeName)"
        )
        let universe = try ImageUniverse.dependencyClosure(root: machO)
        let calculator = StaticLayoutCalculator(imageUniverse: universe)
        let aggregate = try fieldLayout(ofQualifiedTypeName: qualifiedTypeName, with: calculator, in: machO)
        assertFullyComputed(aggregate, equals: runtimeOffsets, typeName: qualifiedTypeName)
    }

    /// The degradation semantics stay intact for everything the constraint
    /// does not pin: an unconstrained or non-class-bound parameter still
    /// degrades (`genericParameterUnsubstituted`), fields before it resolve,
    /// and fields after it report `precedingFieldUnresolved` — including a
    /// class-bound field trapped behind an unresolved one.
    @MainActor
    @Test func nonClassBoundParametersStillDegrade() async throws {
        let machO = machOImage
        let calculator = try StaticLayoutCalculator(machO: machO)

        // `GenericStructNonRequirement<A>`: field1 (Double) resolves at 0, the
        // bare `A` degrades, field3 follows it into the unknown.
        let unconstrained = try fieldLayout(
            ofQualifiedTypeName: "SymbolTestsCore.GenericFieldLayout.GenericStructNonRequirement",
            with: calculator,
            in: machO
        )
        assertDegradationPattern(
            unconstrained,
            expectedResolutions: [.computedAt(0), .unsubstituted, .blockedByPrecedingField],
            typeName: "GenericStructNonRequirement"
        )

        // `Equatable` is not class-bound: identical degradation.
        let swiftProtocolConstrained = try fieldLayout(
            ofQualifiedTypeName: "SymbolTestsCore.GenericFieldLayout.GenericStructSwiftProtocolRequirement",
            with: calculator,
            in: machO
        )
        assertDegradationPattern(
            swiftProtocolConstrained,
            expectedResolutions: [.computedAt(0), .unsubstituted, .blockedByPrecedingField],
            typeName: "GenericStructSwiftProtocolRequirement"
        )

        // Mixed: the class-bound `Reference` fields resolve until the
        // unconstrained `Value` field blocks the accumulator.
        let partiallyClassBound = try fieldLayout(
            ofQualifiedTypeName: "SymbolTestsCore.GenericFieldLayout.PartiallyClassBoundGenericStruct",
            with: calculator,
            in: machO
        )
        assertDegradationPattern(
            partiallyClassBound,
            expectedResolutions: [.computedAt(0), .computedAt(8), .unsubstituted, .blockedByPrecedingField],
            typeName: "PartiallyClassBoundGenericStruct"
        )
    }

    // MARK: - Expected resolution shapes

    private enum ExpectedFieldResolution {
        case computedAt(Int)
        case unsubstituted
        case blockedByPrecedingField
    }

    private func assertDegradationPattern(
        _ aggregate: AggregateFieldLayout,
        expectedResolutions: [ExpectedFieldResolution],
        typeName: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            aggregate.fields.count == expectedResolutions.count,
            "\(typeName): expected \(expectedResolutions.count) fields, got \(aggregate.fields.count)",
            sourceLocation: sourceLocation
        )
        for (field, expected) in zip(aggregate.fields, expectedResolutions) {
            switch (field.resolution, expected) {
            case (.computed, .computedAt(let expectedOffset)):
                #expect(
                    field.offset == expectedOffset,
                    "\(typeName).\(field.fieldName): computed at \(field.offset), expected \(expectedOffset)",
                    sourceLocation: sourceLocation
                )
            case (.unknown(reason: .genericParameterUnsubstituted), .unsubstituted),
                 (.unknown(reason: .precedingFieldUnresolved), .blockedByPrecedingField):
                break
            default:
                Issue.record(
                    "\(typeName).\(field.fieldName): resolution \(field.resolution) does not match expectation \(expected)",
                    sourceLocation: sourceLocation
                )
            }
        }
    }

    // MARK: - Runtime ground truth for two-parameter types

    /// Same walk as the shared `runtimeFieldOffsets(ofGenericQualifiedTypeName:
    /// argumentMetatype:in:)` helper, but supplying two depth-ordered metatype
    /// arguments (an inherited parameter plus the type's own).
    private static func runtimeFieldOffsetsOfTwoParameterType(
        ofQualifiedTypeName qualifiedTypeName: String,
        firstArgumentMetatype: Any.Type,
        secondArgumentMetatype: Any.Type,
        in machO: MachOImage
    ) throws -> [Int]? {
        for contextDescriptor in try machO.swift.contextDescriptors {
            guard let descriptor = contextDescriptor.typeContextDescriptorWrapper else { continue }
            guard
                let name = (try? MetadataReader.demangleContext(for: contextDescriptor, in: machO))
                    .flatMap(NodeTypeNaming.nominalQualifiedName(of:)),
                name == qualifiedTypeName,
                let accessor = try descriptor.typeContextDescriptor.metadataAccessorFunction(in: machO)
            else { continue }
            let response = try accessor(request: .init(), metatypes: firstArgumentMetatype, secondArgumentMetatype)
            let metadata = try response.value.resolve(in: machO)
            switch metadata {
            case .struct(let structMetadata):
                return try structMetadata.fieldOffsets(in: machO).map { Int($0) }
            case .class(let classMetadata):
                return try classMetadata.fieldOffsets(in: machO).map { Int($0) }
            default:
                return nil
            }
        }
        return nil
    }
}

/// Unit tests for the placeholder rewrite itself — hand-built `Node` trees, no
/// fixture: an unsubstituted class-bound parameter rewrites to a class node
/// (one pointer), a supplied substitution wins over the class-bound set, and
/// parameters outside the set stay untouched.
@Suite
struct ClassBoundParameterSubstitutionTests {

    private func dependentParameter(depth: UInt64, index: UInt64) -> Node {
        Node.create(kind: .dependentGenericParamType, children: [
            Node.create(kind: .index, index: depth),
            Node.create(kind: .index, index: index),
        ])
    }

    private func intStructure() -> Node {
        Node.create(kind: .structure, children: [
            Node.create(kind: .module, text: "Swift"),
            Node.create(kind: .identifier, text: "Int"),
        ])
    }

    @Test func classBoundParameterRewritesToClassPlaceholder() {
        let environment = GenericArgumentEnvironment(
            substitutions: [:],
            classBoundParameterKeys: [GenericParameterKey(depth: 0, index: 0)]
        )
        let fieldNode = Node.create(kind: .type, child: dependentParameter(depth: 0, index: 0))
        let result = environment.substituting(in: fieldNode)
        #expect(result.firstChild?.kind == .class, "a class-bound parameter must rewrite to a class node")
    }

    @Test func substitutionTakesPrecedenceOverClassBoundRewrite() {
        let environment = GenericArgumentEnvironment(
            substitutions: [GenericParameterKey(depth: 0, index: 0): intStructure()],
            classBoundParameterKeys: [GenericParameterKey(depth: 0, index: 0)]
        )
        let fieldNode = Node.create(kind: .type, child: dependentParameter(depth: 0, index: 0))
        let result = environment.substituting(in: fieldNode)
        #expect(result.firstChild?.kind == .structure, "a supplied argument must win over the placeholder")
        #expect(result.firstChild?.identifier == "Int")
    }

    @Test func parameterOutsideClassBoundSetStaysUntouched() {
        let environment = GenericArgumentEnvironment(
            substitutions: [:],
            classBoundParameterKeys: [GenericParameterKey(depth: 0, index: 0)]
        )
        let fieldNode = Node.create(kind: .type, child: dependentParameter(depth: 0, index: 1))
        let result = environment.substituting(in: fieldNode)
        #expect(
            result.firstChild?.kind == .dependentGenericParamType,
            "an unlisted parameter must survive so it degrades to unknown as before"
        )
    }

    @Test func classBoundRewriteReachesThroughCompoundTypes() {
        let environment = GenericArgumentEnvironment(
            substitutions: [:],
            classBoundParameterKeys: [GenericParameterKey(depth: 0, index: 0)]
        )
        // (Element, Int) — the tuple element referencing the parameter must
        // rewrite in place.
        let tupleNode = Node.create(kind: .tuple, children: [
            Node.create(kind: .tupleElement, child: Node.create(kind: .type, child: dependentParameter(depth: 0, index: 0))),
            Node.create(kind: .tupleElement, child: Node.create(kind: .type, child: intStructure())),
        ])
        let result = environment.substituting(in: tupleNode)
        #expect(result.firstChild?.firstChild?.firstChild?.kind == .class)
    }
}
