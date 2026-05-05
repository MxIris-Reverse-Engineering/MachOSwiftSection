import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `GenericRequirement`.
///
/// `GenericRequirement` is the high-level wrapper around a
/// `GenericRequirementDescriptor` that pre-resolves `paramManagledName`
/// and `content` (a `ResolvedGenericRequirementContent`). The Suite reads
/// one wrapper per kind branch (layout / Swift protocol / ObjC protocol /
/// baseClass / sameType) and asserts cross-reader equality of the
/// resolved content discriminant against the baseline.
@Suite
final class GenericRequirementTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "GenericRequirement"
    static var registeredTestMethodNames: Set<String> {
        GenericRequirementBaseline.registeredTestMethodNames
    }

    // MARK: - Helpers

    private func loadFirstRequirement(
        fromFile filePicker: (MachOFile) throws -> StructDescriptor,
        fromImage imagePicker: (MachOImage) throws -> StructDescriptor
    ) throws -> (file: GenericRequirement, image: GenericRequirement) {
        let fileDescriptor = try filePicker(machOFile)
        let imageDescriptor = try imagePicker(machOImage)
        let fileGenericCtx = try required(try fileDescriptor.typeGenericContext(in: machOFile))
        let imageGenericCtx = try required(try imageDescriptor.typeGenericContext(in: machOImage))
        let fileReqDesc = try required(fileGenericCtx.currentRequirements.first)
        let imageReqDesc = try required(imageGenericCtx.currentRequirements.first)
        let fileReq = try GenericRequirement(descriptor: fileReqDesc, in: machOFile)
        let imageReq = try GenericRequirement(descriptor: imageReqDesc, in: machOImage)
        return (file: fileReq, image: imageReq)
    }

    private func layoutRequirements() throws -> (file: GenericRequirement, image: GenericRequirement) {
        try loadFirstRequirement(
            fromFile: { try BaselineFixturePicker.struct_GenericStructLayoutRequirement(in: $0) },
            fromImage: { try BaselineFixturePicker.struct_GenericStructLayoutRequirement(in: $0) }
        )
    }

    private func swiftProtocolRequirements() throws -> (file: GenericRequirement, image: GenericRequirement) {
        try loadFirstRequirement(
            fromFile: { try BaselineFixturePicker.struct_GenericStructSwiftProtocolRequirement(in: $0) },
            fromImage: { try BaselineFixturePicker.struct_GenericStructSwiftProtocolRequirement(in: $0) }
        )
    }

    private func objcProtocolRequirements() throws -> (file: GenericRequirement, image: GenericRequirement) {
        try loadFirstRequirement(
            fromFile: { try BaselineFixturePicker.struct_GenericStructObjCProtocolRequirement(in: $0) },
            fromImage: { try BaselineFixturePicker.struct_GenericStructObjCProtocolRequirement(in: $0) }
        )
    }

    private func baseClassRequirements() throws -> (file: GenericRequirement, image: GenericRequirement) {
        try loadFirstRequirement(
            fromFile: { try BaselineFixturePicker.struct_BaseClassRequirementTest(in: $0) },
            fromImage: { try BaselineFixturePicker.struct_BaseClassRequirementTest(in: $0) }
        )
    }

    private func sameTypeRequirements() throws -> (file: GenericRequirement, image: GenericRequirement) {
        try loadFirstRequirement(
            fromFile: { try BaselineFixturePicker.struct_SameTypeRequirementTest(in: $0) },
            fromImage: { try BaselineFixturePicker.struct_SameTypeRequirementTest(in: $0) }
        )
    }

    // MARK: - Initializers

    @Test("init(descriptor:in:)") func initializerWithMachO() async throws {
        let fileDescriptor = try BaselineFixturePicker.struct_GenericStructLayoutRequirement(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_GenericStructLayoutRequirement(in: machOImage)
        let fileContext = try required(try fileDescriptor.typeGenericContext(in: machOFile))
        let imageContext = try required(try imageDescriptor.typeGenericContext(in: machOImage))
        let fileReqDesc = try required(fileContext.currentRequirements.first)
        let imageReqDesc = try required(imageContext.currentRequirements.first)

        let fileReq = try GenericRequirement(descriptor: fileReqDesc, in: machOFile)
        let imageReq = try GenericRequirement(descriptor: imageReqDesc, in: machOImage)
        let fileCtxReq = try GenericRequirement(descriptor: fileReqDesc, in: self.fileContext)

        #expect(fileReq.descriptor.offset == GenericRequirementBaseline.layoutRequirement.descriptorOffset)
        #expect(imageReq.descriptor.offset == GenericRequirementBaseline.layoutRequirement.descriptorOffset)
        #expect(fileCtxReq.descriptor.offset == GenericRequirementBaseline.layoutRequirement.descriptorOffset)
    }

    @Test("init(descriptor:)") func initializerInProcess() async throws {
        // The InProcess init walks the descriptor via raw pointer arithmetic.
        // We pull a descriptor from the image then re-wrap as a pointer-form.
        let imageDescriptor = try BaselineFixturePicker.struct_GenericStructLayoutRequirement(in: machOImage)
        let imageContext = try required(try imageDescriptor.typeGenericContext(in: machOImage))
        let imageReqDesc = try required(imageContext.currentRequirements.first)
        let pointerDescriptor = imageReqDesc.asPointerWrapper(in: machOImage)
        let inProcess = try GenericRequirement(descriptor: pointerDescriptor)
        // The in-process descriptor.offset is a pointer bit pattern; just
        // assert it resolved.
        #expect(inProcess.descriptor.offset != 0)
    }

    // MARK: - Ivars

    @Test func descriptor() async throws {
        let layout = try layoutRequirements()
        let result = try acrossAllReaders(
            file: { layout.file.descriptor.offset },
            image: { layout.image.descriptor.offset }
        )
        #expect(result == GenericRequirementBaseline.layoutRequirement.descriptorOffset)
    }

    @Test func paramManagledName() async throws {
        let layout = try layoutRequirements()
        // MangledName is Hashable/Equatable; compare directly.
        #expect(layout.file.paramManagledName == layout.image.paramManagledName)
    }

    @Test func content() async throws {
        // For .layout / .baseClass / .sameType branches, the resolved
        // content is reader-stable (mangled-name parse trees are
        // deterministic across MachOFile/MachOImage). For the .protocol
        // branches, the underlying SymbolOrElement may be a `.symbol`
        // (file-side cross-image bind) on one reader and a `.element`
        // (resolved descriptor) on the other; we therefore only assert the
        // discriminant matches the baseline for those.
        let layout = try layoutRequirements()
        #expect(layout.file.content == layout.image.content)
        #expect(describeResolvedKind(layout.file.content) == GenericRequirementBaseline.layoutRequirement.resolvedContentCase)

        let swift = try swiftProtocolRequirements()
        #expect(describeResolvedKind(swift.file.content) == GenericRequirementBaseline.swiftProtocolRequirement.resolvedContentCase)
        #expect(describeResolvedKind(swift.image.content) == GenericRequirementBaseline.swiftProtocolRequirement.resolvedContentCase)

        let objc = try objcProtocolRequirements()
        #expect(describeResolvedKind(objc.file.content) == GenericRequirementBaseline.objcProtocolRequirement.resolvedContentCase)
        #expect(describeResolvedKind(objc.image.content) == GenericRequirementBaseline.objcProtocolRequirement.resolvedContentCase)

        let baseClass = try baseClassRequirements()
        #expect(baseClass.file.content == baseClass.image.content)
        #expect(describeResolvedKind(baseClass.file.content) == GenericRequirementBaseline.baseClassRequirement.resolvedContentCase)

        let sameType = try sameTypeRequirements()
        #expect(sameType.file.content == sameType.image.content)
        #expect(describeResolvedKind(sameType.file.content) == GenericRequirementBaseline.sameTypeRequirement.resolvedContentCase)
    }

    // MARK: - Private helpers

    private func describeResolvedKind(_ content: ResolvedGenericRequirementContent) -> String {
        switch content {
        case .type: return "type"
        case .protocol: return "protocol"
        case .layout: return "layout"
        case .conformance: return "conformance"
        case .invertedProtocols: return "invertedProtocols"
        }
    }
}
