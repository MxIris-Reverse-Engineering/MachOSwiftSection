import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
import SwiftDeclarationRendering
import SwiftInterface
@testable import MachOTestingSupport

/// An on-the-fly fixture for class members whose only symbol is their method
/// descriptor, compiled twice over: `.full` keeps every symbol, and
/// `.strippedLocals` is the same dylib after `strip -x`.
///
/// A library-evolution image keeps a public class method's implementation
/// symbol local and exports only its dispatch thunk (`Tj`) and method
/// descriptor (`Tq`), because clients call through the thunk — so the
/// stripped copy is in the position AppKit is in inside the OS dyld shared
/// cache: the vtable's implementations have no names left, while each slot's
/// `Tq` still names its member.
enum DescriptorOnlyMemberFixture {
    enum Variant: String, CaseIterable, Sendable {
        case full
        case strippedLocals
    }

    static let moduleName = "DescriptorOnlyMemberFixture"

    /// `DataSourceHost` mirrors the AppKit shape: generic over two `Hashable`
    /// parameters, stored and computed properties whose accessors own vtable
    /// slots, a non-failable initializer taking an Optional-returning closure,
    /// plain / `open` / `class` / `async` methods and a subscript — every one
    /// public, so the stripped build keeps a `Tq` for each — beside a `final`
    /// and a `static` method, which own no slot and whose implementations
    /// stay exported.
    ///
    /// `InternalSlotHost.hidden()` is internal: its method descriptor symbol
    /// is local like its implementation, so after `strip -x` nothing names
    /// its slot.
    static let source = """
    open class DataSourceHost<SectionIdentifier: Hashable, ItemIdentifier: Hashable> {
        public var rowProvider: ((Int) -> String)?
        public var defaultAnimation: Int = 0
        public var headerProvider: ((Int) -> String?)? {
            get { nil }
            set {}
        }
        public init(tableView: Int, cellProvider: @escaping (Int, ItemIdentifier) -> String?) {}
        public func snapshot() -> [ItemIdentifier] { [] }
        public func apply(_ snapshot: [ItemIdentifier], animatingDifferences: Bool) {}
        open func itemIdentifier(forRow row: Int) -> ItemIdentifier? { nil }
        public subscript(row: Int) -> ItemIdentifier? { nil }
        open class func makeDefaultAnimation() -> Int { 0 }
        open func reload() async -> Int { 0 }
        public final func finalHelper() {}
        public static func staticHelper() -> Int { 0 }
    }

    open class InternalSlotHost {
        public init() {}
        public func before() {}
        func hidden() {}
        public func after() {}
    }
    """

    struct CompilationError: Swift.Error, CustomStringConvertible {
        let step: String
        let diagnostics: String
        var description: String { "\(DescriptorOnlyMemberFixture.moduleName) fixture \(step) failed:\n\(diagnostics)" }
    }

    private enum WorkingDirectoryCleanup {
        nonisolated(unsafe) static var directories: [URL] = []
        static let registration: Void = {
            atexit {
                for directory in WorkingDirectoryCleanup.directories {
                    try? FileManager.default.removeItem(at: directory)
                }
            }
        }()
    }

    /// Compiled once per process.
    private static let compilationResult: Result<[Variant: URL], Swift.Error> = {
        Result {
            let workingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(moduleName)-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            _ = WorkingDirectoryCleanup.registration
            WorkingDirectoryCleanup.directories.append(workingDirectory)

            let sourceURL = workingDirectory.appendingPathComponent("Fixture.swift")
            try source.write(to: sourceURL, atomically: true, encoding: .utf8)
            let fullLibraryURL = workingDirectory.appendingPathComponent("lib\(moduleName)-\(Variant.full.rawValue).dylib")
            let strippedLibraryURL = workingDirectory.appendingPathComponent("lib\(moduleName)-\(Variant.strippedLocals.rawValue).dylib")
            try run(step: "swiftc", [
                // The language mode pinned: CI's toolchain and a newer local
                // one must compile the same source the same way. Library
                // evolution is the premise: without it the implementations
                // are exported and nothing is lost to stripping.
                "swiftc", "-swift-version", "5", "-emit-library", "-enable-library-evolution", "-Onone",
                "-module-name", moduleName,
                sourceURL.path, "-o", fullLibraryURL.path,
            ])
            try FileManager.default.copyItem(at: fullLibraryURL, to: strippedLibraryURL)
            // `strip -x` removes the local symbols and re-signs the dylib, so
            // the stripped copy still loads in-process.
            try run(step: "strip", ["strip", "-x", strippedLibraryURL.path])
            return [.full: fullLibraryURL, .strippedLocals: strippedLibraryURL]
        }
    }()

    private static func run(step: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = arguments
        let standardErrorPipe = Pipe()
        process.standardError = standardErrorPipe
        try process.run()
        // Drain BEFORE waitUntilExit, or a long diagnostic deadlocks both sides.
        let diagnosticsData = standardErrorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CompilationError(step: step, diagnostics: String(decoding: diagnosticsData, as: UTF8.self))
        }
    }

    static func libraryURL(_ variant: Variant) throws -> URL {
        let libraries = try compilationResult.get()
        guard let libraryURL = libraries[variant] else {
            throw CompilationError(step: "lookup", diagnostics: "no library for variant \(variant.rawValue)")
        }
        return libraryURL
    }

    static func machOFile(_ variant: Variant) throws -> MachOFile {
        switch try MachOKit.loadFromFile(url: try libraryURL(variant)) {
        case .machO(let machOFile):
            return machOFile
        case .fat(let fatFile):
            let machOFile = try fatFile.machOFiles().first { $0.header.cpuType == .arm64 }
            return try #require(machOFile, "fixture unexpectedly missing an arm64 slice")
        }
    }

    /// The `.strippedLocals` copy loaded into the test process — only that
    /// one: both copies define the same classes.
    static func loadedStrippedImage() throws -> MachOImage {
        let libraryURL = try libraryURL(.strippedLocals)
        _ = libraryURL.path.withCString { dlopen($0, RTLD_NOW) }
        let imageName = libraryURL.deletingPathExtension().lastPathComponent
        return try #require(MachOImage(name: imageName), "the stripped fixture dylib did not load in-process")
    }
}

/// Class members whose only symbol is their method descriptor (evolution
/// proposal `interface-descriptor-only-vtable-members`).
///
/// Once the local symbols are gone, a public class method's implementation
/// has no name at all, and the interface — which built every member from
/// implementation symbols — printed none of those members: AppKit's
/// `NSCollectionViewDiffableDataSource` came out as its `init` and `deinit`
/// alone. The vtable still names each slot through its descriptor's `Tq`
/// symbol; the interface now builds the member from that and prints the
/// class's vtable members in slot order, the way the dump walks them. A slot
/// nothing names is skipped.
///
/// The full build is the independent truth: stripping local symbols must not
/// change what the interface says about a class whose members are all public.
@Suite(.serialized, ExclusiveImageAccess(DescriptorOnlyMemberFixture.moduleName))
struct DescriptorOnlyVTableMemberTests {
    /// `DataSourceHost`'s declarations in source order: the stored properties
    /// first (they print from the field records), then every vtable member in
    /// slot order — which is declaration order — then the members that own
    /// no slot.
    private static let dataSourceHostDeclarations = [
        "var rowProvider: ((_: Swift.Int) -> Swift.String)?",
        "var defaultAnimation: Swift.Int",
        "var headerProvider: ((_: Swift.Int) -> Swift.String?)? {",
        "init(tableView: Swift.Int, cellProvider: @escaping (Swift.Int, B) -> Swift.String?)",
        "func snapshot() -> [B]",
        "func apply(_: [B], animatingDifferences: Swift.Bool)",
        "func itemIdentifier(forRow: Swift.Int) -> B?",
        "subscript(_: Swift.Int) -> B? {",
        "class func makeDefaultAnimation() -> Swift.Int",
        "func reload() async -> Swift.Int",
        "final func finalHelper()",
        "static func staticHelper() -> Swift.Int",
        "deinit",
    ]

    private func interface(of machO: some MachOFieldLayoutRenderable, printsDispatchComments: Bool) async throws -> String {
        var configuration = SwiftInterfaceBuilderConfiguration()
        configuration.printConfiguration.printVTableOffset = printsDispatchComments
        configuration.printConfiguration.printMemberAddress = printsDispatchComments
        let builder = try SwiftInterfaceBuilder(configuration: configuration, eventHandlers: [], in: machO)
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

    /// The declaration lines of a type block, in order: every line after the
    /// header that is not a comment, an accessor keyword, a closing brace or
    /// blank.
    private func declarations(in block: String) -> [String] {
        block.split(separator: "\n").dropFirst().compactMap { line in
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            guard !trimmedLine.isEmpty, !trimmedLine.hasPrefix("//"), trimmedLine != "}", trimmedLine != "get", trimmedLine != "set" else { return nil }
            return trimmedLine
        }
    }

    // MARK: - Descriptor-only members

    /// With vtable offsets and member addresses on, the stripped build prints
    /// the class exactly as the full build does — every slot's member, its
    /// slot and its implementation address included. The `async` method's
    /// descriptor points at its async function pointer, not at the code, so
    /// its address is the one that needs the extra hop to agree.
    @Test func strippedClassPrintsLikeTheFullBuild() async throws {
        let fullInterface = try await interface(of: try DescriptorOnlyMemberFixture.machOFile(.full), printsDispatchComments: true)
        let strippedInterface = try await interface(of: try DescriptorOnlyMemberFixture.machOFile(.strippedLocals), printsDispatchComments: true)
        let fullBlock = try #require(block(startingWith: "class DataSourceHost<", in: fullInterface), "\(fullInterface)")
        let strippedBlock = try #require(block(startingWith: "class DataSourceHost<", in: strippedInterface), "\(strippedInterface)")
        #expect(strippedBlock == fullBlock, "full:\n\(fullBlock)\n\nstripped:\n\(strippedBlock)")
    }

    /// Vtable members print in slot order — the source's declaration order —
    /// after the stored properties and before the members that own no slot,
    /// in both builds.
    @Test(arguments: DescriptorOnlyMemberFixture.Variant.allCases)
    func vtableMembersPrintInSlotOrder(variant: DescriptorOnlyMemberFixture.Variant) async throws {
        let interface = try await interface(of: try DescriptorOnlyMemberFixture.machOFile(variant), printsDispatchComments: false)
        let hostBlock = try #require(block(startingWith: "class DataSourceHost<", in: interface), "\(interface)")
        #expect(declarations(in: hostBlock) == Self.dataSourceHostDeclarations, "\(hostBlock)")
    }

    /// RuntimeViewer's path: the stripped image loaded into the process and
    /// read through `MachOImage`.
    @Test func strippedImageInProcessPrintsDescriptorOnlyMembers() async throws {
        let interface = try await interface(of: try DescriptorOnlyMemberFixture.loadedStrippedImage(), printsDispatchComments: false)
        let hostBlock = try #require(block(startingWith: "class DataSourceHost<", in: interface), "\(interface)")
        #expect(declarations(in: hostBlock) == Self.dataSourceHostDeclarations, "\(hostBlock)")
    }

    // MARK: - Unnamed slots

    /// A slot neither a `Tq` symbol nor an implementation symbol names is
    /// skipped — no placeholder, and its neighbours keep their places.
    @Test func unnamedSlotIsSkipped() async throws {
        let fullInterface = try await interface(of: try DescriptorOnlyMemberFixture.machOFile(.full), printsDispatchComments: false)
        let fullBlock = try #require(block(startingWith: "class InternalSlotHost", in: fullInterface), "\(fullInterface)")
        // The premise: the slot exists and the full build can name it.
        try #require(fullBlock.contains("func hidden()"), "\(fullBlock)")

        let strippedInterface = try await interface(of: try DescriptorOnlyMemberFixture.machOFile(.strippedLocals), printsDispatchComments: true)
        let strippedBlock = try #require(block(startingWith: "class InternalSlotHost", in: strippedInterface), "\(strippedInterface)")
        #expect(declarations(in: strippedBlock) == ["init()", "func before()", "func after()", "deinit"], "\(strippedBlock)")
        #expect(!strippedBlock.contains("sub_"), "\(strippedBlock)")
        #expect(!strippedBlock.contains("unnamed"), "\(strippedBlock)")
    }
}
