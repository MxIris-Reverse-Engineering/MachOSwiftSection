import Foundation
import Testing
import MachOKit
import MachOFoundation
@_spi(Internals) import Demangling
@testable import MachOSwiftSection
@_spi(Internals) @testable import SwiftInspection

/// `SymbolicDemangler`'s two fixed-shape node extractions (evolution proposal
/// `metadata-reader-deterministic-node-extraction`).
///
/// Both used to be depth-first searches for "the first node that looks right"
/// (`typeSymbol` / `extensionSymbol`), written before the ABI shape of the two
/// fields was understood; they happened to stop at the right node on every
/// sample seen so far. The replacements read the shape IRGen actually writes
/// and answer `nil` for anything else:
///
/// - An Objective-C protocol symbolic reference (`\x0C`) points at a record
///   whose second field is the protocol's declared type mangled flat
///   (`So9NSCopying_p`), so the demangling is exactly
///   `Type → ProtocolList → TypeList → Type(Protocol)`.
/// - An extension descriptor's `ExtendedContext` is the extension's
///   `getSelfInterfaceType()`: a bare nominal, or `Array<A>` (bound generic)
///   for a generic type, or the `Self` parameter for a protocol extension.
///
/// The extension leg is already pinned by the `SymbolTestsCore` interface
/// snapshot (`extension Generics.GenericRequirementTest.RawRepresentableNestedStruct`
/// nests a struct, so its descriptor demangles through the bound-generic
/// shape). The ObjC-protocol leg had NO fixture coverage: the checked-in
/// fixture's `GenericStructObjCProtocolRequirement<A: NSCopying>` goes through
/// the generic requirement's protocol POINTER (`ObjCProtocolPrefix`), never a
/// mangled-name reference. IRGen only emits the `\x0C` reference for a
/// deployment target of macOS 15 / iOS 18 or later (feature availability
/// `ObjCSymbolicReferences` = 6.0), so the fixture below is compiled on the
/// fly with that target.
struct SymbolicDemanglerFixedShapeExtractionTests {
    // MARK: - Pure-shape tests (hand-built trees)

    @Test func objectiveCProtocolReferenceIsReadOffTheFourFixedLevels() throws {
        let protocolNode = Node.createTransient(kind: .protocol, children: [
            .createTransient(kind: .module, text: "__C"),
            .createTransient(kind: .identifier, text: "NSCopying"),
        ])
        let protocolType = Node.createTransient(kind: .type, children: [protocolNode])
        let existential = Node.createTransient(kind: .type, children: [
            .createTransient(kind: .protocolList, children: [
                .createTransient(kind: .typeList, children: [protocolType]),
            ]),
        ])

        let resolved = try #require(SymbolicDemangler.objectiveCProtocolReferenceNode(fromExistential: existential))
        #expect(resolved === protocolType, "the resolver must hand back the inner Type(Protocol) itself, the shape popProtocol accepts")
    }

    @Test func objectiveCProtocolReferenceRefusesAnyOtherShape() {
        // A bare nominal type: the OLD search would have wrapped it in a Type
        // and called it a protocol reference.
        let structType = Node.createTransient(kind: .type, children: [
            .createTransient(kind: .structure, children: [
                .createTransient(kind: .module, text: "Swift"),
                .createTransient(kind: .identifier, text: "Int"),
            ]),
        ])
        #expect(SymbolicDemangler.objectiveCProtocolReferenceNode(fromExistential: structType) == nil)

        // A protocol list holding a struct where the protocol should be.
        let structInProtocolPosition = Node.createTransient(kind: .type, children: [
            .createTransient(kind: .protocolList, children: [
                .createTransient(kind: .typeList, children: [structType]),
            ]),
        ])
        #expect(SymbolicDemangler.objectiveCProtocolReferenceNode(fromExistential: structInProtocolPosition) == nil)

        // The protocol node without its Type wrapper at the top.
        let bareProtocolList = Node.createTransient(kind: .protocolList, children: [
            .createTransient(kind: .typeList, children: []),
        ])
        #expect(SymbolicDemangler.objectiveCProtocolReferenceNode(fromExistential: bareProtocolList) == nil)
    }

    @Test func extendedContextOfANonGenericTypeIsTheBareNominal() throws {
        let structure = Node.createTransient(kind: .structure, children: [
            .createTransient(kind: .module, text: "Fixture"),
            .createTransient(kind: .identifier, text: "Plain"),
        ])
        let extendedContext = Node.createTransient(kind: .type, children: [structure])

        let extended = try #require(SymbolicDemangler.extendedNominalNode(fromExtendedContext: extendedContext))
        #expect(extended === structure)
    }

    @Test func extendedContextOfAGenericTypeDropsTheBoundArguments() throws {
        // `extension Array` mangles `Array<A>`: the bound generic wraps the
        // nominal, and the demangler's own Extension node names only the
        // nominal (the parameters come from the generic signature).
        let array = Node.createTransient(kind: .structure, children: [
            .createTransient(kind: .module, text: "Swift"),
            .createTransient(kind: .identifier, text: "Array"),
        ])
        let boundGeneric = Node.createTransient(kind: .boundGenericStructure, children: [
            .createTransient(kind: .type, children: [array]),
            .createTransient(kind: .typeList, children: [
                .createTransient(kind: .type, children: [
                    .createTransient(kind: .dependentGenericParamType, children: [
                        .createTransient(kind: .index, index: 0),
                        .createTransient(kind: .index, index: 0),
                    ]),
                ]),
            ]),
        ])
        let extendedContext = Node.createTransient(kind: .type, children: [boundGeneric])

        let extended = try #require(SymbolicDemangler.extendedNominalNode(fromExtendedContext: extendedContext))
        #expect(extended === array)
    }

    @Test func extendedContextOfAProtocolExtensionIsNotResolved() {
        // `extension Collection` mangles the `Self` parameter — nothing in the
        // field names the protocol, and the runtime's own
        // `_buildDemanglingForContext` does not resolve it either. The OLD
        // search returned nil here too; the point is that it stays nil rather
        // than becoming a guess.
        let selfParameter = Node.createTransient(kind: .type, children: [
            .createTransient(kind: .dependentGenericParamType, children: [
                .createTransient(kind: .index, index: 0),
                .createTransient(kind: .index, index: 0),
            ]),
        ])
        #expect(SymbolicDemangler.extendedNominalNode(fromExtendedContext: selfParameter) == nil)

        // And a missing Type wrapper is a shape violation, not a nominal.
        let bareNominal = Node.createTransient(kind: .structure, children: [
            .createTransient(kind: .module, text: "Fixture"),
            .createTransient(kind: .identifier, text: "Plain"),
        ])
        #expect(SymbolicDemangler.extendedNominalNode(fromExtendedContext: bareNominal) == nil)
    }

    // MARK: - Real `\x0C` references from an on-the-fly fixture

    private enum FixtureWorkingDirectoryCleanup {
        nonisolated(unsafe) static var directories: [URL] = []
        static let registration: Void = {
            atexit {
                for directory in FixtureWorkingDirectoryCleanup.directories {
                    try? FileManager.default.removeItem(at: directory)
                }
            }
        }()
    }

    /// `Anchor` keeps a `__DATA` segment in the dylib (see AGENTS.md,
    /// "On-the-fly-compiled fixture dylibs need a class"). `Holder`'s two
    /// fields are what put ObjC protocols into mangled type names: a single
    /// existential and a composition, so the reference resolves once and
    /// twice within one name.
    private static let fixtureSource = """
    import Foundation

    public final class Anchor {}

    public struct Holder {
        public var copyable: any NSCopying
        public var both: any NSObjectProtocol & NSCopying

        public init(copyable: any NSCopying, both: any NSObjectProtocol & NSCopying) {
            self.copyable = copyable
            self.both = both
        }
    }
    """

    private static let fixtureCompilationResult: Result<URL, Swift.Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("ObjCProtocolReferenceFixture-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            _ = FixtureWorkingDirectoryCleanup.registration
            FixtureWorkingDirectoryCleanup.directories.append(workingDirectory)

            let sourceURL = workingDirectory.appendingPathComponent("ObjCProtocolReferenceFixture.swift")
            let libraryURL = workingDirectory.appendingPathComponent("libObjCProtocolReferenceFixture.dylib")
            try fixtureSource.write(to: sourceURL, atomically: true, encoding: .utf8)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = [
                "swiftc", "-emit-library", "-module-name", "ObjCProtocolReferenceFixture",
                // The deployment target that turns ObjC-protocol symbolic
                // references on (feature availability 6.0 = macOS 15).
                "-target", "arm64-apple-macosx15.0",
                sourceURL.path, "-o", libraryURL.path,
            ]
            let standardErrorPipe = Pipe()
            process.standardError = standardErrorPipe
            try process.run()
            // Drain BEFORE waitUntilExit — see LegacyDyldInfoBindTests.
            let diagnosticsData = standardErrorPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw FixtureCompilationError(diagnostics: String(decoding: diagnosticsData, as: UTF8.self))
            }
            return libraryURL
        }
    }()

    private struct FixtureCompilationError: Swift.Error, CustomStringConvertible {
        let diagnostics: String
        var description: String { "ObjC-protocol-reference fixture compilation failed:\n\(diagnostics)" }
    }

    private func loadFixtureMachOFile() throws -> MachOFile {
        let libraryURL = try Self.fixtureCompilationResult.get()
        switch try MachOKit.loadFromFile(url: libraryURL) {
        case .machO(let machOFile):
            return machOFile
        case .fat(let fatFile):
            let machOFile = try fatFile.machOFiles().first { $0.header.cpuType == .arm64 }
            return try #require(machOFile, "fixture unexpectedly missing an arm64 slice")
        }
    }

    private func holderFieldMangledTypeName(named fieldName: String, in machOFile: MachOFile) throws -> MangledName {
        for typeContextDescriptor in try machOFile.swift.typeContextDescriptors {
            guard case .struct(let structDescriptor) = typeContextDescriptor else { continue }
            guard try structDescriptor.name(in: machOFile) == "Holder" else { continue }
            let fieldDescriptor = try #require(try structDescriptor.fieldDescriptor(in: machOFile))
            for record in try fieldDescriptor.records(in: machOFile) where try record.fieldName(in: machOFile) == fieldName {
                return try record.mangledTypeName(in: machOFile)
            }
            throw FixtureCompilationError(diagnostics: "Holder has no field \(fieldName)")
        }
        throw FixtureCompilationError(diagnostics: "fixture is missing the struct Holder")
    }

    /// The premise every fixture test below stands on: the field's mangled
    /// type name really carries `\x0C` ObjC-protocol symbolic references.
    /// Without them the resolver leg under test never runs, and a green test
    /// would prove nothing.
    private func objectiveCProtocolReferenceCount(in mangledName: MangledName) -> Int {
        mangledName.lookupElements.filter { lookup in
            guard case .relative(let relativeReference) = lookup.reference else { return false }
            return relativeReference.kind == 0x0C
        }.count
    }

    private func protocolTypes(inExistential existential: Node) throws -> [Node] {
        try #require(existential.kind == .type)
        let protocolList = try #require(existential.children.first)
        try #require(protocolList.kind == .protocolList)
        let typeList = try #require(protocolList.children.first)
        try #require(typeList.kind == .typeList)
        return Array(typeList.children)
    }

    @Test func singleObjCProtocolExistentialFieldResolvesToTypeProtocol() throws {
        let machOFile = try loadFixtureMachOFile()
        let mangledName = try holderFieldMangledTypeName(named: "copyable", in: machOFile)
        try #require(objectiveCProtocolReferenceCount(in: mangledName) == 1, "the fixture must reference NSCopying through a \\x0C symbolic reference for this test to mean anything")

        let node = try SymbolicDemangler.demangleType(for: mangledName, in: machOFile)
        #expect(node.print(using: .default) == "__C.NSCopying")

        let protocolTypes = try protocolTypes(inExistential: node)
        #expect(protocolTypes.count == 1)
        let protocolType = try #require(protocolTypes.first)
        #expect(protocolType.kind == .type)
        let protocolNode = try #require(protocolType.children.first)
        #expect(protocolNode.kind == .protocol)
        #expect(protocolNode.children.first?.kind == .module)
        #expect(protocolNode.children.first?.text == "__C")
        #expect(protocolNode.children.last?.text == "NSCopying")
    }

    @Test func objCProtocolCompositionFieldResolvesEachReference() throws {
        let machOFile = try loadFixtureMachOFile()
        let mangledName = try holderFieldMangledTypeName(named: "both", in: machOFile)
        try #require(objectiveCProtocolReferenceCount(in: mangledName) == 2, "the fixture must reference both protocols through \\x0C symbolic references for this test to mean anything")

        let node = try SymbolicDemangler.demangleType(for: mangledName, in: machOFile)
        // The protocol Swift spells `NSObjectProtocol` is the ObjC protocol
        // `NSObject`; the reference record mangles the ObjC runtime name
        // (`So8NSObject_p`), and the Swift-side rename is APINotes' business
        // (TypeIndexing), not the demangler's.
        let printed = node.print(using: .default)
        #expect(printed == "__C.NSCopying & __C.NSObject")

        let protocolTypes = try protocolTypes(inExistential: node)
        #expect(protocolTypes.count == 2)
        let protocolNames = try protocolTypes.map { protocolType -> String in
            #expect(protocolType.kind == .type)
            let protocolNode = try #require(protocolType.children.first)
            #expect(protocolNode.kind == .protocol)
            #expect(protocolNode.children.first?.text == "__C")
            return try #require(protocolNode.children.last?.text)
        }
        #expect(Set(protocolNames) == ["NSCopying", "NSObject"])
    }
}
