import Foundation
import Testing
import MachOKit
import MachOFixtureSupport
@testable import MachOTestingSupport
import Demangling
import SwiftDeclaration
@_spi(Support) import SwiftIndexing
import SwiftInspection

/// `privateDeclarations` reads a name's whole tree but for two parts: the
/// signature of a function, closure, variable, subscript, initializer or
/// macro the name runs through, and a position-based local type's `$`
/// address (evolution proposal `private-declarations`). A name that runs
/// through neither reads exactly what a whole-tree search reads — the search
/// RuntimeViewer ran before this one moved here. Every definition name of the
/// fixtures below that runs through neither is checked against such a
/// search, written apart from the library's walk.
@Suite(.serialized, ExclusiveImageAccess(LocalTypeFixture.exclusiveAccessName))
struct PrivateDeclarationsWholeTreeTests {
    /// What the comparison covered: the names compared, and how many of them
    /// read a private declaration.
    private struct Coverage {
        var comparedNames = 0
        var namesReadingAPrivateDeclaration = 0
    }

    /// Every `privateDeclName` in the tree, in preorder, each once — the
    /// search RuntimeViewer ran (`node.all(of: .privateDeclName)`).
    private static func wholeTreePrivateDeclarations(of node: Node) -> [PrivateDeclaration] {
        var privateDeclarations: [PrivateDeclaration] = []
        func visit(_ node: Node) {
            if node.kind == .privateDeclName, let discriminator = node.children.first?.text {
                let privateDeclaration = PrivateDeclaration(name: node.children.at(1)?.text, discriminator: discriminator)
                if !privateDeclarations.contains(privateDeclaration) {
                    privateDeclarations.append(privateDeclaration)
                }
            }
            for child in node.children {
                visit(child)
            }
        }
        visit(node)
        return privateDeclarations
    }

    /// The declarations whose children carry a signature.
    private static let declarationsWithASignature: Set<Node.Kind> = [
        .function, .explicitClosure, .implicitClosure, .allocator, .constructor, .subscript, .variable, .macro,
    ]

    /// Whether the name runs through a declaration with a signature, or names
    /// a type by the address of its anonymous context.
    private static func runsThroughASignatureOrAnAddress(_ node: Node) -> Bool {
        if declarationsWithASignature.contains(node.kind) {
            return true
        }
        if node.kind == .privateDeclName, node.children.first?.text?.hasPrefix("$") == true {
            return true
        }
        return node.children.contains(where: runsThroughASignatureOrAnAddress)
    }

    private static func definitionNames<MachO>(of indexer: SwiftDeclarationIndexer<MachO>) -> [any DefinitionName] {
        var definitionNames: [any DefinitionName] = []
        definitionNames += indexer.allTypeDefinitions.keys.map { $0 as any DefinitionName }
        definitionNames += indexer.allProtocolDefinitions.keys.map { $0 as any DefinitionName }
        for extensionDefinitions in [indexer.typeExtensionDefinitions, indexer.protocolExtensionDefinitions, indexer.typeAliasExtensionDefinitions, indexer.conformanceExtensionDefinitions] {
            definitionNames += extensionDefinitions.keys.map { $0 as any DefinitionName }
        }
        return definitionNames
    }

    private static func compare<MachO>(definitionNamesOf indexer: SwiftDeclarationIndexer<MachO>) -> Coverage {
        var coverage = Coverage()
        for definitionName in definitionNames(of: indexer) {
            let node = definitionName.node.materialize()
            guard !runsThroughASignatureOrAnAddress(node) else { continue }
            let expectedPrivateDeclarations = wholeTreePrivateDeclarations(of: node)
            #expect(definitionName.node.privateDeclarations == expectedPrivateDeclarations, "\(definitionName.name)")
            #expect(node.privateDeclarations == expectedPrivateDeclarations, "\(definitionName.name)")
            coverage.comparedNames += 1
            if !expectedPrivateDeclarations.isEmpty {
                coverage.namesReadingAPrivateDeclaration += 1
            }
        }
        return coverage
    }

    @Test func localTypeFixtureReadFromItsFile() async throws {
        let indexer = SwiftDeclarationIndexer(configuration: .init(), eventHandlers: [], in: try LocalTypeFixture.machOFile(.unstripped))
        try await indexer.prepare()

        let coverage = Self.compare(definitionNamesOf: indexer)
        #expect(coverage.comparedNames > 0)
    }

    @Test func localTypeFixtureLoadedIntoTheProcess() async throws {
        let indexer = SwiftDeclarationIndexer(configuration: .init(), eventHandlers: [], in: try LocalTypeFixture.loadedImage(.unstripped))
        try await indexer.prepare()

        let coverage = Self.compare(definitionNamesOf: indexer)
        #expect(coverage.comparedNames > 0)
    }

    /// SymbolTestsCore declares private types (`PrivateDoppelgangers.swift`,
    /// `Structs.swift`), so here the names compared do read some.
    @Test func symbolTestsCore() async throws {
        let machOFile: MachOFile
        switch try loadFromFile(named: .SymbolTestsCore) {
        case .machO(let thinMachOFile):
            machOFile = thinMachOFile
        case .fat(let fatFile):
            machOFile = try #require(try fatFile.machOFiles().first { $0.header.cpuType == .arm64 })
        }
        let indexer = SwiftDeclarationIndexer(configuration: .init(), eventHandlers: [], in: machOFile)
        try await indexer.prepare()

        let coverage = Self.compare(definitionNamesOf: indexer)
        #expect(coverage.comparedNames > 0)
        #expect(coverage.namesReadingAPrivateDeclaration > 0)
    }

    /// The names of `PrivateDeclarationsTests` (SwiftInspectionTests) that run
    /// through no signature, compiled from a sample module `Shapes`: a
    /// private type; a type in a constrained extension of a private generic
    /// type, which no fixture above has; and specialized types whose
    /// arguments are private.
    @Test(arguments: [
        "$s6Shapes15PrivateArgument33_C01776A4525D5700C9CAB18498B5F7E5LLVMn",
        "$s6Shapes14PrivateGeneric33_C01776A4525D5700C9CAB18498B5F7E5LLVAASiRszlE22InConstrainedExtensionVMn",
        "$sSay6Shapes15PrivateArgument33_C01776A4525D5700C9CAB18498B5F7E5LLVGD",
        "$sSDy6Shapes15PrivateArgument33_C01776A4525D5700C9CAB18498B5F7E5LLVAA13PrivateHolder33_C01776A4525D5700C9CAB18498B5F7E5LLVGD",
    ])
    func sampleNamesReadingPrivateDeclarations(mangledName: String) throws {
        let node = try demangleAsNodeTransient(mangledName)
        try #require(!Self.runsThroughASignatureOrAnAddress(node))

        let expectedPrivateDeclarations = Self.wholeTreePrivateDeclarations(of: node)
        #expect(!expectedPrivateDeclarations.isEmpty)
        #expect(node.privateDeclarations == expectedPrivateDeclarations)
    }
}
