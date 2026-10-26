import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSymbols
import MachOTestingSupport
import MachOFixtureSupport

/// A host's wrapper — MachOKitUI's `MachOFileSource` / `MachOImageSource` —
/// around a reader of the system dyld shared cache.
///
/// A file read out of a cache files its symbols at `value − sharedRegionStart`,
/// and an in-process cache image counts its addresses from where it is loaded.
/// Both were worked out only for a bare reader, so a wrapper's symbols stayed at
/// their raw values and its addresses were counted from the start of the shared
/// region.
///
/// Combine is an image no other suite reads, so the symbol index this suite
/// builds for it is built through the wrapper.
@Suite(ExclusiveImageAccess(MachOImageName.Combine.rawValue))
struct WrappedReaderSymbolTests {
    @Test("a wrapper of a cache file files its Swift symbols where the file does")
    func cacheFileWrapperFilesSwiftSymbolsLikeTheFile() throws {
        let combine = try Self.combineInSystemCache()
        let wrapper = ForwardingMachOReader<MachOFile, DeclaredWrapper>(combine)
        #expect(wrapper.swiftSymbols == combine.swiftSymbols)
    }

    @Test("a wrapper of a cache file finds the file's type descriptor symbols at their offsets")
    func cacheFileWrapperIndexesSymbolsAtTheirOffsets() throws {
        let combine = try Self.combineInSystemCache()
        let wrapper = ForwardingMachOReader<MachOFile, DeclaredWrapper>(combine)
        // Combine's own nominal type descriptors: the symbol table also lists
        // the descriptors Combine imports (`$ss12StaticStringVMn`), which sit
        // at no offset in it.
        let descriptorSymbols = combine.swiftSymbols.filter { $0.name.hasSuffix("Mn") && $0.name.contains("$s7Combine") }
        try #require(!descriptorSymbols.isEmpty)
        for descriptorSymbol in descriptorSymbols {
            let symbolsAtOffset = wrapper.symbols(offset: descriptorSymbol.offset)
            #expect(symbolsAtOffset?.contains { $0.name == descriptorSymbol.name } == true, "\(descriptorSymbol.name)")
        }
    }

    @Test("a wrapper of an in-process cache image prints the image's addresses")
    func inProcessCacheImageWrapperPrintsTheImageAddresses() throws {
        let foundation = try #require(MachOImage(named: .Foundation))
        try #require(foundation.cache != nil, "Foundation is expected to be loaded from the shared cache")
        let wrapper = ForwardingMachOReader<MachOImage, DeclaredWrapper>(foundation)
        for offset in [0, 0x1000, 0x10_0000] {
            #expect(wrapper.address(forOffset: offset) == foundation.address(forOffset: offset))
        }
    }

    private static func combineInSystemCache() throws -> MachOFile {
        let fullCache = try FullDyldCache(path: .current)
        return try #require(fullCache.machOFile(named: .Combine))
    }
}
