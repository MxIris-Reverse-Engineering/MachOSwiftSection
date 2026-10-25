import Foundation
import Testing
import MachOTestingSupport
import SwiftSectionKit

/// `dump` and `interface` naming the source file of each private declaration
/// (evolution proposal `private-declaration-source-files`).
///
/// The files' discriminators were computed outside this code base, with
/// `md5 -s` over the module name followed by the file name:
/// `SymbolTestsCoreCodable.swift` is `b89e435d…`, `SymbolTestsCoreStructs.swift`
/// `930e68b5…`, `SymbolTestsCorePrivateDoppelgangers.swift` `82f1a700…`,
/// `SymbolTestsCorePrivateDoppelgangersSecondFile.swift` `1282f137…` — a name
/// no candidate spells, its plural sitting inside it — and
/// `LocalTypeFixtureUnstrippedFixture.swift` `2ea5a000…`.
@Suite
struct PrivateDeclarationSourceFileRequestTests {
    private static let symbolTestsCore = MachOSource.file(path: FixtureFiles.symbolTestsCore, architecture: nil)

    /// One dump of the fixture with the option, which the tests reading it
    /// share: indexing the image and searching its discriminators is what
    /// takes the time.
    private static let symbolTestsCoreDump = Task { try await dump(symbolTestsCore) }

    private static func dump(_ source: MachOSource, emitsPrivateDeclarationSourceFiles: Bool = true) async throws -> String {
        let output = RecordingOutput()
        try await DumpRequest(source: source, emitsPrivateDeclarationSourceFiles: emitsPrivateDeclarationSourceFiles).run(output: output, environment: .testing)
        return output.printedProduct
    }

    /// The line right above the first one that, its indentation left out,
    /// starts with `prefix`; also without its indentation.
    private static func line(above prefix: String, in product: String) -> String? {
        let lines = product.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let index = lines.firstIndex(where: { $0.hasPrefix(prefix) }), index > 0 else { return nil }
        return lines[index - 1]
    }

    // MARK: - dump

    @Test("dump names the file above a private type")
    func dumpNamesTheFileOfAPrivateType() async throws {
        let product = try await Self.symbolTestsCoreDump.value
        #expect(Self.line(above: "enum SymbolTestsCore.CodableTests.GenericCodableTest.(CodingKeys in _B89E435DF71E951D297EEE1ADCD6DDD8) {", in: product) == "// CodingKeys is declared in Codable.swift")
    }

    /// Two files each declare a `private struct PrivateDoppelganger`; the
    /// second file's name is one no candidate spells.
    @Test("dump tells same-named private types apart, and says when a file could not be recovered")
    func dumpTellsSameNamedPrivateTypesApart() async throws {
        let product = try await Self.symbolTestsCoreDump.value
        #expect(Self.line(above: "struct SymbolTestsCore.(PrivateDoppelganger in _82F1A700CE81FEBE6E5E3FC5D7722250) {", in: product) == "// PrivateDoppelganger is declared in PrivateDoppelgangers.swift")
        #expect(Self.line(above: "struct SymbolTestsCore.(PrivateDoppelganger in _1282F137F8790A6AF4B7E2738A640142) {", in: product) == "// PrivateDoppelganger is declared in a source file whose name could not be recovered (private discriminator _1282F137F8790A6AF4B7E2738A640142)")
    }

    @Test("dump names the file above a private protocol and above a conformance of a private type")
    func dumpNamesTheFileOfAPrivateProtocolAndConformance() async throws {
        let product = try await Self.symbolTestsCoreDump.value
        #expect(Self.line(above: "protocol SymbolTestsCore.(PrivateDoppelgangerProtocol in _82F1A700CE81FEBE6E5E3FC5D7722250)", in: product) == "// PrivateDoppelgangerProtocol is declared in PrivateDoppelgangers.swift")
        #expect(Self.line(above: "extension SymbolTestsCore.Structs.(PrivateProtocolTest in _930E68B58AC9D850D1A6B7A3A1786E37): Swift.Hashable {", in: product) == "// PrivateProtocolTest is declared in Structs.swift")
    }

    /// The fixture's private declarations are all types, so every member
    /// that reads a discriminator is a member of one.
    @Test("dump does not repeat a private type's file on its members")
    func dumpDoesNotRepeatTheFileOnMembersOfAPrivateType() async throws {
        let product = try await Self.symbolTestsCoreDump.value
        #expect(Self.line(above: "SymbolTestsCore.CodableTests.GenericCodableTest.(CodingKeys in _B89E435DF71E951D297EEE1ADCD6DDD8).stringValue.getter", in: product)?.hasPrefix("//") == false)
    }

    @Test("dump only adds comment lines, and adds none without the option")
    func dumpOnlyAddsCommentLines() async throws {
        let withSourceFiles = try await Self.symbolTestsCoreDump.value
        let withoutSourceFiles = try await Self.dump(Self.symbolTestsCore, emitsPrivateDeclarationSourceFiles: false)
        let sourceFileLines = withSourceFiles.components(separatedBy: "\n").filter { $0.contains(" is declared in ") }
        #expect(!sourceFileLines.isEmpty)
        #expect(!withoutSourceFiles.contains(" is declared in "))
        #expect(withSourceFiles.components(separatedBy: "\n").filter { !$0.contains(" is declared in ") } == withoutSourceFiles.components(separatedBy: "\n"))
    }

    /// `Holder` is public; its `private func hiddenValues()` says where it is,
    /// and so does the type declared in that method, whose name runs through
    /// it.
    @Test("dump names the file of a public type's private member", ExclusiveImageAccess(LocalTypeFixture.exclusiveAccessName))
    func dumpNamesTheFileOfAPrivateMember() async throws {
        let source = MachOSource.file(path: try LocalTypeFixture.libraryURL(.unstripped).path, architecture: nil)
        let product = try await Self.dump(source)
        #expect(Self.line(above: "LocalTypeFixtureUnstripped.Holder.(hiddenValues in _2EA5A000E301E8E89BE43D5FB26A4D0E)() -> Any", in: product) == "// hiddenValues is declared in Fixture.swift")
        let hiddenTypeLine = try #require(product.components(separatedBy: "\n").first { $0.hasPrefix("struct ") && $0.contains("Hidden #1") })
        #expect(Self.line(above: hiddenTypeLine, in: product) == "// hiddenValues is declared in Fixture.swift")
    }
}
