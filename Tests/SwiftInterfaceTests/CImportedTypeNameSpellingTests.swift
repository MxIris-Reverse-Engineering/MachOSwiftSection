import Foundation
import Testing
import MachOKit
@testable import MachOSwiftSection
@_spi(Support) @testable import SwiftPrinting
@_spi(Support) @testable import SwiftInterface
import SwiftDeclaration
import SwiftIndexing
@_spi(Internals) import SwiftInspection
import Semantic
import SwiftSectionTestingSupport

/// Evolution proposal `c-imported-type-name-spelling`: a C-imported type the
/// compiler knows by two names prints under one of them everywhere —
/// declaration, member types and extension headers.
///
/// The fixture's bridging header reproduces the shapes AttributeGraph and the
/// SDK have: a struct renamed with `swift_name` (`AGWeakAttribute` →
/// `AnyWeakAttribute`) holding an anonymous struct, a `swift_wrapper` typedef
/// renamed the same way (`AGAttribute` → `AnyAttribute`), and a typedef
/// imported as a member of another type (`NSAttributedStringKey` →
/// `NSAttributedString.Key`), whose descriptor keeps only the leaf.
@Suite
struct CImportedTypeNameSpellingTests {
    // MARK: - Fixture

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

    private static let fixtureHeader = """
    #import <Foundation/Foundation.h>
    #include <stdint.h>

    typedef uint32_t AGFooIdentifier __attribute__((swift_wrapper(struct))) __attribute__((swift_name("AnyFooIdentifier")));

    typedef struct __attribute__((swift_name("AnyFooThing"))) AGFooThing {
        struct {
            AGFooIdentifier identifier;
            uint32_t seed;
        } _details;
    } AGFooThing;

    typedef struct ProbeOwner {
        int value;
    } ProbeOwner;

    typedef NSString *ProbeOwnerKey __attribute__((swift_wrapper(struct))) __attribute__((swift_name("ProbeOwner.Key")));
    """

    /// `Anchor` keeps a `__DATA` segment in the dylib (see AGENTS.md,
    /// "On-the-fly-compiled fixture dylibs need a class"). The conformances
    /// put the C-imported types' descriptors into this image: the Swift-side
    /// `Equatable` of `AnyFooThing`, and the importer's synthesized `Hashable`
    /// of the two wrappers, reached through a generic function.
    private static let fixtureSource = """
    import Foundation

    public final class Anchor {}

    public struct Holder {
        public var thing: AnyFooThing
        public var identifier: AnyFooIdentifier
        public var key: ProbeOwner.Key

        public init(thing: AnyFooThing, identifier: AnyFooIdentifier, key: ProbeOwner.Key) {
            self.thing = thing
            self.identifier = identifier
            self.key = key
        }
    }

    extension AnyFooThing: Equatable {
        public static func == (left: AnyFooThing, right: AnyFooThing) -> Bool {
            left._details.identifier == right._details.identifier && left._details.seed == right._details.seed
        }
    }

    @inline(never) public func hashValue<Value: Hashable>(of value: Value) -> Int { value.hashValue }
    @inline(never) public func isEqual<Value: Equatable>(_ left: Value, _ right: Value) -> Bool { left == right }

    public func exercise(_ holder: Holder) -> (Int, Int, Bool) {
        (hashValue(of: holder.identifier), hashValue(of: holder.key), isEqual(holder.thing, holder.thing))
    }
    """

    private static let fixtureCompilationResult: Result<URL, any Swift.Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("CImportedTypeNameSpellingFixture-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            _ = FixtureWorkingDirectoryCleanup.registration
            FixtureWorkingDirectoryCleanup.directories.append(workingDirectory)

            let headerURL = workingDirectory.appendingPathComponent("CImportedTypeNameSpellingFixture.h")
            let sourceURL = workingDirectory.appendingPathComponent("CImportedTypeNameSpellingFixture.swift")
            let libraryURL = workingDirectory.appendingPathComponent("libCImportedTypeNameSpellingFixture.dylib")
            try fixtureHeader.write(to: headerURL, atomically: true, encoding: .utf8)
            try fixtureSource.write(to: sourceURL, atomically: true, encoding: .utf8)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = [
                "swiftc", "-emit-library", "-module-name", "CImportedTypeNameSpellingFixture",
                "-target", "arm64-apple-macosx15.0",
                "-import-objc-header", headerURL.path,
                sourceURL.path, "-o", libraryURL.path,
            ]
            let standardErrorPipe = Pipe()
            process.standardError = standardErrorPipe
            try process.run()
            // Drain BEFORE waitUntilExit, or a long diagnostic deadlocks both sides.
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
        var description: String { "C-imported type name spelling fixture compilation failed:\n\(diagnostics)" }
    }

    private func loadFixtureMachOFile() throws -> MachOFile {
        try HostSlice.machOFile(at: Self.fixtureCompilationResult.get())
    }

    /// Records every query, and answers the ones it was set up to answer.
    private final class RecordingResolver: ModuleNameResolving, CImportedNameResolving, @unchecked Sendable {
        private let lock = NSLock()
        private var recordedQueryCount = 0
        private let moduleNamesByTypeName: [String: String]
        private let swiftNamesByCName: [String: String]

        init(moduleNamesByTypeName: [String: String], swiftNamesByCName: [String: String] = [:]) {
            self.moduleNamesByTypeName = moduleNamesByTypeName
            self.swiftNamesByCName = swiftNamesByCName
        }

        var queryCount: Int {
            lock.withLock { recordedQueryCount }
        }

        func moduleName(forTypeName typeName: String) async -> String? {
            lock.withLock { recordedQueryCount += 1 }
            return moduleNamesByTypeName[typeName]
        }

        func swiftName(forCName cName: String, category: CImportedTypeNameCategory) async -> String? {
            lock.withLock { recordedQueryCount += 1 }
            return swiftNamesByCName[cName]
        }
    }

    private func makeBuilder(spelling: CImportedTypeNameSpelling = .swiftName, marksCImportedTypeNames: Bool = false, resolver: RecordingResolver? = nil) async throws -> SwiftInterfaceBuilder<MachOFile> {
        var printConfiguration = SwiftDeclarationPrintConfiguration()
        printConfiguration.cImportedTypeNameSpelling = spelling
        printConfiguration.marksCImportedTypeNames = marksCImportedTypeNames
        var configuration = SwiftInterfaceBuilderConfiguration()
        configuration.indexConfiguration = SwiftDeclarationIndexConfiguration(showCImportedTypes: true)
        configuration.printConfiguration = printConfiguration
        let builder = try SwiftInterfaceBuilder(configuration: configuration, eventHandlers: [], in: loadFixtureMachOFile())
        if let resolver {
            builder.printer.addTypeNameResolver(resolver)
        }
        try await builder.prepare()
        return builder
    }

    private func buildInterface(spelling: CImportedTypeNameSpelling = .swiftName, resolver: RecordingResolver? = nil) async throws -> String {
        try await makeBuilder(spelling: spelling, resolver: resolver).printRoot().string
    }

    private func lines(of interface: String, startingWith prefix: String) -> [String] {
        interface.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix(prefix) }
    }

    // MARK: - Trusting a descriptor's name

    @Test("A descriptor name is trusted when it is the type's whole Swift name", arguments: [
        ("AnyWeakAttribute", "AGWeakAttribute"),
        ("AnyAttribute", "AGAttribute"),
        ("CGColor", "CGColorRef"),
        ("__UIPointerShape", "UIPointerShape"),
    ])
    func trustsUserFacingNameWhenABINameDiffers(userFacingName: String, abiName: String) {
        let importInfo = TypeImportInfo(abiName: abiName, symbolNamespace: nil, relatedEntityName: nil)
        #expect(CImportedTypeSwiftNameTable.trustsUserFacingName(userFacingName, importInfo: importInfo))
    }

    /// A type imported as a member keeps only its leaf; a top-level rename of
    /// the same shape is refused with it.
    @Test("A leaf the C name ends with is not trusted", arguments: [
        ("Key", "NSAttributedStringKey"),
        ("Name", "NSNotificationName"),
        ("Decimal", "NSDecimal"),
    ])
    func refusesLeafNameOfTypeImportedAsMember(userFacingName: String, abiName: String) {
        let importInfo = TypeImportInfo(abiName: abiName, symbolNamespace: nil, relatedEntityName: nil)
        #expect(!CImportedTypeSwiftNameTable.trustsUserFacingName(userFacingName, importInfo: importInfo))
    }

    @Test func refusesRelatedEntityName() {
        let importInfo = TypeImportInfo(abiName: "CKErrorCode", symbolNamespace: nil, relatedEntityName: "e")
        #expect(!CImportedTypeSwiftNameTable.trustsUserFacingName("CKError", importInfo: importInfo))
    }

    @Test func refusesNameWithoutABIName() {
        let importInfo = TypeImportInfo(abiName: nil, symbolNamespace: TypeImportInfo.cTypedefSymbolNamespace, relatedEntityName: nil)
        #expect(!CImportedTypeSwiftNameTable.trustsUserFacingName("CGRect", importInfo: importInfo))
    }

    @Test func nameTableReadsTheFixturesDescriptors() throws {
        let machOFile = try loadFixtureMachOFile()
        let descriptors = try machOFile.swift.typeContextDescriptors
        let table = CImportedTypeSwiftNameTable(typeContextDescriptors: descriptors, in: machOFile.context)
        var swiftNamesByDescriptorName: [String: String?] = [:]
        for descriptorWrapper in descriptors where (try? descriptorWrapper.typeContextDescriptor.isCImportedContextDescriptor(in: machOFile.context)) == true {
            let descriptorName = try descriptorWrapper.namedContextDescriptor.name(in: machOFile.context)
            let identity = try SymbolicDemangler.demangleContext(for: descriptorWrapper.asContextDescriptorWrapper, in: machOFile.context)
            swiftNamesByDescriptorName[descriptorName] = table.swiftName(forIdentity: identity)
        }
        #expect(swiftNamesByDescriptorName["AnyFooThing"] == .some("AnyFooThing"))
        #expect(swiftNamesByDescriptorName["AnyFooIdentifier"] == .some("AnyFooIdentifier"))
        // Imported as `ProbeOwner.Key`: the descriptor says `Key`, which is not trusted.
        #expect(swiftNamesByDescriptorName["Key"] == .some(nil))
        // The anonymous struct keeps its own name and has no entry.
        #expect(swiftNamesByDescriptorName["__Unnamed_struct__details"] == .some(nil))
    }

    // MARK: - Spelling Swift names

    @Test func swiftSpellingPrintsBareSwiftNameWhenModuleIsUnknown() async throws {
        let interface = try await buildInterface()
        #expect(interface.contains("struct AnyFooThing {"), "\(interface)")
        #expect(interface.contains("var _details: AnyFooThing.__Unnamed_struct__details"), "\(interface)")
        #expect(interface.contains("var identifier: AnyFooIdentifier"), "\(interface)")
        #expect(interface.contains("var thing: AnyFooThing"), "\(interface)")
        let equatableLines = lines(of: interface, startingWith: "extension AnyFooThing: ")
        #expect(equatableLines.contains { $0.contains("Swift.Equatable") }, "\(interface)")
        #expect(!interface.contains("AGFooThing"), "\(interface)")
        #expect(!interface.contains("AGFooIdentifier"), "\(interface)")
    }

    @Test func untrustedDeclaredNamePrintsCName() async throws {
        let interface = try await buildInterface()
        #expect(interface.contains("struct ProbeOwnerKey {"), "\(interface)")
        #expect(!interface.contains("struct Key {"), "\(interface)")
        #expect(interface.contains("var key: __C.ProbeOwnerKey"), "\(interface)")
        #expect(!lines(of: interface, startingWith: "extension __C.ProbeOwnerKey: ").isEmpty, "\(interface)")
    }

    @Test func swiftSpellingKeepsModuleThatResolverFinds() async throws {
        let resolver = RecordingResolver(
            moduleNamesByTypeName: ["AGFooThing": "ProbeModule", "ProbeOwnerKey": "ProbeModule"],
            swiftNamesByCName: ["ProbeOwnerKey": "ProbeOwner.Key"]
        )
        let interface = try await buildInterface(resolver: resolver)
        // The resolver finds the module but has no Swift name: the descriptor's.
        #expect(interface.contains("var thing: ProbeModule.AnyFooThing"), "\(interface)")
        #expect(!lines(of: interface, startingWith: "extension ProbeModule.AnyFooThing: ").isEmpty, "\(interface)")
        #expect(interface.contains("struct AnyFooThing {"), "\(interface)")
        // The resolver spells the member import whole.
        #expect(interface.contains("var key: ProbeModule.ProbeOwner.Key"), "\(interface)")
        #expect(!lines(of: interface, startingWith: "extension ProbeModule.ProbeOwner.Key: ").isEmpty, "\(interface)")
        #expect(interface.contains("struct ProbeOwner.Key {"), "\(interface)")
        // Nothing found for the wrapper: the descriptor's name, alone.
        #expect(interface.contains("var identifier: AnyFooIdentifier"), "\(interface)")
    }

    @Test func extensionHeaderSpellsLikeMemberTypes() async throws {
        let interface = try await buildInterface()
        let extensionLines = lines(of: interface, startingWith: "extension ")
        #expect(!extensionLines.isEmpty, "\(interface)")
        for line in extensionLines {
            #expect(!line.hasPrefix("extension __C.AGFoo"), "\(line)")
        }
    }

    // MARK: - Spelling C names

    @Test func cSpellingPrintsMangledNamesAndAsksNoResolver() async throws {
        let resolver = RecordingResolver(moduleNamesByTypeName: ["AGFooThing": "ProbeModule", "ProbeOwnerKey": "ProbeModule"])
        let interface = try await buildInterface(spelling: .cName, resolver: resolver)
        #expect(interface.contains("struct AGFooThing {"), "\(interface)")
        #expect(interface.contains("var _details: __C.AGFooThing.__Unnamed_struct__details"), "\(interface)")
        #expect(interface.contains("var identifier: __C.AGFooIdentifier"), "\(interface)")
        #expect(interface.contains("var thing: __C.AGFooThing"), "\(interface)")
        #expect(!lines(of: interface, startingWith: "extension __C.AGFooThing: ").isEmpty, "\(interface)")
        #expect(interface.contains("struct ProbeOwnerKey {"), "\(interface)")
        #expect(!interface.contains("AnyFooThing"), "\(interface)")
        #expect(!interface.contains("ProbeModule"), "\(interface)")
        #expect(resolver.queryCount == 0)
    }

    // MARK: - Marking declared names

    @Test func markedDeclaredNameCarriesBothSpellings() async throws {
        let unmarked = try await makeBuilder().printRoot().frozen()
        let marked = try await makeBuilder(marksCImportedTypeNames: true).printRoot().frozen()
        let separated = marked.separatingAnnotationRegions()
        #expect(separated.text == unmarked)
        #expect(unmarked.separatingAnnotationRegions().annotations.isEmpty)

        let printedBytes = Array(separated.text.string.utf8)
        var markedNames: [CImportedTypeNames: String] = [:]
        for region in separated.annotations.regions {
            guard let names = region.kind.cImportedTypeNames else { continue }
            let regionStart = Int(region.utf8Offset)
            markedNames[names] = String(decoding: printedBytes[regionStart ..< regionStart + Int(region.utf8Length)], as: UTF8.self)
        }
        #expect(markedNames == [
            CImportedTypeNames(swiftName: "AnyFooThing", cName: "AGFooThing"): "AnyFooThing",
            CImportedTypeNames(swiftName: "AnyFooIdentifier", cName: "AGFooIdentifier"): "AnyFooIdentifier",
        ])
    }

    @Test func markedCSpellingCarriesTheSameNames() async throws {
        let marked = try await makeBuilder(spelling: .cName, marksCImportedTypeNames: true).printRoot().frozen()
        let separated = marked.separatingAnnotationRegions()
        let printedBytes = Array(separated.text.string.utf8)
        let region = try #require(separated.annotations.regions(ofKind: .cImportedTypeName(CImportedTypeNames(swiftName: "AnyFooThing", cName: "AGFooThing"))).first)
        let regionStart = Int(region.utf8Offset)
        #expect(String(decoding: printedBytes[regionStart ..< regionStart + Int(region.utf8Length)], as: UTF8.self) == "AGFooThing")
    }

    @Test func sameSpellingsAreNotMarked() async throws {
        let marked = try await makeBuilder(marksCImportedTypeNames: true).printRoot().frozen()
        let names = marked.separatingAnnotationRegions().annotations.regions.compactMap(\.kind.cImportedTypeNames)
        // `ProbeOwnerKey` has no known Swift name without a resolver, and
        // the anonymous struct has one name only.
        #expect(!names.contains { $0.cName == "ProbeOwnerKey" || $0.cName == "__Unnamed_struct__details" })
    }

    @Test func regionKindRoundTripsDottedSwiftName() {
        let names = CImportedTypeNames(swiftName: "NSAttributedString.Key", cName: "NSAttributedStringKey")
        #expect(AnnotationRegion.Kind.cImportedTypeName(names).cImportedTypeNames == names)
        #expect(AnnotationRegion.Kind.note.cImportedTypeNames == nil)
        #expect(AnnotationRegion.Kind("cImportedTypeName").cImportedTypeNames == nil)
    }
}
