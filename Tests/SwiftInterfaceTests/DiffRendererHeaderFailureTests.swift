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

    private func preparedBuilder(
        eventHandlers: [SwiftIndexEvents.Handler] = []
    ) async throws -> SwiftDiffableInterfaceBuilder<MachOFile> {
        let unsafeMachOFile = machOFile
        let builder = SwiftDiffableInterfaceBuilder(eventHandlers: eventHandlers, in: unsafeMachOFile)
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

        let corruptDefinition = try makeUnrenderableDefinition(borrowingNameFrom: Self.addedOnlyDonorName, in: newBuilder)
        // A renderable grandchild, so the corrupt definition's body is not empty.
        let grandchildDonor = try #require(findTypeDefinition(named: "StructTest", in: newBuilder))
        corruptDefinition.typeChildren.append(grandchildDonor)

        let hostDefinition = try #require(findTypeDefinition(named: "Classes", in: newBuilder))
        try requireAbsentFromHost(Self.addedOnlyDonorName, host: hostDefinition)
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

        let corruptDefinition = try makeUnrenderableDefinition(borrowingNameFrom: Self.addedOnlyDonorName, in: newBuilder)
        let hostDefinition = try #require(findTypeDefinition(named: "Classes", in: newBuilder))
        try requireAbsentFromHost(Self.addedOnlyDonorName, host: hostDefinition)
        hostDefinition.typeChildren.append(corruptDefinition)

        let renderer = SwiftDiffableInterfaceRenderer(old: oldBuilder, new: newBuilder)
        let output = await renderer.printAnnotatedInterface().string

        #expect(output.contains("Classes"), "the enclosing type must keep rendering")
    }

    /// Dropping the declaration is right; dropping it **silently** is not.
    ///
    /// The renderer now builds each printer with its indexer's dispatcher, so the
    /// handlers the host passed to the builder cover printing too. Previously the
    /// printers were built with `.init(in:)` and had no sink at all, which is why
    /// this was once asserted by capturing stderr.
    ///
    /// The event carries the declaration's NAME. The old stderr line named
    /// nothing, so an operator could tell that something had vanished but not
    /// what — which is most of what makes such a report actionable.
    @Test func unrenderableHeaderIsReportedAsAnEvent() async throws {
        let collector = SwiftIndexEventCollector()
        let oldBuilder = try await preparedBuilder()
        let newBuilder = try await preparedBuilder(eventHandlers: [collector])

        let corruptDefinition = try makeUnrenderableDefinition(borrowingNameFrom: "FinalClassTest", in: newBuilder)
        let hostDefinition = try #require(findTypeDefinition(named: "Classes", in: newBuilder))
        hostDefinition.typeChildren.append(corruptDefinition)

        let renderer = SwiftDiffableInterfaceRenderer(old: oldBuilder, new: newBuilder)
        _ = await renderer.printAnnotatedInterface().string

        #expect(
            collector.printFailureNames.contains { $0.hasSuffix("FinalClassTest") },
            "an unrenderable header must be reported through the event stream, naming the declaration that was dropped; got \(collector.printFailureNames)"
        )
    }

    /// The two-sided case, which is the routine one when diffing two versions of
    /// a binary and the one the drop-whole contract must NOT swallow.
    ///
    /// `renderType` used to read
    /// `guard let old = await header(...), let new = await header(...)`. Guard
    /// clauses short-circuit, so a failure on the OLD side never even attempted
    /// the new side, and returning `[]` deleted the declaration, its members and
    /// every nested child from BOTH sides — while the old binary's copy really
    /// was unrenderable, the new binary's copy was perfectly fine.
    ///
    /// One renderable side is enough to print a valid declaration line, so the
    /// surviving side stands in and the member diff below it lives. Injecting on
    /// the OLD side only is what distinguishes this from the `.added` cases
    /// above, where dropping IS correct.
    @Test func unrenderableHeaderOnOneSideKeepsTheOtherSide() async throws {
        let collector = SwiftIndexEventCollector()
        let oldBuilder = try await preparedBuilder(eventHandlers: [collector])
        let newBuilder = try await preparedBuilder()

        // REPLACE the old side's copy rather than appending a second one:
        // `matchByKey` is first-wins, so an appended duplicate never gets
        // matched and the corrupt definition would simply be ignored. Replacing
        // keeps one entry per side under the same key, which is what puts the
        // renderer on its two-sided `.unchanged` path. The new side keeps its
        // intact copy untouched.
        let oldHost = try #require(findTypeDefinition(named: "Classes", in: oldBuilder))
        let replacedIndex = try #require(
            oldHost.typeChildren.firstIndex { $0.typeName.currentName == "FinalClassTest" },
            "fixture must nest FinalClassTest inside Classes for this test to exercise the two-sided path"
        )
        oldHost.typeChildren[replacedIndex] = try makeUnrenderableDefinition(borrowingNameFrom: "FinalClassTest", in: oldBuilder)

        let renderer = SwiftDiffableInterfaceRenderer(old: oldBuilder, new: newBuilder)
        let output = await renderer.printAnnotatedInterface().string

        #expect(
            output.contains("FinalClassTest"),
            "a header that fails on ONE side must not delete the declaration from the other side too"
        )
        #expect(
            collector.printFailureNames.contains { $0.hasSuffix("FinalClassTest") },
            "the side that could not be rendered must still be reported; got \(collector.printFailureNames)"
        )
    }

    /// A real struct descriptor's layout re-wrapped at an offset far past the
    /// fixture's end of file: every relative resolve the header materialization
    /// performs is out of bounds and throws deterministically.
    ///
    /// The borrowed name decides which diff path the injection exercises, so
    /// callers pass it explicitly. A name already nested under the host matches
    /// the other side's real copy and takes the two-sided path; a name from
    /// elsewhere has no counterpart and takes `.added`.
    private func makeUnrenderableDefinition(
        borrowingNameFrom donorName: String,
        in builder: SwiftDiffableInterfaceBuilder<MachOFile>
    ) throws -> TypeDefinition {
        let realStructDefinition = try #require(findTypeDefinition(named: "GenericStructNonRequirement", in: builder))
        guard case .struct(let realStructDescriptor) = realStructDefinition.typeContextDescriptorWrapper else {
            throw UnrenderableDefinitionError.donorIsNotAStruct
        }
        let unreadableDescriptor = StructDescriptor(layout: realStructDescriptor.layout, offset: 0x0FFF_FFF0)
        let donorDefinition = try #require(findTypeDefinition(named: donorName, in: builder))
        return TypeDefinition(
            typeContextDescriptorWrapper: .struct(unreadableDescriptor),
            typeName: donorDefinition.typeName,
            isSpecialized: false
        )
    }

    /// A type that is NOT nested under `Classes`, so injecting a definition
    /// under its name puts the renderer on the `.added` path — the only side
    /// where dropping the whole declaration is the correct outcome.
    private static let addedOnlyDonorName = "GenericStructNonRequirement"

    /// Injecting a name the host already carries would silently change which
    /// path the test exercises: `matchByKey` would pair the injected definition
    /// with the other side's real copy and take the two-sided route instead.
    /// Assert the premise rather than trust the fixture to hold still.
    private func requireAbsentFromHost(_ name: String, host: TypeDefinition) throws {
        try #require(
            !host.typeChildren.contains { $0.typeName.currentName == name },
            "\(name) must not already be nested under the host, or this test silently stops covering the `.added` path"
        )
    }

    private enum UnrenderableDefinitionError: Error {
        case donorIsNotAStruct
    }
}
