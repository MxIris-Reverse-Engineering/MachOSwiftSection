@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
@_spi(Support) @testable import SwiftPrinting
@_spi(Support) @testable import SwiftInterface
import Foundation
import Testing
import MachOKit
import Dependencies
@_spi(Internals) import MachOSymbols
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// The diff renderer's header contract: a declaration whose HEADER cannot be
/// rendered must be dropped whole, never rendered as a body under a blank
/// header line.
///
/// `renderType` / `renderProtocol` compute their body units unconditionally and
/// hand them to `DiffContainerAssembler` together with the header. While
/// `header(_:_:)` swallowed a throw into an empty `SemanticString`, that
/// produced a type's members and braces with NO `struct Foo` / `protocol Foo`
/// line above them — structurally invalid Swift, emitted silently, with no
/// event and no error.
///
/// Header rendering can genuinely throw: it reads the declaration's name,
/// generic signature and superclass and demangles each (issue #102 is the field
/// evidence that print-time `DemanglingError`s occur on real binaries), and
/// since evolution 0002 it also re-materializes the wrapper from its
/// descriptor.
@Suite(.serialized)
final class DiffRendererHeaderFailureTests: MachOFileTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SymbolTestsCore }

    private func preparedBuilder() async throws -> SwiftDiffableInterfaceBuilder<MachOFile> {
        let unsafeMachOFile = machOFile
        let builder = SwiftDiffableInterfaceBuilder(in: unsafeMachOFile)
        try await builder.prepare()
        return builder
    }

    private func findTypeDefinition(
        named name: String,
        in builder: SwiftDiffableInterfaceBuilder<MachOFile>
    ) -> TypeDefinition? {
        builder.indexer.allTypeDefinitions.values.first { $0.typeName.currentName == name }
    }

    /// Injecting a type whose header cannot be rendered must not add a single
    /// character to the annotated interface.
    ///
    /// The injected child carries a real, renderable grandchild, so its BODY is
    /// non-empty — that is what makes the assertion sharp. Before the fix the
    /// blank header was assembled together with that body, so the grandchild's
    /// declaration appeared in the output an extra time under no header of its
    /// own; the rendered output therefore grew. After the fix the whole child
    /// is dropped and the output is byte-identical to the un-injected run.
    @Test func unrenderableTypeHeaderDropsTheWholeDeclaration() async throws {
        let oldBuilder = try await preparedBuilder()
        let newBuilder = try await preparedBuilder()

        let renderer = SwiftDiffableInterfaceRenderer(old: oldBuilder, new: newBuilder)
        let outputBeforeInjection = await renderer.printAnnotatedInterface().string

        // A real struct descriptor's layout re-wrapped at an offset far past
        // the fixture's end of file: every relative resolve the header
        // materialization performs is out of bounds and throws deterministically.
        let realStructDefinition = try #require(findTypeDefinition(named: "GenericStructNonRequirement", in: newBuilder))
        guard case .struct(let realStructDescriptor) = realStructDefinition.typeContextDescriptorWrapper else {
            Issue.record("GenericStructNonRequirement is expected to be a struct")
            return
        }
        let unreadableDescriptor = StructDescriptor(layout: realStructDescriptor.layout, offset: 0x0FFF_FFF0)

        let donorDefinition = try #require(findTypeDefinition(named: "FinalClassTest", in: newBuilder))
        let corruptDefinition = TypeDefinition(
            typeContextDescriptorWrapper: .struct(unreadableDescriptor),
            typeName: donorDefinition.typeName,
            isSpecialized: false
        )
        // A renderable grandchild, so the corrupt definition's body is not empty.
        let grandchildDonor = try #require(findTypeDefinition(named: "StructTest", in: newBuilder))
        corruptDefinition.typeChildren.append(grandchildDonor)

        let hostDefinition = try #require(findTypeDefinition(named: "Classes", in: newBuilder))
        hostDefinition.typeChildren.append(corruptDefinition)

        let outputAfterInjection = await renderer.printAnnotatedInterface().string

        #expect(
            outputAfterInjection == outputBeforeInjection,
            "a type whose header cannot be rendered must be dropped whole — its body must not be emitted under a blank header line"
        )
    }

    /// The companion property, stated positively: the un-renderable header must
    /// not silently truncate its ENCLOSING declaration either. The host type
    /// keeps rendering; only the injected child disappears.
    @Test func unrenderableChildHeaderKeepsItsEnclosingType() async throws {
        let oldBuilder = try await preparedBuilder()
        let newBuilder = try await preparedBuilder()

        let realStructDefinition = try #require(findTypeDefinition(named: "GenericStructNonRequirement", in: newBuilder))
        guard case .struct(let realStructDescriptor) = realStructDefinition.typeContextDescriptorWrapper else {
            Issue.record("GenericStructNonRequirement is expected to be a struct")
            return
        }
        let unreadableDescriptor = StructDescriptor(layout: realStructDescriptor.layout, offset: 0x0FFF_FFF0)

        let donorDefinition = try #require(findTypeDefinition(named: "FinalClassTest", in: newBuilder))
        let corruptDefinition = TypeDefinition(
            typeContextDescriptorWrapper: .struct(unreadableDescriptor),
            typeName: donorDefinition.typeName,
            isSpecialized: false
        )

        let hostDefinition = try #require(findTypeDefinition(named: "Classes", in: newBuilder))
        hostDefinition.typeChildren.append(corruptDefinition)

        let renderer = SwiftDiffableInterfaceRenderer(old: oldBuilder, new: newBuilder)
        let output = await renderer.printAnnotatedInterface().string

        #expect(output.contains("Classes"), "the enclosing type must keep rendering")
    }
}
