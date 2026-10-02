import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
import Demangling
import SwiftDeclarationRendering
import SwiftInterface
@testable import SwiftDump
@_spi(Internals) @testable import MachOSymbols
@testable import MachOTestingSupport
import MachOFixtureSupport

/// An on-the-fly fixture compiled twice from one class: as a main executable,
/// whose `__TEXT` sits at 0x100000000, and as a dylib, whose `__TEXT` sits at
/// 0 — the control. Both carry the linker's debug map (`-g`), so their symbol
/// tables also hold STABS entries.
///
/// A symbol table entry's value is a virtual address, while every offset
/// `MachOSwiftSection` keys by is a file offset. In a dylib the two coincide,
/// which is why the gap went unnoticed; in an executable they differ by the
/// base address, so the index filed every symbol 0x100000000 too high.
enum ExecutableImageFixture {
    enum Variant: String, CaseIterable, Sendable {
        case executable
        case library
    }

    static let moduleName = "ExecutableImageFixture"

    /// `alpha` and `beta` own vtable slots. `sharedNames` and `hiddenNames`
    /// are static stored properties, each with a STABS `N_GSYM` entry of the
    /// value 0 under its storage symbol's name. `hiddenNames` is internal, so
    /// its storage symbol is local, and the linker writes local symbols
    /// BEFORE the debug map — the order in which the entry overwrote the
    /// symbol. The class gives both builds a `__DATA` segment, as every
    /// on-the-fly fixture in this repository needs.
    static let librarySource = """
    open class OffsetHost {
        public var storedValue: Int = 0
        public init() {}
        open func alpha() -> Int { storedValue + 1 }
        open func beta() -> Int { storedValue + 2 }
        public static let sharedNames: [String] = ["first", "second"]
        static let hiddenNames: [String] = ["third"]
        public func hiddenCount() -> Int { Self.hiddenNames.count }
    }
    """

    static let mainSource = """
    let host = OffsetHost()
    print(host.alpha() + host.beta(), OffsetHost.sharedNames.count)
    """

    struct CompilationError: Swift.Error, CustomStringConvertible {
        let step: String
        let diagnostics: String
        var description: String { "\(ExecutableImageFixture.moduleName) fixture \(step) failed:\n\(diagnostics)" }
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

            let librarySourceURL = workingDirectory.appendingPathComponent("OffsetHost.swift")
            let mainSourceURL = workingDirectory.appendingPathComponent("main.swift")
            try librarySource.write(to: librarySourceURL, atomically: true, encoding: .utf8)
            try mainSource.write(to: mainSourceURL, atomically: true, encoding: .utf8)
            let executableURL = workingDirectory.appendingPathComponent(moduleName)
            let libraryURL = workingDirectory.appendingPathComponent("lib\(moduleName).dylib")
            // The language mode pinned so CI's toolchain and a newer local one
            // compile the same source the same way; `-g` leaves the debug map
            // in the symbol table.
            let commonArguments = ["swiftc", "-swift-version", "5", "-Onone", "-g", "-module-name", moduleName]
            try run(step: "swiftc (executable)", commonArguments + [librarySourceURL.path, mainSourceURL.path, "-o", executableURL.path])
            try run(step: "swiftc (library)", commonArguments + ["-emit-library", librarySourceURL.path, "-o", libraryURL.path])
            return [.executable: executableURL, .library: libraryURL]
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

    static func url(_ variant: Variant) throws -> URL {
        let products = try compilationResult.get()
        guard let url = products[variant] else {
            throw CompilationError(step: "lookup", diagnostics: "no product for variant \(variant.rawValue)")
        }
        return url
    }

    static func machOFile(_ variant: Variant) throws -> MachOFile {
        switch try MachOKit.loadFromFile(url: try url(variant)) {
        case .machO(let machOFile):
            return machOFile
        case .fat(let fatFile):
            let machOFile = try fatFile.machOFiles().first { $0.header.cpuType == .arm64 }
            return try #require(machOFile, "fixture unexpectedly missing an arm64 slice")
        }
    }

    /// The library loaded into the test process. The executable cannot be:
    /// `dlopen` refuses an `MH_EXECUTE` image.
    static func loadedLibraryImage() throws -> MachOImage {
        let libraryURL = try url(.library)
        _ = libraryURL.path.withCString { dlopen($0, RTLD_NOW) }
        let imageName = libraryURL.deletingPathExtension().lastPathComponent
        return try #require(MachOImage(name: imageName), "the fixture dylib did not load in-process")
    }
}

extension MachOFile.Symbol {
    /// A debug-map entry (`N_STAB`): it describes a symbol for the debugger
    /// and is not one. An `N_GSYM` entry carries the value 0.
    fileprivate var isDebuggingEntry: Bool {
        nlist.flags?.stab != nil
    }

    /// Defined in one of the image's sections — not an import, not an
    /// absolute value, not a debug-map entry.
    fileprivate var isDefinedInSection: Bool {
        !isDebuggingEntry && nlist.sectionNumber != nil
    }

    /// The entry's value, which is the symbol's virtual address.
    fileprivate var address: UInt64 {
        UInt64(bitPattern: Int64(offset))
    }
}

/// Symbol offsets in a main executable, and STABS entries in any image.
@Suite(.serialized, ExclusiveImageAccess(ExecutableImageFixture.moduleName))
struct ExecutableImageSymbolOffsetTests {
    private func interface(of machO: some MachOFieldLayoutRenderable) async throws -> String {
        var configuration = SwiftInterfaceBuilderConfiguration()
        configuration.printConfiguration.printVTableOffset = true
        configuration.printConfiguration.printMemberAddress = true
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

    private func hexadecimal(_ address: UInt64) -> String {
        String(address, radix: 16, uppercase: true)
    }

    private func definedSwiftSymbol(withSuffix suffix: String, in machOFile: MachOFile) throws -> MachOFile.Symbol {
        let symbol = machOFile.symbols.first { $0.isDefinedInSection && $0.name.isSwiftSymbol && $0.name.hasSuffix(suffix) }
        return try #require(symbol, "fixture is missing a defined symbol ending in \(suffix)")
    }

    // MARK: - Symbol offsets

    /// Every defined Swift symbol is found at its file offset — the
    /// accounting every descriptor-derived offset (a vtable slot's
    /// implementation, a witness) uses to ask for it.
    @Test(arguments: ExecutableImageFixture.Variant.allCases)
    func everySymbolIsIndexedAtItsFileOffset(variant: ExecutableImageFixture.Variant) throws {
        let machOFile = try ExecutableImageFixture.machOFile(variant)
        var checkedCount = 0
        var missedNames: [String] = []
        for symbol in machOFile.symbols where symbol.isDefinedInSection && symbol.name.isSwiftSymbol {
            let fileOffset = try #require(machOFile.fileOffset(of: symbol.address), "\(symbol.name) lies in no segment")
            let namesAtOffset = machOFile.symbols(offset: Int(fileOffset))?.map(\.name) ?? []
            if !namesAtOffset.contains(symbol.name) {
                missedNames.append(symbol.name)
            }
            checkedCount += 1
        }
        #expect(checkedCount > 10, "the fixture should define more Swift symbols than that")
        #expect(missedNames.isEmpty, "\(missedNames.count) of \(checkedCount) symbols not found at their file offset, e.g. \(missedNames.prefix(3))")
    }

    /// `swiftSymbols` vends the same offsets as the index, and no debug-map
    /// entry.
    @Test(arguments: ExecutableImageFixture.Variant.allCases)
    func swiftSymbolsCarryFileOffsets(variant: ExecutableImageFixture.Variant) throws {
        let machOFile = try ExecutableImageFixture.machOFile(variant)
        var expectedOffsetByName: [String: Int] = [:]
        for symbol in machOFile.symbols where symbol.isDefinedInSection && symbol.name.isSwiftSymbol {
            expectedOffsetByName[symbol.name] = Int(try #require(machOFile.fileOffset(of: symbol.address)))
        }
        var mismatchedNames: [String] = []
        for symbol in machOFile.swiftSymbols where expectedOffsetByName[symbol.name] != nil {
            if symbol.offset != expectedOffsetByName[symbol.name] {
                mismatchedNames.append(symbol.name)
            }
        }
        #expect(mismatchedNames.isEmpty, "\(mismatchedNames.count) symbols at the wrong offset, e.g. \(mismatchedNames.prefix(3))")
        let debuggingEntryNames = Set(machOFile.symbols.filter(\.isDebuggingEntry).map(\.name))
        let vendedNamesAtHeader = machOFile.swiftSymbols.filter { $0.offset == 0 && debuggingEntryNames.contains($0.name) }.map(\.name)
        #expect(vendedNamesAtHeader.isEmpty, "\(vendedNamesAtHeader)")
    }

    /// The symbolic-mangling table keys by the same accounting: its offsets
    /// are where the mangled names are READ from.
    @Test(arguments: ExecutableImageFixture.Variant.allCases)
    func symbolicManglingSymbolsSitAtTheirFileOffsets(variant: ExecutableImageFixture.Variant) throws {
        let machOFile = try ExecutableImageFixture.machOFile(variant)
        var expectedOffsetByName: [String: Int] = [:]
        for symbol in machOFile.symbols where symbol.isDefinedInSection && SymbolicManglingSymbolName.hasPrefix(symbol.name) {
            expectedOffsetByName[symbol.name] = Int(try #require(machOFile.fileOffset(of: symbol.address)))
        }
        try #require(!expectedOffsetByName.isEmpty, "premise: the fixture carries `_symbolic` symbols")
        let collectedSymbols = try #require(SymbolIndexStore.shared.symbolicManglingSymbols(in: machOFile))
        var collectedOffsetByName: [String: Int] = [:]
        for symbol in collectedSymbols {
            collectedOffsetByName[symbol.name] = symbol.offset
        }
        #expect(collectedOffsetByName == expectedOffsetByName)
    }

    /// A member's address comment is the address its symbol is defined at —
    /// what a disassembler opened on the same file shows.
    @Test(arguments: ExecutableImageFixture.Variant.allCases)
    func memberAddressesAreTheSymbolAddresses(variant: ExecutableImageFixture.Variant) async throws {
        let machOFile = try ExecutableImageFixture.machOFile(variant)
        let hostBlock = try #require(block(startingWith: "class OffsetHost", in: try await interface(of: machOFile)))

        let alphaSymbol = try definedSwiftSymbol(withSuffix: "5alphaSiyF", in: machOFile)
        let sharedNamesStorageSymbol = try definedSwiftSymbol(withSuffix: "11sharedNamesSaySSGvpZ", in: machOFile)
        let hiddenNamesStorageSymbol = try definedSwiftSymbol(withSuffix: "11hiddenNamesSaySSGvpZ", in: machOFile)
        #expect(hostBlock.contains("// Address: 0x\(hexadecimal(alphaSymbol.address))\n"), "\(hostBlock)")
        #expect(hostBlock.contains("// Address: 0x\(hexadecimal(sharedNamesStorageSymbol.address))\n"), "\(hostBlock)")
        // The local storage symbol, which its debug-map entry overwrote
        // with 0 — printed `Address: 0x0` before the fix.
        #expect(hostBlock.contains("// Address: 0x\(hexadecimal(hiddenNamesStorageSymbol.address))\n"), "\(hostBlock)")

        // No address may point anywhere but at a defined symbol.
        let symbolAddresses = Set(machOFile.symbols.filter(\.isDefinedInSection).map(\.address))
        let printedAddresses = hostBlock.matches(of: /Address[^:]*: 0x([0-9A-F]+)/).compactMap { UInt64($0.output.1, radix: 16) }
        #expect(!printedAddresses.isEmpty, "\(hostBlock)")
        let strayAddresses = printedAddresses.filter { !symbolAddresses.contains($0) }
        #expect(strayAddresses.isEmpty, "addresses naming no symbol: \(strayAddresses.map(hexadecimal))\n\(hostBlock)")
    }

    /// The vtable is joined to its symbols through the implementation
    /// offsets: every slot is named and the members print in slot order.
    @Test(arguments: ExecutableImageFixture.Variant.allCases)
    func vtableSlotsAreNamed(variant: ExecutableImageFixture.Variant) async throws {
        let machOFile = try ExecutableImageFixture.machOFile(variant)
        let hostDescriptor = try #require(try machOFile.swift.typeContextDescriptors.compactMap { wrapper -> ClassDescriptor? in
            guard case .class(let classDescriptor) = wrapper else { return nil }
            return try classDescriptor.name(in: machOFile.context) == "OffsetHost" ? classDescriptor : nil
        }.first)
        var configuration = DumperConfiguration.demangleOptions(.test)
        configuration.printVTableOffset = true
        let dump = try await Class(descriptor: hostDescriptor, in: machOFile.context).dump(using: configuration, in: machOFile).string
        #expect(!dump.contains("sub_"), "\(dump)")
        #expect(!dump.contains("unnamed vtable slot"), "\(dump)")

        let hostBlock = try #require(block(startingWith: "class OffsetHost", in: try await interface(of: machOFile)))
        let alphaRange = try #require(hostBlock.range(of: "func alpha()"), "\(hostBlock)")
        let betaRange = try #require(hostBlock.range(of: "func beta()"), "\(hostBlock)")
        #expect(alphaRange.lowerBound < betaRange.lowerBound, "members must print in slot order\n\(hostBlock)")
    }

    // MARK: - STABS entries

    /// A debug-map entry never decides where a symbol is filed. `N_GSYM`
    /// entries carry the value 0, so one indexed like a symbol was filed at
    /// the mach header; and since the table keeps the LAST value it saw for
    /// a name, every symbol listed before its debug-map entry — the local
    /// ones — took the value 0 (`memberAddressesAreTheSymbolAddresses` shows
    /// the printed result). The entry may still open its name's row, which
    /// keeps members in the debug map's (source) order; the SymbolTestsCore
    /// snapshot suites pin that order.
    @Test(arguments: ExecutableImageFixture.Variant.allCases)
    func debuggingEntriesNeverDecideAnOffset(variant: ExecutableImageFixture.Variant) throws {
        let machOFile = try ExecutableImageFixture.machOFile(variant)
        let debuggingEntryNames = Set(machOFile.symbols.filter { $0.isDebuggingEntry && $0.name.isSwiftSymbol && $0.offset == 0 }.map(\.name))
        try #require(!debuggingEntryNames.isEmpty, "premise: `-g` left `N_GSYM` entries in the symbol table")
        let namesAtHeader = machOFile.symbols(offset: 0)?.map(\.name) ?? []
        #expect(namesAtHeader.isEmpty, "\(namesAtHeader)")
    }

    /// RuntimeViewer's path: the image's own symbol table, read in-process.
    @Test func debuggingEntriesNeverDecideAnInProcessOffset() throws {
        let machOImage = try ExecutableImageFixture.loadedLibraryImage()
        try #require(machOImage.symbols.contains { $0.nlist.flags?.stab != nil && $0.name.isSwiftSymbol }, "premise: the loaded image's symbol table keeps its debug map")
        let namesAtHeader = machOImage.symbols(offset: 0)?.map(\.name) ?? []
        #expect(namesAtHeader.isEmpty, "\(namesAtHeader)")
    }
}
