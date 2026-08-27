@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
@_spi(Support) @testable import SwiftPrinting
import Foundation
import Testing
import MachOKit
@_spi(Support) @testable import SwiftInterface
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// End-to-end coverage for the `final` keyword recovery and the lazy-var
/// accessor-type correction (evolution proposal 0006), pinned against the
/// `VTableEntryVariants.FinalMembersTest` fixture matrix: every final/plain
/// pairing across stored properties, lazy storage, computed properties,
/// methods, and subscripts.
@Suite(.serialized)
final class FinalMemberRecoveryTests: MachOFileTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SymbolTestsCore }

    private func buildOutput() async throws -> String {
        let configuration = SwiftInterfaceBuilderConfiguration(
            indexConfiguration: .init(showCImportedTypes: false),
            printConfiguration: .init(
                printStrippedSymbolicItem: true,
                printFieldOffset: false,
                printMemberAddress: false,
                printVTableOffset: true,
                printPWTOffset: false,
                memberSortOrder: .byOffset,
                printTypeLayout: false,
                printEnumLayout: false
            )
        )
        let unsafeMachOFile = machOFile
        let builder = try SwiftInterfaceBuilder(configuration: configuration, eventHandlers: [], in: unsafeMachOFile)
        try await builder.prepare()
        let result = try await builder.printRoot()
        return result.string
    }

    private func finalMembersTestDefinition() async throws -> TypeDefinition {
        let unsafeMachOFile = machOFile
        let builder = try SwiftInterfaceBuilder(configuration: .init(indexConfiguration: .init(showCImportedTypes: false)), eventHandlers: [], in: unsafeMachOFile)
        try await builder.prepare()
        // `printRoot()` indexes every definition in place — the model facts
        // below read the post-index state without crossing an isolation
        // boundary with the non-Sendable definition.
        _ = try await builder.printRoot()
        return try #require(builder.indexer.allTypeDefinitions.values.first { $0.typeName.name.hasSuffix("FinalMembersTest") })
    }

    // MARK: - Rendered output: `final` keyword

    @Test func renderedOutputPairsFinalCorrectly() async throws {
        let output = try await buildOutput()

        // Stored properties.
        #expect(output.contains("final var finalStoredProperty"))
        #expect(!output.contains("final var plainStoredProperty"))
        // A stored `let` is not overridable to begin with — never marked.
        #expect(output.contains("let constantStoredProperty"))
        #expect(!output.contains("final let"))

        // Lazy storage.
        #expect(output.contains("final lazy var finalLazyProperty"))
        #expect(!output.contains("final lazy var plainLazyProperty"))

        // Computed properties.
        #expect(output.contains("final var finalComputedProperty"))
        #expect(!output.contains("final var plainComputedProperty"))

        // Methods.
        #expect(output.contains("final func finalMethod"))
        #expect(!output.contains("final func plainMethod"))

        // Subscripts.
        #expect(output.contains("final subscript(finalIndex"))
        #expect(!output.contains("final subscript(plainIndex"))

        // Type-level members are implicitly final / spelled `class`; overrides
        // carry override descriptors — none may gain the keyword.
        #expect(!output.contains("final static"))
        #expect(!output.contains("final class func"))
        #expect(!output.contains("final override"))
    }

    // MARK: - Rendered output: lazy accessor type

    @Test func lazyVarPrintsAccessorTypeNotStorageType() async throws {
        let output = try await buildOutput()
        // The pre-0006 output rendered the `Optional` storage type
        // (`lazy var lazyProperty: Swift.String?`); the getter's type is the
        // one callers see.
        #expect(!output.contains("lazy var lazyProperty: Swift.String?"))
        #expect(output.contains("lazy var lazyProperty: Swift.String"))
        #expect(!output.contains("lazy var plainLazyProperty: Swift.String?"))
        #expect(output.contains("lazy var plainLazyProperty: Swift.String"))
    }

    // MARK: - Rendered output: stored-var accessor vtable comments

    @Test func plainStoredVarCarriesAccessorVTableComments() async throws {
        let output = try await buildOutput()
        let declarationRange = try #require(output.range(of: "var plainStoredProperty"))
        // The lines immediately above the declaration must attribute the
        // getter/setter to their vtable slots (issue #106 §1: a stored `var`
        // without any vtable comment used to be indistinguishable from a
        // `final` one).
        let windowStart = output.index(declarationRange.lowerBound, offsetBy: -300, limitedBy: output.startIndex) ?? output.startIndex
        let window = String(output[windowStart ..< declarationRange.lowerBound])
        #expect(window.contains("VTable offset (getter):"))
        #expect(window.contains("VTable offset (setter):"))

        // The `final` stored `var` has no vtable entries, so the line
        // immediately above its declaration must not be a vtable comment.
        // (A fixed-size window would bleed into the preceding class's last
        // member, whose async override legitimately carries one.)
        let finalDeclarationRange = try #require(output.range(of: "final var finalStoredProperty"))
        // The last fragment is the declaration line's own indentation; the one
        // before it is the actual preceding line.
        let precedingLine = output[..<finalDeclarationRange.lowerBound]
            .split(separator: "\n", omittingEmptySubsequences: true)
            .suffix(2)
            .joined()
        #expect(!precedingLine.contains("VTable offset"))
    }

    // MARK: - Model facts

    @Test func modelMarksFinalMembers() async throws {
        let typeDefinition = try await finalMembersTestDefinition()

        let fieldsByName = Dictionary(uniqueKeysWithValues: typeDefinition.fields.map { ($0.name, $0) })
        let finalStored = try #require(fieldsByName["finalStoredProperty"])
        let plainStored = try #require(fieldsByName["plainStoredProperty"])
        let constantStored = try #require(fieldsByName["constantStoredProperty"])
        let finalLazy = try #require(fieldsByName["finalLazyProperty"])
        let plainLazy = try #require(fieldsByName["plainLazyProperty"])

        // The accessor groups must have joined (the evidence gate) …
        #expect(!finalStored.accessors.isEmpty)
        #expect(!plainStored.accessors.isEmpty)
        // … and the vtable attribution decides `final`.
        #expect(finalStored.isFinal)
        #expect(!finalStored.hasVTableAccessor)
        #expect(!plainStored.isFinal)
        #expect(plainStored.hasVTableAccessor)
        // A stored `let` is not overridable — never marked.
        #expect(!constantStored.isFinal)
        #expect(finalLazy.isFinal)
        #expect(!plainLazy.isFinal)

        let functionsByName = Dictionary(grouping: typeDefinition.functions, by: \.name)
        #expect(functionsByName["finalMethod"]?.allSatisfy(\.isFinal) == true)
        #expect(functionsByName["plainMethod"]?.allSatisfy { !$0.isFinal } == true)

        let variablesByName = Dictionary(grouping: typeDefinition.variables, by: \.name)
        #expect(variablesByName["finalComputedProperty"]?.allSatisfy(\.isFinal) == true)
        #expect(variablesByName["plainComputedProperty"]?.allSatisfy { !$0.isFinal } == true)

        #expect(typeDefinition.subscripts.contains { $0.isFinal })
        #expect(typeDefinition.subscripts.contains { !$0.isFinal })
        #expect(typeDefinition.staticFunctions.allSatisfy { !$0.isFinal })
        #expect(typeDefinition.staticVariables.allSatisfy { !$0.isFinal })
    }

    @Test func modelCapturesLazyAccessorType() async throws {
        let typeDefinition = try await finalMembersTestDefinition()
        let fieldsByName = Dictionary(uniqueKeysWithValues: typeDefinition.fields.map { ($0.name, $0) })

        let plainLazy = try #require(fieldsByName["plainLazyProperty"])
        let accessorTypeNode = try #require(plainLazy.accessorTypeNode)
        // The storage record's type is `Optional<String>`; the getter's is `String`.
        #expect(await accessorTypeNode.print(using: .default) == "Swift.String")
        let storageTypeText = await plainLazy.typeNode.print(using: .default)
        #expect(storageTypeText.contains("?") || storageTypeText.contains("Optional"))

        // Non-lazy fields keep no accessor-facing override.
        let plainStored = try #require(fieldsByName["plainStoredProperty"])
        #expect(plainStored.accessorTypeNode == nil)
    }

    /// `final` recovery's symbol lookups are node-matched, so two same-named
    /// `private class`es each get their own verdict: the `PrivateDoppelganger`
    /// pair declares `sharedNameMethod()` non-final in one file and `final` in
    /// the other, under one discriminator-stripped name.
    ///
    /// NON-REGRESSION PIN, NOT A REPRODUCTION. No trigger could be constructed
    /// for the name-only lookups this replaced: a `private` class emits no `Tq`
    /// method-descriptor symbols (the negative-evidence gate reads nothing from
    /// either sibling) and no stored-property accessor symbols (the `@objc`
    /// gate, which only guards stored fields, has nothing to strip), and Swift
    /// rejects a same-named `internal`/`private` pair outright with `invalid
    /// redeclaration`. What this pins is that node-matching the lookups does
    /// not BREAK the verdicts it now scopes. See `ReviewAdjudications.md`.
    @Test func sameNamedPrivateClassesGetIndependentFinalVerdicts() async throws {
        let output = try await buildOutput()

        // Exactly one of the two same-named declarations carries `final` on
        // the shared member name — never both, never neither.
        let finalOccurrences = output.components(separatedBy: "final func sharedNameMethod()").count - 1
        let plainOccurrences = output.components(separatedBy: "\n    func sharedNameMethod()").count - 1
        #expect(finalOccurrences == 1, "expected exactly one `final func sharedNameMethod()`")
        #expect(plainOccurrences == 1, "expected exactly one non-final `func sharedNameMethod()`")
    }
}
