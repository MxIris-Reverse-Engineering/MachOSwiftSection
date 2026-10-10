import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
import SwiftDeclaration
@_spi(Support) import SwiftIndexing
@_spi(Support) import SwiftInterface
@testable import MachOTestingSupport

/// Local types on the indexing and interface paths (evolution proposal
/// `local-type-context-names`). Named after their method, two methods'
/// `Visitor`s are two definitions: the indexer used to key both under
/// `Holder.Visitor`, keep the last one and file it twice under `Holder`.
/// In the interface a local type stays nested in its enclosing type, its
/// method named in a comment above it, and a reference to it in a type
/// position prints its declared name — the upstream-free printer used to
/// print nothing there.
@Suite(.serialized, ExclusiveImageAccess(LocalTypeFixture.exclusiveAccessName))
struct LocalTypeInterfaceTests {
    private func fileBuilder(of variant: LocalTypeFixture.Variant) async throws -> SwiftInterfaceBuilder<MachOFile> {
        let builder = try SwiftInterfaceBuilder(configuration: .init(), eventHandlers: [], in: try LocalTypeFixture.machOFile(variant))
        try await builder.prepare()
        return builder
    }

    private func interface(of variant: LocalTypeFixture.Variant) async throws -> String {
        try await fileBuilder(of: variant).printRoot().string
    }

    private func inProcessInterface(of variant: LocalTypeFixture.Variant) async throws -> String {
        let builder = try SwiftInterfaceBuilder(configuration: .init(), eventHandlers: [], in: try LocalTypeFixture.loadedImage(variant))
        try await builder.prepare()
        return try await builder.printRoot().string
    }

    /// The block whose header line STARTS with `prefix`, through its closing
    /// brace at the same indentation.
    private func block(startingWith prefix: String, in interface: String) -> String? {
        let lines = interface.split(separator: "\n", omittingEmptySubsequences: false)
        guard let start = lines.firstIndex(where: { $0.hasPrefix(prefix) }) else { return nil }
        let indentation = lines[start].prefix { $0 == " " }
        guard let end = lines[start...].firstIndex(where: { $0 == "\(indentation)}" }) else { return nil }
        return lines[start...end].joined(separator: "\n")
    }

    // MARK: - Indexing

    /// Every local type is one definition, filed once under its enclosing
    /// type. The two `Visitor`s used to collapse into one definition that
    /// `Holder` listed twice.
    @Test func everyLocalTypeIsIndexedOnceUnderItsEnclosingType() async throws {
        let indexer = try await fileBuilder(of: .unstripped).indexer
        let holder = try #require(indexer.allTypeDefinitions.values.first { $0.typeName.declaredNameForTesting == "Holder" })
        let childNames = holder.typeChildren.map(\.typeName.declaredNameForTesting)

        #expect(childNames.sorted() == ["Box", "Generator", "Hidden", "InClosure", "Key", "Key", "Lookup", "Mode", "Payload", "Twin", "Twin", "Visitor", "Visitor", "WrappingGenerator"])
        #expect(Set(holder.typeChildren.map { ObjectIdentifier($0) }).count == holder.typeChildren.count, "a definition is listed twice")
        // Holder, its fourteen local types, the four types nested in them, the
        // two local types outside `Holder`, and the twins `KeyTwin`,
        // `PayloadTwin` with its `CodingKeys`, and `LookupTwin`.
        #expect(indexer.allTypeDefinitions.count == 25)
    }

    /// A `~Copyable` generic parameter makes the compiler name a type's
    /// members as if they sat in an extension with the inverse requirement;
    /// that extension must extend the very name the type is indexed under,
    /// or a host looking the type up by the extension's name (RuntimeViewer
    /// does) lists it as a stray extension.
    @Test func inverseExtensionOfANestedLocalTypeExtendsTheIndexedName() async throws {
        let indexer = try await fileBuilder(of: .unstripped).indexer
        let visitor = try #require(indexer.allTypeDefinitions.keys.first { $0.declaredNameForTesting == "IndexWrappingVisitor" })

        #expect(indexer.typeExtensionDefinitions.keys.contains { $0.name == visitor.name }, "no extension extends \(visitor.name)")
        #expect(visitor.name.hasPrefix("IndexWrappingVisitor in WrappingGenerator #1 in "))
    }

    // MARK: - Conformance members

    /// A local type of the fixture, its twin declared outside any body, and
    /// the standard-library protocols both conform to — each type by the name
    /// its conformance extensions are filed and printed under.
    private struct TwinConformances {
        let localTypeName: String
        let twinName: String
        let protocolNames: [String]
    }

    private static func twinConformances(moduleName: String) -> [TwinConformances] {
        let hashableProtocolNames = ["Swift.Hashable", "Swift.Equatable"]
        return [
            TwinConformances(localTypeName: "Key #1 in \(moduleName).Holder.keyFromGetter.getter : Any", twinName: "\(moduleName).KeyTwin", protocolNames: hashableProtocolNames),
            TwinConformances(localTypeName: "Key #1 in static \(moduleName).Holder.keyFromStaticMethod() -> Any", twinName: "\(moduleName).KeyTwin", protocolNames: hashableProtocolNames),
            TwinConformances(localTypeName: "Payload #1 in \(moduleName).Holder.payload() throws -> Any", twinName: "\(moduleName).PayloadTwin", protocolNames: ["Swift.Encodable", "Swift.Decodable"]),
            TwinConformances(
                localTypeName: "CodingKeys in Payload #1 in \(moduleName).Holder.payload() throws -> Any",
                twinName: "\(moduleName).PayloadTwin.CodingKeys",
                protocolNames: hashableProtocolNames + ["Swift.CodingKey", "Swift.CustomStringConvertible", "Swift.CustomDebugStringConvertible"]
            ),
            TwinConformances(
                localTypeName: "Lookup #1 in \(moduleName).Holder.lookup(named: Swift.String, at: Swift.Int) -> Any",
                twinName: "\(moduleName).LookupTwin",
                protocolNames: hashableProtocolNames
            ),
        ]
    }

    /// The member lines of `extension <typeName>: <protocolName>`, trimmed
    /// and sorted; `nil` when the interface prints no such extension.
    private func members(ofExtensionOf typeName: String, conformingTo protocolName: String, in interface: String) -> [String]? {
        let header = "extension \(typeName): \(protocolName) {"
        let lines = interface.split(separator: "\n", omittingEmptySubsequences: false)
        guard let start = lines.firstIndex(where: { $0 == header || $0 == header + "}" }) else { return nil }
        guard lines[start] == header, let end = lines[start...].firstIndex(of: "}") else { return [] }
        return lines[(start + 1)..<end].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.sorted()
    }

    /// A conformance's witnesses are symbols filed under the conformance, so
    /// under the local type's full name — and that name carries its
    /// enclosing declaration: a getter's variable, a method's `static`, a
    /// function. Read as the member's own, they filed every witness of a type
    /// declared in a getter as a property and dropped it, and keyed every
    /// method witness as the enclosing function, keeping one of them.
    private func expectTwinMembers(in interface: String, moduleName: String) throws {
        for twinConformances in Self.twinConformances(moduleName: moduleName) {
            for protocolName in twinConformances.protocolNames {
                let twinMembers = try #require(members(ofExtensionOf: twinConformances.twinName, conformingTo: protocolName, in: interface), "no \(twinConformances.twinName): \(protocolName)")
                #expect(!twinMembers.isEmpty, "\(twinConformances.twinName): \(protocolName)")
                #expect(members(ofExtensionOf: twinConformances.localTypeName, conformingTo: protocolName, in: interface) == twinMembers, "\(twinConformances.localTypeName): \(protocolName)")
            }
        }
    }

    @Test func localConformancesListTheirTwinsMembersOffline() async throws {
        try expectTwinMembers(in: try await interface(of: .unstripped), moduleName: LocalTypeFixture.Variant.unstripped.moduleName)
    }

    @Test func localConformancesListTheirTwinsMembersInProcess() async throws {
        try expectTwinMembers(in: try await inProcessInterface(of: .unstripped), moduleName: LocalTypeFixture.Variant.unstripped.moduleName)
    }

    /// The same comparison on the model a host reads, where the kind of a
    /// member is the array it sits in: a witness filed under `static` because
    /// its local type's method is static prints the same, but a host lists
    /// it as a static member.
    @Test func localConformancesDeclareTheirTwinsMembers() async throws {
        let indexer = try await fileBuilder(of: .unstripped).indexer
        var membersByConformance: [String: [String]] = [:]
        for (extensionName, extensionDefinitions) in indexer.allConformanceExtensionDefinitions {
            for indexedExtensionDefinition in extensionDefinitions {
                let extensionDefinition = indexedExtensionDefinition.value
                try extensionDefinition.index(in: indexedExtensionDefinition.machO)
                guard let protocolName = extensionDefinition.conformingProtocolName?.name else { continue }
                let members = extensionDefinition.functions.map { "func \($0.name)" }
                    + extensionDefinition.staticFunctions.map { "static func \($0.name)" }
                    + extensionDefinition.variables.map { "var \($0.name)" }
                    + extensionDefinition.staticVariables.map { "static var \($0.name)" }
                    + extensionDefinition.allocators.map { _ in "init" }
                    + extensionDefinition.subscripts.map { _ in "subscript" }
                    + extensionDefinition.staticSubscripts.map { _ in "static subscript" }
                membersByConformance["\(extensionName.name): \(protocolName)", default: []] += members
            }
        }
        for twinConformances in Self.twinConformances(moduleName: LocalTypeFixture.Variant.unstripped.moduleName) {
            for protocolName in twinConformances.protocolNames {
                let twinMembers = try #require(membersByConformance["\(twinConformances.twinName): \(protocolName)"], "no \(twinConformances.twinName): \(protocolName) in \(membersByConformance.keys.sorted())").sorted()
                #expect(!twinMembers.isEmpty, "\(twinConformances.twinName): \(protocolName)")
                #expect(membersByConformance["\(twinConformances.localTypeName): \(protocolName)"]?.sorted() == twinMembers, "\(twinConformances.localTypeName): \(protocolName)")
            }
        }
    }

    // MARK: - Members in the body of a local type

    /// A local type of the fixture, the comment the interface prints above
    /// it, and its twin declared outside any body.
    private struct TwinBody {
        let comment: String
        let localTypeName: String
        let twinName: String
    }

    private static let twinBodies = [
        TwinBody(comment: "Lookup #1 in Holder.lookup(named:at:)", localTypeName: "Lookup", twinName: "LookupTwin"),
        TwinBody(comment: "Key #1 in Holder.keyFromGetter.getter", localTypeName: "Key", twinName: "KeyTwin"),
    ]

    /// The member lines of a type's block, trimmed and sorted.
    private func memberLines(of block: String) -> [String] {
        block.split(separator: "\n").dropFirst().dropLast().map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.sorted()
    }

    /// A local type's context comes first in each of its members' names. The
    /// method declaring `Lookup`, `lookup(named:at:)`, put its label list and
    /// argument tuple there, and the getter declaring `Key` its accessor. Read
    /// as the member's own, they kept the synthesized `hash(into:)` in
    /// `Lookup`'s body (its labels read `named:at:`), lost
    /// `@dynamicMemberLookup` (the subscript's first label read `named`), gave
    /// `combine(_:_:_:)` one unnamed label per parameter of the method — two
    /// for three — and printed `Key`'s `static var shared` as a computed
    /// property, its storage symbol read as a getter. Each twin prints the
    /// same members, its own name in them read as the local type's.
    private func expectLocalTypeBodiesMatchTheirTwins(in interface: String, moduleName: String) throws {
        for twinBody in Self.twinBodies {
            let afterComment = try #require(interface.components(separatedBy: "\n    // \(twinBody.comment)\n").dropFirst().first, "no \(twinBody.comment) in\n\(interface)")
            let localTypeBlock = try #require(block(startingWith: "    struct \(twinBody.localTypeName) {", in: afterComment), "\(afterComment)")
            let twinBlock = try #require(block(startingWith: "struct \(twinBody.twinName) {", in: interface), "\(interface)")

            #expect(memberLines(of: localTypeBlock) == memberLines(of: twinBlock).map { $0.replacingOccurrences(of: "\(moduleName).\(twinBody.twinName)", with: twinBody.localTypeName) }, "\(localTypeBlock)\n\(twinBlock)")
        }
        #expect(interface.contains("\n    // Lookup #1 in Holder.lookup(named:at:)\n    @dynamicMemberLookup\n    struct Lookup {\n"), "\(interface)")
        #expect(interface.contains("\n@dynamicMemberLookup\nstruct LookupTwin {\n"), "\(interface)")
    }

    @Test func localTypeBodiesPrintLikeTheirTwinsOffline() async throws {
        try expectLocalTypeBodiesMatchTheirTwins(in: try await interface(of: .unstripped), moduleName: LocalTypeFixture.Variant.unstripped.moduleName)
    }

    @Test func localTypeBodiesPrintLikeTheirTwinsInProcess() async throws {
        try expectLocalTypeBodiesMatchTheirTwins(in: try await inProcessInterface(of: .unstripped), moduleName: LocalTypeFixture.Variant.unstripped.moduleName)
    }

    // MARK: - The interface

    private func expectNamedLocalTypes(in interface: String) throws {
        let holder = try #require(block(startingWith: "struct Holder {", in: interface), "\(interface)")
        // Both `Visitor`s, each under the comment naming its method, with its
        // own fields and members.
        #expect(holder.contains("\n    // Visitor #1 in Holder.countValues()\n    struct Visitor {\n        var count: Swift.Int\n"), "\(holder)")
        #expect(holder.contains("\n    // Visitor #1 in Holder.sumValues()\n    struct Visitor {\n        var sum: Swift.Int\n"), "\(holder)")
        #expect(holder.components(separatedBy: "struct Visitor {").count - 1 == 2, "\(holder)")
        #expect(holder.components(separatedBy: "func visit(_: Swift.Int)").count - 1 == 2, "\(holder)")
        #expect(holder.contains("\n    // Twin #1 in Holder.twins(_:)\n    struct Twin"), "\(holder)")
        #expect(holder.contains("\n    // Twin #2 in Holder.twins(_:)\n    struct Twin"), "\(holder)")
        #expect(holder.contains("\n    // Hidden #1 in Holder.hiddenValues()\n    struct Hidden"), "\(holder)")
        #expect(holder.contains("\n    // InClosure #1 in closure #1 in Holder.valuesFromClosure()\n    struct InClosure"), "\(holder)")
        // In a type position, a local type is its declared name; a type
        // nested in it is reached through that name.
        #expect(holder.contains("var element: Generator.Element"), "\(holder)")
        #expect(holder.contains("static func __derived_struct_equals(_: Visitor, _: Visitor) -> Swift.Bool"), "\(holder)")
        // Outside any type: under the module, and in an extension of the
        // type whose method declares it.
        #expect(interface.contains("\n// TopLevel #1 in localTypeFixtureTopLevel()\nstruct TopLevel {"), "\(interface)")
        let stringExtension = try #require(block(startingWith: "extension Swift.String {", in: interface), "\(interface)")
        #expect(stringExtension.contains("\n    // Wrapper #1 in String.localTypeFixtureWrapped()\n    struct Wrapper"), "\(stringExtension)")
    }

    @Test func interfaceNamesEachLocalTypesMethodOffline() async throws {
        try expectNamedLocalTypes(in: try await interface(of: .unstripped))
    }

    @Test func interfaceNamesEachLocalTypesMethodInProcess() async throws {
        try expectNamedLocalTypes(in: try await inProcessInterface(of: .unstripped))
    }

    /// With every name source stripped, the comment says the method is not
    /// recorded instead of naming a wrong one, and the two `Visitor`s stay
    /// two declarations.
    @Test func strippedInterfaceSaysTheMethodIsNotRecorded() async throws {
        let interface = try await interface(of: .stripped)
        let holder = try #require(block(startingWith: "struct Holder {", in: interface), "\(interface)")

        #expect(holder.contains("\n    // Local type in a function or closure the binary does not name\n    struct Visitor {\n        var count: Swift.Int\n"), "\(holder)")
        #expect(holder.contains("\n    // Local type in a function or closure the binary does not name\n    struct Visitor {\n        var sum: Swift.Int\n"), "\(holder)")
        #expect(holder.components(separatedBy: "struct Visitor {").count - 1 == 2, "\(holder)")
        #expect(!holder.contains(" in $"), "a position-based name leaked into a type position:\n\(holder)")
        // An extension of such a type, or of one nested in it, keeps the
        // position-based name: `Holder.WrappingGenerator.Counter` would name
        // a member type the source never declared.
        let moduleName = LocalTypeFixture.Variant.stripped.moduleName
        #expect(interface.contains("\nextension \(moduleName).Holder.(Visitor in $"), "\(interface)")
        #expect(interface.contains("\nextension \(moduleName).Holder.(WrappingGenerator in $"), "\(interface)")
        #expect(!interface.contains("\nextension \(moduleName).Holder.WrappingGenerator."), "\(interface)")
    }
}
