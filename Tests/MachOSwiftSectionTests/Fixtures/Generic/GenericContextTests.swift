import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `TargetGenericContext` (the underlying generic
/// struct behind both the `GenericContext` and `TypeGenericContext`
/// typealiases declared in `GenericContext.swift`).
///
/// PublicMemberScanner emits MethodKey entries under the typeName
/// `TargetGenericContext` (the source-level struct declaration name), so
/// `testedTypeName` is `TargetGenericContext`.
///
/// Each `@Test` exercises one ivar / derived var / initializer of the
/// generic context. The cross-reader assertions use *cardinality* (counts
/// for arrays of arrays, presence flags for optional payloads) — the
/// underlying types (`GenericRequirementDescriptor`,
/// `GenericPackShapeDescriptor`, etc.) are not Equatable cheaply and
/// presence + cardinality is the meaningful invariant. The fixture
/// variants together exercise:
///   - `nonRequirement` — params only
///   - `layoutRequirement` — params + layout requirement
///   - `protocolRequirement` — params + protocol requirement
///   - `parameterPack` — typePackHeader/typePacks
///   - `invertibleProtocol` — invertedProtocols requirement
@Suite
final class GenericContextTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "TargetGenericContext"
    static var registeredTestMethodNames: Set<String> {
        GenericContextBaseline.registeredTestMethodNames
    }

    // MARK: - Helpers

    private func loadContextsFromFile(
        for picker: (MachOFile) throws -> StructDescriptor
    ) throws -> TypeGenericContext {
        let fileDescriptor = try picker(machOFile)
        return try required(try fileDescriptor.typeGenericContext(in: machOFile))
    }

    private func loadContextsFromImage(
        for picker: (MachOImage) throws -> StructDescriptor
    ) throws -> TypeGenericContext {
        let imageDescriptor = try picker(machOImage)
        return try required(try imageDescriptor.typeGenericContext(in: machOImage))
    }

    private func nonRequirementContexts() throws -> (file: TypeGenericContext, image: TypeGenericContext) {
        let file = try loadContextsFromFile { try BaselineFixturePicker.struct_GenericStructNonRequirement(in: $0) }
        let image = try loadContextsFromImage { try BaselineFixturePicker.struct_GenericStructNonRequirement(in: $0) }
        return (file: file, image: image)
    }

    private func layoutRequirementContexts() throws -> (file: TypeGenericContext, image: TypeGenericContext) {
        let file = try loadContextsFromFile { try BaselineFixturePicker.struct_GenericStructLayoutRequirement(in: $0) }
        let image = try loadContextsFromImage { try BaselineFixturePicker.struct_GenericStructLayoutRequirement(in: $0) }
        return (file: file, image: image)
    }

    private func protocolRequirementContexts() throws -> (file: TypeGenericContext, image: TypeGenericContext) {
        let file = try loadContextsFromFile { try BaselineFixturePicker.struct_GenericStructSwiftProtocolRequirement(in: $0) }
        let image = try loadContextsFromImage { try BaselineFixturePicker.struct_GenericStructSwiftProtocolRequirement(in: $0) }
        return (file: file, image: image)
    }

    private func parameterPackContexts() throws -> (file: TypeGenericContext, image: TypeGenericContext) {
        let file = try loadContextsFromFile { try BaselineFixturePicker.struct_ParameterPackRequirementTest(in: $0) }
        let image = try loadContextsFromImage { try BaselineFixturePicker.struct_ParameterPackRequirementTest(in: $0) }
        return (file: file, image: image)
    }

    private func invertibleProtocolContexts() throws -> (file: TypeGenericContext, image: TypeGenericContext) {
        let file = try loadContextsFromFile { try BaselineFixturePicker.struct_InvertibleProtocolRequirementTest(in: $0) }
        let image = try loadContextsFromImage { try BaselineFixturePicker.struct_InvertibleProtocolRequirementTest(in: $0) }
        return (file: file, image: image)
    }

    // MARK: - Initializers

    @Test("init(contextDescriptor:in:)") func initializerWithMachO() async throws {
        let fileDescriptor = try BaselineFixturePicker.struct_GenericStructLayoutRequirement(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_GenericStructLayoutRequirement(in: machOImage)

        let fileMachO = try TypeGenericContext(contextDescriptor: fileDescriptor, in: machOFile)
        let imageMachO = try TypeGenericContext(contextDescriptor: imageDescriptor, in: machOImage)
        let fileCtx = try TypeGenericContext(contextDescriptor: fileDescriptor, in: fileContext)
        let imageCtx = try TypeGenericContext(contextDescriptor: imageDescriptor, in: imageContext)

        #expect(fileMachO.offset == GenericContextBaseline.layoutRequirement.offset)
        #expect(imageMachO.offset == GenericContextBaseline.layoutRequirement.offset)
        #expect(fileCtx.offset == GenericContextBaseline.layoutRequirement.offset)
        #expect(imageCtx.offset == GenericContextBaseline.layoutRequirement.offset)
    }

    @Test("init(contextDescriptor:)") func initializerInProcess() async throws {
        let imageDescriptor = try BaselineFixturePicker.struct_GenericStructLayoutRequirement(in: machOImage)
        let pointerWrapper = imageDescriptor.asPointerWrapper(in: machOImage)
        // The InProcess init walks the descriptor via raw pointer arithmetic;
        // we just assert it succeeds and produces a non-zero offset (the
        // absolute pointer is per-process).
        let inProcess = try TypeGenericContext(contextDescriptor: pointerWrapper)
        #expect(inProcess.offset != 0)
    }

    // MARK: - Scalar ivars

    @Test func offset() async throws {
        let contexts = try layoutRequirementContexts()
        let result = try acrossAllReaders(
            file: { contexts.file.offset },
            image: { contexts.image.offset }
        )
        #expect(result == GenericContextBaseline.layoutRequirement.offset)
    }

    @Test func size() async throws {
        let contexts = try layoutRequirementContexts()
        let result = try acrossAllReaders(
            file: { contexts.file.size },
            image: { contexts.image.size }
        )
        #expect(result == GenericContextBaseline.layoutRequirement.size)
    }

    @Test func depth() async throws {
        let contexts = try layoutRequirementContexts()
        let result = try acrossAllReaders(
            file: { contexts.file.depth },
            image: { contexts.image.depth }
        )
        #expect(result == GenericContextBaseline.layoutRequirement.depth)
    }

    @Test func header() async throws {
        // The header's `offset` equals the descriptor's offset + layoutSize
        // (i.e. the start of the generic-context payload). Cross-reader
        // equality is captured indirectly via the header's `numParams` ivar.
        let contexts = try layoutRequirementContexts()
        let numParams = try acrossAllReaders(
            file: { contexts.file.header.layout.numParams },
            image: { contexts.image.header.layout.numParams }
        )
        #expect(Int(numParams) == GenericContextBaseline.layoutRequirement.parametersCount)
    }

    // MARK: - Direct arrays

    @Test func parameters() async throws {
        let contexts = try layoutRequirementContexts()
        let count = try acrossAllReaders(
            file: { contexts.file.parameters.count },
            image: { contexts.image.parameters.count }
        )
        #expect(count == GenericContextBaseline.layoutRequirement.parametersCount)
    }

    @Test func requirements() async throws {
        let contexts = try layoutRequirementContexts()
        let count = try acrossAllReaders(
            file: { contexts.file.requirements.count },
            image: { contexts.image.requirements.count }
        )
        #expect(count == GenericContextBaseline.layoutRequirement.requirementsCount)
    }

    @Test func typePackHeader() async throws {
        // No type packs on layoutRequirement; presence true on parameterPack.
        let contexts = try layoutRequirementContexts()
        let layoutPresence = try acrossAllReaders(
            file: { contexts.file.typePackHeader != nil },
            image: { contexts.image.typePackHeader != nil }
        )
        #expect(layoutPresence == GenericContextBaseline.layoutRequirement.hasTypePackHeader)

        let packContexts = try parameterPackContexts()
        let packPresence = try acrossAllReaders(
            file: { packContexts.file.typePackHeader != nil },
            image: { packContexts.image.typePackHeader != nil }
        )
        #expect(packPresence == GenericContextBaseline.parameterPack.hasTypePackHeader)
    }

    @Test func typePacks() async throws {
        let packContexts = try parameterPackContexts()
        let count = try acrossAllReaders(
            file: { packContexts.file.typePacks.count },
            image: { packContexts.image.typePacks.count }
        )
        #expect(count == GenericContextBaseline.parameterPack.typePacksCount)
    }

    @Test func valueHeader() async throws {
        // None of the SymbolTestsCore fixtures use integer-value generic
        // parameters, so valueHeader is always nil. Check on the layout
        // fixture (a representative case).
        let contexts = try layoutRequirementContexts()
        let presence = try acrossAllReaders(
            file: { contexts.file.valueHeader != nil },
            image: { contexts.image.valueHeader != nil }
        )
        #expect(presence == GenericContextBaseline.layoutRequirement.hasValueHeader)
    }

    @Test func values() async throws {
        let contexts = try layoutRequirementContexts()
        let count = try acrossAllReaders(
            file: { contexts.file.values.count },
            image: { contexts.image.values.count }
        )
        #expect(count == GenericContextBaseline.layoutRequirement.valuesCount)
    }

    // MARK: - Parent arrays

    @Test func parentParameters() async throws {
        let contexts = try layoutRequirementContexts()
        let count = try acrossAllReaders(
            file: { contexts.file.parentParameters.count },
            image: { contexts.image.parentParameters.count }
        )
        #expect(count == GenericContextBaseline.layoutRequirement.parentParametersCount)
    }

    @Test func parentRequirements() async throws {
        let contexts = try layoutRequirementContexts()
        let count = try acrossAllReaders(
            file: { contexts.file.parentRequirements.count },
            image: { contexts.image.parentRequirements.count }
        )
        #expect(count == GenericContextBaseline.layoutRequirement.parentRequirementsCount)
    }

    @Test func parentTypePacks() async throws {
        let contexts = try layoutRequirementContexts()
        let count = try acrossAllReaders(
            file: { contexts.file.parentTypePacks.count },
            image: { contexts.image.parentTypePacks.count }
        )
        #expect(count == GenericContextBaseline.layoutRequirement.parentTypePacksCount)
    }

    @Test func parentValues() async throws {
        let contexts = try layoutRequirementContexts()
        let count = try acrossAllReaders(
            file: { contexts.file.parentValues.count },
            image: { contexts.image.parentValues.count }
        )
        #expect(count == GenericContextBaseline.layoutRequirement.parentValuesCount)
    }

    // MARK: - Conditional invertible protocols

    @Test func conditionalInvertibleProtocolSet() async throws {
        // Conditional set is captured when the
        // `hasConditionalInvertedProtocols` flag is set; the fixture's
        // `InvertibleProtocolRequirementTest` does not surface this bit
        // (the inverted-protocols requirement is emitted as a regular
        // requirement instead), so we check both fixtures register the
        // baseline-recorded presence.
        let invertible = try invertibleProtocolContexts()
        let presence = try acrossAllReaders(
            file: { invertible.file.conditionalInvertibleProtocolSet != nil },
            image: { invertible.image.conditionalInvertibleProtocolSet != nil }
        )
        #expect(presence == GenericContextBaseline.invertibleProtocol.hasConditionalInvertibleProtocolSet)
    }

    @Test func conditionalInvertibleProtocolsRequirementsCount() async throws {
        let invertible = try invertibleProtocolContexts()
        let presence = try acrossAllReaders(
            file: { invertible.file.conditionalInvertibleProtocolsRequirementsCount != nil },
            image: { invertible.image.conditionalInvertibleProtocolsRequirementsCount != nil }
        )
        #expect(presence == GenericContextBaseline.invertibleProtocol.hasConditionalInvertibleProtocolsRequirementsCount)
    }

    @Test func conditionalInvertibleProtocolsRequirements() async throws {
        let invertible = try invertibleProtocolContexts()
        let count = try acrossAllReaders(
            file: { invertible.file.conditionalInvertibleProtocolsRequirements.count },
            image: { invertible.image.conditionalInvertibleProtocolsRequirements.count }
        )
        #expect(count == GenericContextBaseline.invertibleProtocol.conditionalInvertibleProtocolsRequirementsCount)
    }

    // MARK: - Derived vars

    @Test func currentParameters() async throws {
        let contexts = try layoutRequirementContexts()
        let count = try acrossAllReaders(
            file: { contexts.file.currentParameters.count },
            image: { contexts.image.currentParameters.count }
        )
        #expect(count == GenericContextBaseline.layoutRequirement.currentParametersCount)
    }

    @Test func currentRequirements() async throws {
        let contexts = try layoutRequirementContexts()
        let count = try acrossAllReaders(
            file: { contexts.file.currentRequirements.count },
            image: { contexts.image.currentRequirements.count }
        )
        #expect(count == GenericContextBaseline.layoutRequirement.currentRequirementsCount)
    }

    @Test func currentTypePacks() async throws {
        let packContexts = try parameterPackContexts()
        let count = try acrossAllReaders(
            file: { packContexts.file.currentTypePacks.count },
            image: { packContexts.image.currentTypePacks.count }
        )
        #expect(count == GenericContextBaseline.parameterPack.currentTypePacksCount)
    }

    @Test func currentValues() async throws {
        let contexts = try layoutRequirementContexts()
        let count = try acrossAllReaders(
            file: { contexts.file.currentValues.count },
            image: { contexts.image.currentValues.count }
        )
        #expect(count == GenericContextBaseline.layoutRequirement.currentValuesCount)
    }

    @Test func allParameters() async throws {
        let contexts = try layoutRequirementContexts()
        let count = try acrossAllReaders(
            file: { contexts.file.allParameters.count },
            image: { contexts.image.allParameters.count }
        )
        #expect(count == GenericContextBaseline.layoutRequirement.allParametersCount)
    }

    @Test func allRequirements() async throws {
        let contexts = try layoutRequirementContexts()
        let count = try acrossAllReaders(
            file: { contexts.file.allRequirements.count },
            image: { contexts.image.allRequirements.count }
        )
        #expect(count == GenericContextBaseline.layoutRequirement.allRequirementsCount)
    }

    @Test func allTypePacks() async throws {
        let packContexts = try parameterPackContexts()
        let count = try acrossAllReaders(
            file: { packContexts.file.allTypePacks.count },
            image: { packContexts.image.allTypePacks.count }
        )
        #expect(count == GenericContextBaseline.parameterPack.allTypePacksCount)
    }

    @Test func allValues() async throws {
        let contexts = try layoutRequirementContexts()
        let count = try acrossAllReaders(
            file: { contexts.file.allValues.count },
            image: { contexts.image.allValues.count }
        )
        #expect(count == GenericContextBaseline.layoutRequirement.allValuesCount)
    }

    // MARK: - Methods

    @Test func uniqueCurrentRequirements() async throws {
        // Top-level type with no parent generic context: every requirement
        // is unique. Cross-reader equality on the count.
        let contexts = try layoutRequirementContexts()
        let count = try acrossAllReaders(
            file: { contexts.file.uniqueCurrentRequirements(in: machOFile).count },
            image: { contexts.image.uniqueCurrentRequirements(in: machOImage).count }
        )
        #expect(count == GenericContextBaseline.layoutRequirement.requirementsCount)
    }

    @Test func uniqueCurrentRequirementsInProcess() async throws {
        let contexts = try layoutRequirementContexts()
        let count = try acrossAllReaders(
            file: { contexts.file.uniqueCurrentRequirementsInProcess().count },
            image: { contexts.image.uniqueCurrentRequirementsInProcess().count }
        )
        #expect(count == GenericContextBaseline.layoutRequirement.requirementsCount)
    }

    @Test func asGenericContext() async throws {
        // `asGenericContext` projects a TypeGenericContext down to the base
        // GenericContext shape. The offset/parameter/requirement counts must
        // match the original.
        let contexts = try layoutRequirementContexts()
        let fileProjection = contexts.file.asGenericContext()
        let imageProjection = contexts.image.asGenericContext()

        let fileMatch = (
            fileProjection.offset == contexts.file.offset
            && fileProjection.parameters.count == contexts.file.parameters.count
            && fileProjection.requirements.count == contexts.file.requirements.count
        )
        let imageMatch = (
            imageProjection.offset == contexts.image.offset
            && imageProjection.parameters.count == contexts.image.parameters.count
            && imageProjection.requirements.count == contexts.image.requirements.count
        )

        #expect(fileMatch)
        #expect(imageMatch)
        #expect(fileProjection.offset == GenericContextBaseline.layoutRequirement.offset)
    }
}
