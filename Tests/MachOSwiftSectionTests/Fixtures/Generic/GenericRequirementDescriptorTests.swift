import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `GenericRequirementDescriptor`.
///
/// `GenericRequirementDescriptor` is the per-requirement record carried in
/// the trailing `requirements` array of a generic context. The Suite
/// reads one descriptor per kind branch the parser exercises:
///   - layout (`A: AnyObject`)
///   - protocol Swift (`A: Equatable`)
///   - protocol ObjC (`A: NSCopying`)
///   - baseClass (`Element: GenericBaseClassForRequirementTest`)
///   - sameType (`First == Second`)
@Suite
final class GenericRequirementDescriptorTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "GenericRequirementDescriptor"
    static var registeredTestMethodNames: Set<String> {
        GenericRequirementDescriptorBaseline.registeredTestMethodNames
    }

    // MARK: - Helpers

    private func loadFirstRequirement(
        fromFile filePicker: (MachOFile) throws -> StructDescriptor,
        fromImage imagePicker: (MachOImage) throws -> StructDescriptor
    ) throws -> (file: GenericRequirementDescriptor, image: GenericRequirementDescriptor) {
        let fileDescriptor = try filePicker(machOFile)
        let imageDescriptor = try imagePicker(machOImage)
        let fileGenericCtx = try required(try fileDescriptor.typeGenericContext(in: machOFile))
        let imageGenericCtx = try required(try imageDescriptor.typeGenericContext(in: machOImage))
        let fileReq = try required(fileGenericCtx.currentRequirements.first)
        let imageReq = try required(imageGenericCtx.currentRequirements.first)
        return (file: fileReq, image: imageReq)
    }

    private func layoutRequirements() throws -> (file: GenericRequirementDescriptor, image: GenericRequirementDescriptor) {
        try loadFirstRequirement(
            fromFile: { try BaselineFixturePicker.struct_GenericStructLayoutRequirement(in: $0) },
            fromImage: { try BaselineFixturePicker.struct_GenericStructLayoutRequirement(in: $0) }
        )
    }

    private func swiftProtocolRequirements() throws -> (file: GenericRequirementDescriptor, image: GenericRequirementDescriptor) {
        try loadFirstRequirement(
            fromFile: { try BaselineFixturePicker.struct_GenericStructSwiftProtocolRequirement(in: $0) },
            fromImage: { try BaselineFixturePicker.struct_GenericStructSwiftProtocolRequirement(in: $0) }
        )
    }

    private func objcProtocolRequirements() throws -> (file: GenericRequirementDescriptor, image: GenericRequirementDescriptor) {
        try loadFirstRequirement(
            fromFile: { try BaselineFixturePicker.struct_GenericStructObjCProtocolRequirement(in: $0) },
            fromImage: { try BaselineFixturePicker.struct_GenericStructObjCProtocolRequirement(in: $0) }
        )
    }

    private func baseClassRequirements() throws -> (file: GenericRequirementDescriptor, image: GenericRequirementDescriptor) {
        try loadFirstRequirement(
            fromFile: { try BaselineFixturePicker.struct_BaseClassRequirementTest(in: $0) },
            fromImage: { try BaselineFixturePicker.struct_BaseClassRequirementTest(in: $0) }
        )
    }

    private func sameTypeRequirements() throws -> (file: GenericRequirementDescriptor, image: GenericRequirementDescriptor) {
        try loadFirstRequirement(
            fromFile: { try BaselineFixturePicker.struct_SameTypeRequirementTest(in: $0) },
            fromImage: { try BaselineFixturePicker.struct_SameTypeRequirementTest(in: $0) }
        )
    }

    // MARK: - Ivars

    @Test func offset() async throws {
        let layout = try layoutRequirements()
        let layoutOffset = try acrossAllReaders(file: { layout.file.offset }, image: { layout.image.offset })
        #expect(layoutOffset == GenericRequirementDescriptorBaseline.layoutRequirement.offset)

        let swift = try swiftProtocolRequirements()
        let swiftOffset = try acrossAllReaders(file: { swift.file.offset }, image: { swift.image.offset })
        #expect(swiftOffset == GenericRequirementDescriptorBaseline.swiftProtocolRequirement.offset)
    }

    @Test func layout() async throws {
        // Layout-level rawValue cross-reader equality on each fixture.
        let layout = try layoutRequirements()
        let layoutRaw = try acrossAllReaders(
            file: { layout.file.layout.flags.rawValue },
            image: { layout.image.layout.flags.rawValue }
        )
        #expect(layoutRaw == GenericRequirementDescriptorBaseline.layoutRequirement.flagsRawValue)

        let baseClass = try baseClassRequirements()
        let baseClassRaw = try acrossAllReaders(
            file: { baseClass.file.layout.flags.rawValue },
            image: { baseClass.image.layout.flags.rawValue }
        )
        #expect(baseClassRaw == GenericRequirementDescriptorBaseline.baseClassRequirement.flagsRawValue)

        let sameType = try sameTypeRequirements()
        let sameTypeRaw = try acrossAllReaders(
            file: { sameType.file.layout.flags.rawValue },
            image: { sameType.image.layout.flags.rawValue }
        )
        #expect(sameTypeRaw == GenericRequirementDescriptorBaseline.sameTypeRequirement.flagsRawValue)
    }

    // MARK: - Derived

    @Test func content() async throws {
        let layout = try layoutRequirements()
        let layoutKind = try acrossAllReaders(
            file: { describeContentKind(layout.file.content) },
            image: { describeContentKind(layout.image.content) }
        )
        #expect(layoutKind == GenericRequirementDescriptorBaseline.layoutRequirement.contentKindCase)

        let swift = try swiftProtocolRequirements()
        let swiftKind = try acrossAllReaders(
            file: { describeContentKind(swift.file.content) },
            image: { describeContentKind(swift.image.content) }
        )
        #expect(swiftKind == GenericRequirementDescriptorBaseline.swiftProtocolRequirement.contentKindCase)

        let objc = try objcProtocolRequirements()
        let objcKind = try acrossAllReaders(
            file: { describeContentKind(objc.file.content) },
            image: { describeContentKind(objc.image.content) }
        )
        #expect(objcKind == GenericRequirementDescriptorBaseline.objcProtocolRequirement.contentKindCase)

        let baseClass = try baseClassRequirements()
        let baseClassKind = try acrossAllReaders(
            file: { describeContentKind(baseClass.file.content) },
            image: { describeContentKind(baseClass.image.content) }
        )
        #expect(baseClassKind == GenericRequirementDescriptorBaseline.baseClassRequirement.contentKindCase)

        let sameType = try sameTypeRequirements()
        let sameTypeKind = try acrossAllReaders(
            file: { describeContentKind(sameType.file.content) },
            image: { describeContentKind(sameType.image.content) }
        )
        #expect(sameTypeKind == GenericRequirementDescriptorBaseline.sameTypeRequirement.contentKindCase)
    }

    // MARK: - Resolution methods

    @Test func paramMangledName() async throws {
        // The resolved MangledName payload is a parsed tree we don't embed
        // as a literal; cross-reader equality is meaningful on the parsed
        // result. MangledName is Hashable/Equatable so direct equality works.
        let layout = try layoutRequirements()
        let fileName = try layout.file.paramMangledName(in: machOFile)
        let imageName = try layout.image.paramMangledName(in: machOImage)
        let fileCtxName = try layout.file.paramMangledName(in: fileContext)
        let imageCtxName = try layout.image.paramMangledName(in: imageContext)

        #expect(fileName == imageName)
        #expect(fileName == fileCtxName)
        #expect(fileName == imageCtxName)
    }

    @Test func type() async throws {
        // `type(in:)` resolves the content as a MangledName for sameType /
        // baseClass / sameShape. The sameType requirement provides a clean
        // carrier.
        let sameType = try sameTypeRequirements()
        let fileType = try sameType.file.type(in: machOFile)
        let imageType = try sameType.image.type(in: machOImage)
        let fileCtxType = try sameType.file.type(in: fileContext)

        #expect(fileType == imageType)
        #expect(fileType == fileCtxType)
    }

    @Test func resolvedContent() async throws {
        let layout = try layoutRequirements()
        let fileResolved = try layout.file.resolvedContent(in: machOFile)
        let imageResolved = try layout.image.resolvedContent(in: machOImage)
        let fileCtxResolved = try layout.file.resolvedContent(in: fileContext)

        #expect(fileResolved == imageResolved)
        #expect(fileResolved == fileCtxResolved)
        #expect(describeResolvedKind(fileResolved) == GenericRequirementDescriptorBaseline.layoutRequirement.contentKindCase)
    }

    @Test func isContentEqual() async throws {
        // The descriptor offsets differ between MachOFile and MachOImage
        // readers; `isContentEqual(to:in:)` requires both descriptors to
        // be reachable through the supplied reader. We therefore exercise
        // each overload with same-reader inputs (a descriptor is content-
        // equal to itself).
        let layout = try layoutRequirements()
        #expect(layout.file.isContentEqual(to: layout.file, in: machOFile))
        #expect(layout.image.isContentEqual(to: layout.image, in: machOImage))
        #expect(layout.file.isContentEqual(to: layout.file, in: fileContext))
        #expect(layout.image.isContentEqual(to: layout.image, in: imageContext))
        // The InProcess overload reads via the descriptor's resolved
        // pointer — only the image-side descriptor carries a pointer-form
        // ivar set, so we exercise it from there.
        let imagePointerLeft = layout.image.asPointerWrapper(in: machOImage)
        let imagePointerRight = layout.image.asPointerWrapper(in: machOImage)
        #expect(imagePointerLeft.isContentEqual(to: imagePointerRight))
    }

    // MARK: - Private helpers

    private func describeContentKind(_ content: GenericRequirementContent) -> String {
        switch content {
        case .type: return "type"
        case .protocol: return "protocol"
        case .layout: return "layout"
        case .conformance: return "conformance"
        case .invertedProtocols: return "invertedProtocols"
        }
    }

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
