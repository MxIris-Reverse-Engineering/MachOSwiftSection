import Foundation
import Testing
import Demangling
import SwiftInspection
@testable import SwiftDeclarationRendering

/// The comments dump and interface print above a declaration to say which
/// source files its private declarations come from (evolution proposal
/// `private-declaration-source-files`).
///
/// The `SymbolTestsCore` manglings are the fixture's own symbols; `md5 -s
/// 'SymbolTestsCoreCodable.swift'`, computed outside this code base, is
/// `b89e435df71e951d297eee1adcd6ddd8`. The `Main` ones are written for these
/// tests — no source declares a type with two discriminators, but a
/// specialized definition's name reads its arguments' — and `swift-demangle`
/// prints them as the comments above them say.
@Suite
struct PrivateDeclarationSourceFileCommentsTests {
    private static let codableDiscriminator = "_B89E435DF71E951D297EEE1ADCD6DDD8"

    private static let firstDiscriminator = "_0123456789ABCDEF0123456789ABCDEF"

    private static let secondDiscriminator = "_FEDCBA9876543210FEDCBA9876543210"

    /// The answers of a recovery done elsewhere; one it has none for was not
    /// recovered.
    private struct RecoveredSourceFiles: PrivateDeclarationSourceFileProviding {
        let sourceFileByDiscriminator: [String: PrivateDeclarationSourceFile]

        func sourceFile(forPrivateDiscriminator discriminator: String) -> PrivateDeclarationSourceFile? {
            sourceFileByDiscriminator[discriminator]
        }
    }

    private static let recoveredSourceFiles = RecoveredSourceFiles(sourceFileByDiscriminator: [
        codableDiscriminator: .init(fileName: "Codable.swift", moduleName: "SymbolTestsCore", isSynthesized: false),
        firstDiscriminator: .init(fileName: "Box.swift", moduleName: "Main", isSynthesized: false),
        secondDiscriminator: .init(fileName: "Payload.swift", moduleName: "Main", isSynthesized: false),
    ])

    private static func lines(for mangledNames: [String], enclosedBy enclosingMangledName: String? = nil) throws -> [String] {
        let nodes: [any DemanglingNode] = try mangledNames.map { try demangleAsNodeTransient($0) }
        let enclosingNodes: [any DemanglingNode] = try enclosingMangledName.map { [try demangleAsNodeTransient($0)] } ?? []
        return PrivateDeclarationSourceFileComments.lines(for: nodes, enclosedBy: enclosingNodes, provider: recoveredSourceFiles)
    }

    // MARK: - Wording

    @Test func recoveredFileIsNamed() {
        let line = PrivateDeclarationSourceFileComments.line(
            for: PrivateDeclaration(name: "CodingKeys", discriminator: Self.codableDiscriminator),
            sourceFile: .init(fileName: "Codable.swift", moduleName: "SymbolTestsCore", isSynthesized: false),
            printedModuleName: "SymbolTestsCore"
        )
        #expect(line == "CodingKeys is declared in Codable.swift")
    }

    /// SwiftUICore's declarations print under their ABI module name, SwiftUI,
    /// while the digest was made with the framework's own.
    @Test func hashedModuleIsNamedWhenTheDeclarationPrintsUnderAnother() {
        let line = PrivateDeclarationSourceFileComments.line(
            for: PrivateDeclaration(name: "EnabledKey", discriminator: "_09CE35833F3876FE3A3A46977D61FC64"),
            sourceFile: .init(fileName: "Enabled.swift", moduleName: "SwiftUICore", isSynthesized: false),
            printedModuleName: "SwiftUI"
        )
        #expect(line == "EnabledKey is declared in Enabled.swift of module SwiftUICore")
    }

    @Test func synthesizedFileIsNamedAfterTheFileItWasMadeFor() {
        let line = PrivateDeclarationSourceFileComments.line(
            for: PrivateDeclaration(name: "Storage", discriminator: Self.firstDiscriminator),
            sourceFile: .init(fileName: "Box.swift", moduleName: "Main", isSynthesized: true),
            printedModuleName: "Main"
        )
        #expect(line == "Storage is declared in the file the compiler synthesized for Box.swift")
    }

    /// The interface prints no discriminator anywhere else, so this line is
    /// the only place a reader finds it.
    @Test func unrecoveredFileIsSaidSoWithTheDiscriminator() {
        let line = PrivateDeclarationSourceFileComments.line(
            for: PrivateDeclaration(name: "PrivateDoppelganger", discriminator: "_1282F137F8790A6AF4B7E2738A640142"),
            sourceFile: nil,
            printedModuleName: "SymbolTestsCore"
        )
        #expect(line == "PrivateDoppelganger is declared in a source file whose name could not be recovered (private discriminator _1282F137F8790A6AF4B7E2738A640142)")
    }

    @Test func declarationWithoutANameIsLeftUnnamed() {
        let line = PrivateDeclarationSourceFileComments.line(
            for: PrivateDeclaration(name: nil, discriminator: Self.firstDiscriminator),
            sourceFile: .init(fileName: "Box.swift", moduleName: "Main", isSynthesized: false),
            printedModuleName: "Main"
        )
        #expect(line == "Declared in Box.swift")
    }

    // MARK: - Which discriminators get a line

    @Test func privateTypeGetsALine() throws {
        // nominal type descriptor for SymbolTestsCore.CodableTests.GenericCodableTest.(CodingKeys in _B89E…)
        #expect(try Self.lines(for: ["$s15SymbolTestsCore12CodableTestsO07GenericC4TestV10CodingKeys33_B89E435DF71E951D297EEE1ADCD6DDD8LLOMn"]) == [
            "CodingKeys is declared in Codable.swift",
        ])
    }

    /// The type a nested private type is declared in reads the same
    /// discriminator: one line, naming the type the declaration is.
    @Test func oneDiscriminatorGetsOneLineNamingTheLastDeclarationReadWithIt() throws {
        // Main.(Holder in _0123…).(Inner in _0123…)
        #expect(try Self.lines(for: ["$s4Main6Holder33_0123456789ABCDEF0123456789ABCDEFLLV5Inner33_0123456789ABCDEF0123456789ABCDEFLLVD"]) == [
            "Inner is declared in Box.swift",
        ])
    }

    @Test func eachDiscriminatorGetsALineInTheOrderTheNameReadsThem() throws {
        // Main.(Box in _0123…)<Main.(P in _FEDC…)>
        #expect(try Self.lines(for: ["$s4Main3Box33_0123456789ABCDEF0123456789ABCDEFLLVyAA1P33_FEDCBA9876543210FEDCBA9876543210LLVGD"]) == [
            "Box is declared in Box.swift",
            "P is declared in Payload.swift",
        ])
    }

    /// A member of a private type is declared in the type's file: the type's
    /// own line already says so.
    @Test func discriminatorOfTheEnclosingDeclarationGetsNoLine() throws {
        // SymbolTestsCore.CodableTests.GenericCodableTest.(CodingKeys in _B89E…).stringValue.getter : Swift.String
        #expect(try Self.lines(
            for: ["$s15SymbolTestsCore12CodableTestsO07GenericC4TestV10CodingKeys33_B89E435DF71E951D297EEE1ADCD6DDD8LLO11stringValueSSvg"],
            enclosedBy: "$s15SymbolTestsCore12CodableTestsO07GenericC4TestV10CodingKeys33_B89E435DF71E951D297EEE1ADCD6DDD8LLOMn"
        ).isEmpty)
    }

    @Test func privateMemberOfAPublicTypeGetsALine() throws {
        // Main.Holder.(helper in _0123…)() -> ()
        #expect(try Self.lines(for: ["$s4Main6HolderV6helper33_0123456789ABCDEF0123456789ABCDEFLLyyF"], enclosedBy: "$s4Main6HolderVMn") == [
            "helper is declared in Box.swift",
        ])
    }

    /// A conformance's header reads two names, the type's and the
    /// protocol's; a discriminator both read gets one line.
    @Test func linesAcrossNamesAreOnePerDiscriminator() throws {
        #expect(try Self.lines(for: [
            // Main.(Box in _0123…)
            "$s4Main3Box33_0123456789ABCDEF0123456789ABCDEFLLVD",
            // Main.(Holder in _0123…).(Inner in _0123…)
            "$s4Main6Holder33_0123456789ABCDEF0123456789ABCDEFLLV5Inner33_0123456789ABCDEF0123456789ABCDEFLLVD",
        ]) == [
            "Inner is declared in Box.swift",
        ])
    }
}
