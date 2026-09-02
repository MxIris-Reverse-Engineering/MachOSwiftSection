import Foundation
import Testing
import MachOKit
@_spi(Internals) @testable import MachOSymbols
@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftPrinting
@_spi(Support) @testable import SwiftInterface
@testable import MachOTestingSupport
import MachOFixtureSupport

/// End-to-end coverage for the exported-only filter (evolution proposal
/// `exported-only-interface`) on the `SymbolTestsCore` fixture — a
/// library-evolution Release build with `ENABLE_TESTABILITY`, so its
/// `internal` declarations ARE exported and only `private` ones are not.
/// That makes it the right fixture for the declaration-level rules
/// (private types / protocols / their extensions) and the member rule's
/// three exemptions; the `internal` shapes are pinned separately by
/// `ExportedOnlyLibraryEvolutionFixtureTests` on a compile-on-the-fly module.
///
/// Every negative assertion is paired with the same assertion against the
/// DEFAULT output, so "absent" provably means "dropped by the filter" and not
/// "never rendered in the first place".
@Suite(.serialized)
final class ExportedOnlyInterfaceTests: MachOFileTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SymbolTestsCore }

    private func buildOutput(exportedOnly: Bool, annotate: Bool = false) async throws -> String {
        var printConfiguration = SwiftDeclarationPrintConfiguration()
        printConfiguration.printExportedDeclarationsOnly = exportedOnly
        printConfiguration.printExportStatus = annotate
        let configuration = SwiftInterfaceBuilderConfiguration(
            indexConfiguration: .init(showCImportedTypes: false),
            printConfiguration: printConfiguration
        )
        let unsafeMachOFile = machOFile
        let builder = try SwiftInterfaceBuilder(configuration: configuration, eventHandlers: [], in: unsafeMachOFile)
        try await builder.prepare()
        return try await builder.printRoot().string
    }

    /// A top-level `private struct`: its nominal type descriptor is a local
    /// symbol, so the whole declaration goes — while the `public enum` anchor
    /// declared in the same file stays.
    @Test func privateTypeIsDropped() async throws {
        let unsafeMachOFile = machOFile
        let descriptorName = "_$s15SymbolTestsCore19PrivateDoppelganger33_1282F137F8790A6AF4B7E2738A640142LLVMn"
        #expect(SymbolIndexStore.shared.isExported(name: descriptorName, in: unsafeMachOFile) == false)

        let defaultOutput = try await buildOutput(exportedOnly: false)
        #expect(defaultOutput.contains("struct PrivateDoppelganger {"))

        let filteredOutput = try await buildOutput(exportedOnly: true)
        #expect(!filteredOutput.contains("struct PrivateDoppelganger {"))
        #expect(!filteredOutput.contains("class PrivateDoppelgangerClass {"))
        #expect(filteredOutput.contains("enum PrivateDoppelgangerFirstFileAnchors {"))
    }

    /// A `private protocol` goes by its protocol descriptor, and the
    /// protocol-extension default implementations attached to it (rendered
    /// trailing the declaration, evolution proposal 0007) go with it.
    @Test func privateProtocolAndItsDefaultImplementationsAreDropped() async throws {
        let unsafeMachOFile = machOFile
        let descriptorName = "_$s15SymbolTestsCore27PrivateDoppelgangerProtocol33_1282F137F8790A6AF4B7E2738A640142LLMp"
        #expect(SymbolIndexStore.shared.isExported(name: descriptorName, in: unsafeMachOFile) == false)

        let defaultOutput = try await buildOutput(exportedOnly: false)
        #expect(defaultOutput.contains("protocol PrivateDoppelgangerProtocol {"))
        #expect(defaultOutput.contains("var alphaDefaultProperty: Swift.Int64 {"))

        let filteredOutput = try await buildOutput(exportedOnly: true)
        #expect(!filteredOutput.contains("protocol PrivateDoppelgangerProtocol {"))
        #expect(!filteredOutput.contains("extension SymbolTestsCore.PrivateDoppelgangerProtocol {"))
        #expect(!filteredOutput.contains("alphaDefaultProperty"))
    }

    /// A conformance extension whose target is a private type — an
    /// extension owns no descriptor symbol, so the verdict comes from the
    /// installed `ExportFilterScope`'s in-image tables.
    @Test func conformanceExtensionOfPrivateTypeIsDropped() async throws {
        let conformanceHeader = "extension SymbolTestsCore.AlphaProtocolWitness: SymbolTestsCore.PrivateDoppelgangerProtocol {}"
        let defaultOutput = try await buildOutput(exportedOnly: false)
        #expect(defaultOutput.contains(conformanceHeader))

        let filteredOutput = try await buildOutput(exportedOnly: true)
        #expect(!filteredOutput.contains(conformanceHeader))
        #expect(!filteredOutput.contains("AlphaProtocolWitness"))
    }

    /// A private type NESTED in a public one drops alone: the parent and its
    /// public sibling stay, and so does nothing of the nested type's
    /// conformance extensions (their target is the dropped nested type).
    @Test func nestedPrivateTypeIsDroppedWhileParentStays() async throws {
        let unsafeMachOFile = machOFile
        let descriptorName = "_$s15SymbolTestsCore7StructsO19PrivateProtocolTest33_930E68B58AC9D850D1A6B7A3A1786E37LLOMn"
        #expect(SymbolIndexStore.shared.isExported(name: descriptorName, in: unsafeMachOFile) == false)

        let defaultOutput = try await buildOutput(exportedOnly: false)
        #expect(defaultOutput.contains("    enum PrivateProtocolTest {"))
        #expect(defaultOutput.contains("extension SymbolTestsCore.Structs.PrivateProtocolTest: Swift.Hashable {"))

        let filteredOutput = try await buildOutput(exportedOnly: true)
        #expect(filteredOutput.contains("enum Structs {"))
        #expect(filteredOutput.contains("    struct StructTest {"))
        #expect(!filteredOutput.contains("enum PrivateProtocolTest {"))
        #expect(!filteredOutput.contains("extension SymbolTestsCore.Structs.PrivateProtocolTest"))
    }

    /// The regression the descriptor-offset leg exists for: a public type
    /// nested in a CONSTRAINED extension mangles only the extension's own
    /// requirement into its context (`…VAASYRzrlE28RawRepresentableNestedStructVMn`),
    /// while the model's name node carries the type's full signature — a
    /// remangled name misses the trie and the first implementation dropped
    /// this exported type. The verdict must come from the symbol AT the
    /// descriptor, which spells the name the compiler's way.
    @Test func publicTypeNestedInConstrainedExtensionIsKept() async throws {
        let unsafeMachOFile = machOFile
        let descriptorName = "_$s15SymbolTestsCore8GenericsO22GenericRequirementTestVAASYRzrlE28RawRepresentableNestedStructVMn"
        #expect(SymbolIndexStore.shared.isExported(name: descriptorName, in: unsafeMachOFile) == true)

        let filteredOutput = try await buildOutput(exportedOnly: true)
        #expect(filteredOutput.contains("struct RawRepresentableNestedStruct {"))
    }

    /// The member rule: `GenericAsyncSequenceTest.AsyncIterator`'s implicit
    /// `init()` is `internal` with no exported form (the true positive of
    /// `ExportStatusAnnotationTests`), so it goes — while the struct that
    /// declares it stays with its exported `next()`.
    @Test func nonExportedMemberIsDroppedWhileItsTypeStays() async throws {
        let filteredOutput = try await buildOutput(exportedOnly: true)
        let typeBlock = try #require(filteredOutput.range(of: "struct GenericAsyncSequenceTest"))
        let iteratorBlock = try #require(filteredOutput.range(of: "struct AsyncIterator {", range: typeBlock.upperBound ..< filteredOutput.endIndex))
        let lines = filteredOutput[iteratorBlock.upperBound...].split(separator: "\n", omittingEmptySubsequences: false)
        let closingIndex = lines.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "}" } ?? lines.endIndex
        let blockLines = lines[..<closingIndex].map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(!blockLines.contains("init()"))
        #expect(blockLines.contains { $0.hasPrefix("func next()") })
    }

    /// Top-level globals go through `printRoot`'s own blocks, not
    /// `renderMember`, so the filter is applied there explicitly.
    @Test func nonExportedGlobalIsDropped() async throws {
        let globalDeclaration = "func getContiguousArrayStorageType<A>(for: A.Type)"
        let defaultOutput = try await buildOutput(exportedOnly: false)
        #expect(defaultOutput.contains(globalDeclaration))

        let filteredOutput = try await buildOutput(exportedOnly: true)
        #expect(!filteredOutput.contains(globalDeclaration))
    }

    /// The three shapes the annotation never flags are the three shapes the
    /// filter never drops: a member reachable only through its exported `Tj`
    /// thunk, an `@objc dynamic` member, and an `override`. Premises are
    /// asserted through the store first, exactly as in
    /// `ExportStatusAnnotationTests`, so "kept" is the exemption's doing.
    @Test func thunkExportedObjCAndOverrideMembersAreKept() async throws {
        let unsafeMachOFile = machOFile
        #expect(SymbolIndexStore.shared.isExported(name: "_$s15SymbolTestsCore6ActorsO9ActorTestC11mutateStateyyF", in: unsafeMachOFile) == false)
        #expect(SymbolIndexStore.shared.isExportedIncludingDerivedSymbols(name: "_$s15SymbolTestsCore6ActorsO9ActorTestC11mutateStateyyF", in: unsafeMachOFile) == true)
        #expect(SymbolIndexStore.shared.isExportedIncludingDerivedSymbols(name: "_$s15SymbolTestsCore10AttributesO18ObjCAttributeClassC17objcDynamicMethodyyF", in: unsafeMachOFile) == false)
        #expect(SymbolIndexStore.shared.isExportedIncludingDerivedSymbols(name: "_$s15SymbolTestsCore7ClassesO25ExternalSwiftSubclassTestC14instanceMethodSSyF", in: unsafeMachOFile) == false)

        let filteredOutput = try await buildOutput(exportedOnly: true)
        #expect(filteredOutput.contains("func mutateState()"))
        #expect(filteredOutput.contains("@objc func objcDynamicMethod()"))
        #expect(filteredOutput.contains("override func instanceMethod() -> Swift.String"))
    }

    /// A conformance extension is kept even when the filter empties it: a
    /// synthesized `Equatable`'s `==` witness is not statically callable
    /// (proposal 0008 deliberately does not exempt witnesses), so the body
    /// collapses to `{}` — the same shape a `.swiftinterface` prints for a
    /// synthesized conformance — and the conformance clause itself remains.
    @Test func emptiedConformanceExtensionKeepsItsClause() async throws {
        let defaultOutput = try await buildOutput(exportedOnly: false)
        #expect(defaultOutput.contains("extension SymbolTestsCore.Enums.RawValueEnumTest: Swift.Equatable {\n"))

        let filteredOutput = try await buildOutput(exportedOnly: true)
        #expect(filteredOutput.contains("extension SymbolTestsCore.Enums.RawValueEnumTest: Swift.Equatable {}"))
    }

    /// The filter's drop condition IS the annotation's emit condition, so
    /// with both flags on the output carries zero `not exported` comments —
    /// a structural invariant, not a fixture coincidence.
    @Test func filteredOutputCarriesNoAnnotation() async throws {
        let annotatedOutput = try await buildOutput(exportedOnly: false, annotate: true)
        #expect(annotatedOutput.contains("// not exported"))

        let filteredOutput = try await buildOutput(exportedOnly: true, annotate: true)
        #expect(!filteredOutput.contains("// not exported"))
    }

    /// Dropped definitions render as EMPTY results that every `BlockList` /
    /// `NestedDeclaration` skips outright — no orphaned separator breaks.
    @Test func filteredOutputHasNoBlankLineArtifacts() async throws {
        let filteredOutput = try await buildOutput(exportedOnly: true)
        #expect(!filteredOutput.contains("\n\n\n"))
        #expect(!filteredOutput.contains("{\n}"))
    }

    /// Flag off (the default): byte-identical to a builder that never heard
    /// of the filter.
    @Test func defaultOutputIsUnchanged() async throws {
        let defaultOutput = try await buildOutput(exportedOnly: false)
        let unsafeMachOFile = machOFile
        let builder = try SwiftInterfaceBuilder(configuration: .init(indexConfiguration: .init(showCImportedTypes: false)), eventHandlers: [], in: unsafeMachOFile)
        try await builder.prepare()
        let untouchedOutput = try await builder.printRoot().string
        #expect(defaultOutput == untouchedOutput)
    }
}
