import Foundation
import Testing
import MachOKit
@_spi(Internals) @testable import MachOSymbols
@_spi(Internals) import MachOCaches
@testable import MachOTestingSupport
import MachOFixtureSupport

/// The collection layer of evolution proposal `symbolic-mangling-symbol-index`:
/// the build sweep gathers every `_symbolic ` / `_default assoc type ` symbol
/// into a table of its own — on both collection legs exactly the population a
/// `String`-based pass over the symbol table finds — and keeps them out of the
/// offset index, whose callers expect names that demangle.
///
/// Anchored on AppKit, whose macOS 26 dyld shared cache image carries these
/// symbols.
@Suite(.serialized)
struct SymbolicManglingSymbolCollectionTests {
    private static let appKitPath = "/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit"

    private static var runsOnMacOS26OrLater: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0))
    }

    /// The byte-level prefix test restates `SymbolicManglingSymbolName.hasPrefix(_:)`
    /// and would silently diverge from it if either changed alone.
    @Test(.enabled(if: runsOnMacOS26OrLater, "AppKit's symbolic-mangling symbols are pinned on macOS 26"))
    func byteLevelPrefixCheckMatchesStringCheck() throws {
        let machOImage = try Self.loadedAppKitImage()
        let symbols64 = try #require(machOImage.symbols64)
        var checkedCount = 0
        var prefixedCount = 0
        var mismatchCount = 0
        for symbol in symbols64 {
            let byteLevelVerdict = nameBytesHaveSymbolicManglingSymbolPrefix(symbol.nameC)
            if byteLevelVerdict != SymbolicManglingSymbolName.hasPrefix(symbol.name) {
                mismatchCount += 1
                if mismatchCount <= 3 {
                    Issue.record("byte-level prefix check mismatch for \(symbol.name)")
                }
            }
            if byteLevelVerdict {
                prefixedCount += 1
            }
            checkedCount += 1
        }
        #expect(mismatchCount == 0)
        #expect(prefixedCount > 0, "the check must have met the prefix at all to prove anything")
        #expect(checkedCount > prefixedCount)
    }

    @Test(.enabled(if: runsOnMacOS26OrLater, "AppKit's symbolic-mangling symbols are pinned on macOS 26"))
    func imageLegCollectsExactlyThePrefixedLocalSymbols() throws {
        let machOImage = try Self.loadedAppKitImage()
        var expectedOffsetByName: [String: Int] = [:]
        for symbol in machOImage.symbols where SymbolicManglingSymbolName.hasPrefix(symbol.name) && !symbol.nlist.isExternal {
            expectedOffsetByName[symbol.name] = symbol.offset
        }
        let collectedSymbols = try #require(SymbolIndexStore.shared.symbolicManglingSymbols(in: machOImage))

        try Self.expectCollection(collectedSymbols, equals: expectedOffsetByName)
    }

    /// A cache image's symbol offsets are unslid addresses; the collected
    /// offsets are measured from the shared region's start, like every other
    /// offset the index vends.
    @Test(.enabled(if: runsOnMacOS26OrLater, "AppKit's symbolic-mangling symbols are pinned on macOS 26"))
    func fileLegCollectsExactlyThePrefixedLocalSymbols() throws {
        let machOFile = try Self.appKitFileInSystemCache()
        let sharedRegionStart = Int(try #require(machOFile.cache).mainCacheHeader.sharedRegionStart)
        var expectedOffsetByName: [String: Int] = [:]
        for symbol in machOFile.symbols where SymbolicManglingSymbolName.hasPrefix(symbol.name) && !symbol.nlist.isExternal {
            expectedOffsetByName[symbol.name] = symbol.offset - sharedRegionStart
        }
        let collectedSymbols = try #require(SymbolIndexStore.shared.symbolicManglingSymbols(in: machOFile))

        try Self.expectCollection(collectedSymbols, equals: expectedOffsetByName)
    }

    /// Neither the offset query nor the name membership query may ever answer
    /// with a symbolic-mangling symbol: both are answered from the main table.
    @Test(.enabled(if: runsOnMacOS26OrLater, "AppKit's symbolic-mangling symbols are pinned on macOS 26"))
    func symbolicManglingSymbolsStayOutOfTheMainTable() throws {
        let machOFile = try Self.appKitFileInSystemCache()
        let collectedSymbols = try #require(SymbolIndexStore.shared.symbolicManglingSymbols(in: machOFile))
        try #require(!collectedSymbols.isEmpty)
        var leakedCount = 0
        for symbol in collectedSymbols {
            let symbolsAtOffset = SymbolIndexStore.shared.symbols(for: symbol.offset, in: machOFile).map { Array($0) } ?? []
            if symbolsAtOffset.contains(where: { SymbolicManglingSymbolName.hasPrefix($0.name) }) || SymbolIndexStore.shared.containsSymbol(named: symbol.name, in: machOFile) {
                leakedCount += 1
                if leakedCount <= 3 {
                    Issue.record("\(symbol.name) is visible through the main table")
                }
            }
        }
        #expect(leakedCount == 0)
    }

    @Test func symbolNameSplitsIntoRoleMangledNameAndReferents() throws {
        let delegateName = try #require(SymbolicManglingSymbolName("_symbolic ______pSgXw 6AppKit32TextShadowViewControllerDelegate33_05EA0EB8E781FFE22747790FC22932B1LLP"))
        #expect(delegateName.role == .symbolic)
        #expect(delegateName.mangledNameWithPlaceholders == "______pSgXw")
        #expect(delegateName.referentManglings == ["6AppKit32TextShadowViewControllerDelegate33_05EA0EB8E781FFE22747790FC22932B1LLP"])

        // The second referent leans on the first (`AA` is `Main`), so the two
        // only mean something demangled together — splitting just separates them.
        let twoReferenceName = try #require(SymbolicManglingSymbolName("_default assoc type _____y_____G 4Main5OuterV AA5InnerV"))
        #expect(twoReferenceName.role == .defaultAssociatedTypeWitness)
        #expect(twoReferenceName.mangledNameWithPlaceholders == "_____y_____G")
        #expect(twoReferenceName.referentManglings == ["4Main5OuterV", "AA5InnerV"])

        let referencelessName = try #require(SymbolicManglingSymbolName("_symbolic Si"))
        #expect(referencelessName.mangledNameWithPlaceholders == "Si")
        #expect(referencelessName.referentManglings.isEmpty)

        #expect(SymbolicManglingSymbolName("_$s6AppKit24FontPanelBIUSPopUpButtonCMn") == nil)
        #expect(SymbolicManglingSymbolName("_flat unique So8NSObjectC") == nil)
    }

    /// Acceptance evidence for the proposal's memory note: how many symbols
    /// each image has, how many carry referents, and what the collected table
    /// costs. Asserts the direction the proposal rests on — the images carry
    /// these symbols — and that the second prefix is really collected: AppKit
    /// has no default associated type witness, SwiftUICore does.
    @Test(.enabled(if: runsOnMacOS26OrLater, "AppKit's symbolic-mangling symbols are pinned on macOS 26"))
    func censusOfSystemCacheImages() throws {
        let cache = try DyldCache(path: .current)
        var censusLines: [String] = []
        for imageName in [MachOImageName.AppKit, .SwiftUICore] {
            let machOFile = try #require(cache.machOFile(named: imageName), "the running system's cache has no \(imageName)")
            let collectedSymbols = try #require(SymbolIndexStore.shared.symbolicManglingSymbols(in: machOFile))
            var symbolCount = 0
            var withReferentsCount = 0
            var referentCount = 0
            var defaultAssociatedTypeWitnessCount = 0
            for symbol in collectedSymbols {
                let symbolName = try #require(SymbolicManglingSymbolName(symbol.name))
                symbolCount += 1
                if !symbolName.referentManglings.isEmpty {
                    withReferentsCount += 1
                }
                referentCount += symbolName.referentManglings.count
                if symbolName.role == .defaultAssociatedTypeWitness {
                    defaultAssociatedTypeWitnessCount += 1
                }
            }
            let symbolTable = collectedSymbols.symbolTable
            let tableByteCount = symbolTable.rows.count * MemoryLayout<SymbolRow>.stride + symbolTable.rowsSortedByName.count * MemoryLayout<UInt32>.stride + symbolTable.privateNameBuffer.count
            censusLines.append("\(imageName): \(symbolCount) symbols, \(withReferentsCount) with referents, \(referentCount) referents, \(defaultAssociatedTypeWitnessCount) default assoc type, table \(tableByteCount) bytes (names \(symbolTable.privateNameBuffer.count))")
            #expect(withReferentsCount > 0, "\(imageName) carries no symbolic-mangling symbol with referents")
            if imageName == .SwiftUICore {
                #expect(defaultAssociatedTypeWitnessCount > 0, "SwiftUICore's default associated type witnesses were not collected")
            }
        }
        print("Symbolic-mangling symbol census —\n" + censusLines.joined(separator: "\n"))
    }

    // MARK: - Helpers

    private static func expectCollection(_ collectedSymbols: SymbolicManglingSymbols, equals expectedOffsetByName: [String: Int]) throws {
        try #require(!expectedOffsetByName.isEmpty, "the image must carry symbolic-mangling symbols for this to prove anything")
        #expect(collectedSymbols.count == expectedOffsetByName.count)
        var mismatchCount = 0
        for position in collectedSymbols.indices {
            let symbol = collectedSymbols[position]
            if expectedOffsetByName[symbol.name] != symbol.offset || collectedSymbols.position(ofSymbolNamed: symbol.name) != position {
                mismatchCount += 1
                if mismatchCount <= 3 {
                    Issue.record("position \(position) (\(symbol.name) at \(symbol.offset)) diverges from the String-based collection")
                }
            }
        }
        #expect(mismatchCount == 0)
    }

    /// The test process does not link AppKit, so it has to be mapped before a
    /// `MachOImage` can be made of it.
    private static func loadedAppKitImage() throws -> MachOImage {
        try #require(dlopen(appKitPath, RTLD_LAZY) != nil, "AppKit could not be loaded into the test process")
        return try #require(MachOImage(name: "AppKit"))
    }

    private static func appKitFileInSystemCache() throws -> MachOFile {
        let cache = try DyldCache(path: .current)
        return try #require(cache.machOFile(named: .AppKit), "the running system's cache has no AppKit")
    }
}
