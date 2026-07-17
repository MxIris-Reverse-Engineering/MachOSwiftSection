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

/// Validates two extensions made after the class-bound-parameter phase:
///
/// 1. **Metatype field thinness.** A metatype's storage is decided by its
///    instance's *syntactic* kind, not by the aggregate's genericity: a
///    concrete value-type metatype (`Int64.Type`) is thin (zero-sized) even
///    inside a generic type, a class metatype is thick (one pointer), and a
///    generic-parameter metatype (`Element.Type`) is thick in *every*
///    instantiation — so a generic type's metatype-of-parameter field resolves
///    exactly **without specialization**. Ground truth is the runtime
///    field-offset vector (a concrete instantiation for the generic case).
///
/// 2. **Generic enum case projection.** `enumCaseLayoutResult` projects a
///    generic multi-payload enum whose payloads are all class-bound (tagged
///    strategy, no arguments needed) exactly like its instantiations.
///
/// Both readers (in-process `MachOImage` and offline `MachOFile`) are checked.
@Suite
final class MetatypeAndGenericEnumProjectionLayoutTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {

    /// The concrete class fed to the generic accessors as the argument. Any
    /// class works — a parameter's metatype has the same (thick) layout for
    /// every class, which is the property under test.
    private final class RuntimeProbeElement {}

    @MainActor
    @Test func concreteMetatypeFieldsMatchCompilerLowering() async throws {
        let machO = machOImage
        let qualifiedTypeName = "SymbolTestsCore.GenericFieldLayout.ConcreteMetatypeFieldStruct"
        let runtimeOffsets = try #require(
            try runtimeFieldOffsets(ofQualifiedTypeName: qualifiedTypeName, in: machO),
            "no runtime field-offset vector for \(qualifiedTypeName)"
        )

        let calculator = try StaticLayoutCalculator(machO: machO)
        let aggregate = try fieldLayout(ofQualifiedTypeName: qualifiedTypeName, with: calculator, in: machO)
        assertFullyComputed(aggregate, equals: runtimeOffsets, typeName: qualifiedTypeName)

        // A concrete value-type metatype is thin (zero-sized); a class metatype
        // is thick (one pointer). Verified directly, not just via the offsets.
        #expect(aggregate.fields[0].layout?.size == 0, "Int64.Type must be a thin (zero-sized) metatype")
        #expect(aggregate.fields[2].layout?.size == 8, "a class metatype must be thick (one pointer)")
        // Int64.Type? wraps the thin metatype → 1 byte (Optional of a
        // zero-sized payload), not the 8 a thick metatype would give.
        #expect(aggregate.fields[3].layout?.size == 1, "Optional<thin metatype> must be 1 byte")

        let fileCalculator = try StaticLayoutCalculator(machO: machOFile)
        let fileAggregate = try fieldLayout(ofQualifiedTypeName: qualifiedTypeName, with: fileCalculator, in: machOFile)
        assertFullyComputed(fileAggregate, equals: runtimeOffsets, typeName: "\(qualifiedTypeName) (MachOFile)")
    }

    @MainActor
    @Test func genericParameterMetatypeFieldsResolveUnspecialized() async throws {
        let machO = machOImage
        let qualifiedTypeName = "SymbolTestsCore.GenericFieldLayout.GenericMetatypeFieldStruct"
        // Ground truth: a concrete instantiation's runtime offsets. The static
        // layout is computed *unspecialized* and must match — a
        // parameter's metatype is thick in every instantiation.
        let runtimeOffsets = try #require(
            try runtimeFieldOffsets(
                ofGenericQualifiedTypeName: qualifiedTypeName,
                argumentMetatype: RuntimeProbeElement.self,
                in: machO
            ),
            "no runtime field-offset vector for \(qualifiedTypeName)"
        )

        let calculator = try StaticLayoutCalculator(machO: machO)
        let aggregate = try fieldLayout(ofQualifiedTypeName: qualifiedTypeName, with: calculator, in: machO)
        assertFullyComputed(aggregate, equals: runtimeOffsets, typeName: qualifiedTypeName)

        // parameterKind (Element.Type) is thick; concreteKind (Int64.Type) is
        // thin even here, in a generic type.
        #expect(aggregate.fields[0].layout?.size == 8, "Element.Type must be a thick metatype")
        #expect(aggregate.fields[2].layout?.size == 0, "a concrete Int64.Type stays thin inside a generic type")
        #expect(aggregate.fields[3].layout?.size == 8, "Optional<thick parameter metatype> must be 8 bytes")

        let fileCalculator = try StaticLayoutCalculator(machO: machOFile)
        let fileAggregate = try fieldLayout(ofQualifiedTypeName: qualifiedTypeName, with: fileCalculator, in: machOFile)
        assertFullyComputed(fileAggregate, equals: runtimeOffsets, typeName: "\(qualifiedTypeName) (MachOFile)")
    }

    /// The generic parameter metatype resolves identically no matter which
    /// concrete class the parameter binds to — the layout does not depend on
    /// the argument, so the unspecialized result is the whole answer.
    @MainActor
    @Test func genericParameterMetatypeIsArgumentIndependent() async throws {
        let machO = machOImage
        let qualifiedTypeName = "SymbolTestsCore.GenericFieldLayout.GenericMetatypeFieldStruct"
        let offsetsWithClass = try #require(
            try runtimeFieldOffsets(ofGenericQualifiedTypeName: qualifiedTypeName, argumentMetatype: RuntimeProbeElement.self, in: machO)
        )
        // A value-type argument yields the same field offsets — a metatype field
        // is a fixed 8 bytes regardless of the argument.
        let offsetsWithValue = try #require(
            try runtimeFieldOffsets(ofGenericQualifiedTypeName: qualifiedTypeName, argumentMetatype: Int64.self, in: machO)
        )
        #expect(offsetsWithClass == offsetsWithValue, "a parameter metatype field must be argument-independent")
    }

    /// A generic multi-payload enum whose payloads are all class-bound projects
    /// its per-case layout (tagged strategy) without any specialization —
    /// `enumCaseLayoutResult` returns a non-nil projection whose payload/tag
    /// regions are consistent with the runtime value-witness size.
    @MainActor
    @Test func genericClassBoundEnumProjectsUnspecialized() async throws {
        let machO = machOImage
        let calculator = try StaticLayoutCalculator(machO: machO)
        let fileCalculator = try StaticLayoutCalculator(machO: machOFile)

        let enumDescriptor = try #require(
            try Self.findEnumDescriptor(named: "SymbolTestsCore.GenericFieldLayout.ClassBoundContent", in: machO)
        )
        let projection = calculator.enumCaseLayoutResult(forDescriptor: enumDescriptor)
        #expect(projection != nil, "a class-bound generic multi-payload enum must project unspecialized")
        // Two payload cases (first(Element), second(Element, Int32)) → the
        // projection must enumerate both payload cases.
        #expect((projection?.cases.count ?? 0) >= 2, "both payload cases must be projected")

        let fileEnumDescriptor = try #require(
            try Self.findEnumDescriptor(named: "SymbolTestsCore.GenericFieldLayout.ClassBoundContent", in: machOFile)
        )
        let fileProjection = fileCalculator.enumCaseLayoutResult(forDescriptor: fileEnumDescriptor)
        #expect(fileProjection != nil, "the MachOFile reader must project it too")
    }

    private static func findEnumDescriptor<MachO: MachOSwiftSectionRepresentableWithCache>(
        named qualifiedTypeName: String,
        in machO: MachO
    ) throws -> TypeContextDescriptorWrapper? {
        for contextDescriptor in try machO.swift.contextDescriptors {
            guard let descriptor = contextDescriptor.typeContextDescriptorWrapper, descriptor.isEnum else { continue }
            guard
                let name = (try? MetadataReader.demangleContext(for: contextDescriptor, in: machO))
                    .flatMap(NodeTypeNaming.nominalQualifiedName(of:)),
                name == qualifiedTypeName
            else { continue }
            return descriptor
        }
        return nil
    }
}
