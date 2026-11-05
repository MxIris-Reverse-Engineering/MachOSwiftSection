import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
import MachOFixtureSupport
import SwiftThunkAnalysis

/// `AccessorThunkReader.read` makes a new thunk environment for every thunk,
/// so what an environment reads from the image or its dyld cache to name a
/// call target has to be read once per image, not once per environment.
///
/// Two tables were rebuilt per environment, so per thunk: the image's own
/// runtime symbols, picked out of the whole symbol table — about a sixth of
/// reading SwiftUI's interface offline — and the address table of every image
/// in the cache, with the image opened for each target found there.
///
/// After one environment has named a target, a fresh environment must name
/// it with lookups, not by reading the table again. Reading the table is
/// timed directly as the yardstick, so the comparison holds on a busy machine
/// as well as an idle one.
@Suite("Thunk environment image tables")
struct ThunkEnvironmentImageTablesTests {
    @Test("A fresh environment does not walk the symbol table again")
    func freshEnvironmentReusesTheImagesRuntimeSymbols() throws {
        let cache = try DyldCache(path: .current)
        let machOFile = try #require(cache.machOFile(named: .SwiftUI))
        // A type descriptor: inside the image and not a metadata accessor,
        // so a lookup gets as far as the image's own runtime symbols.
        let descriptor = try #require(try machOFile.swift.typeContextDescriptors.first)
        let address = try #require(ThunkAddressSpace(of: machOFile).address(forOffset: descriptor.typeContextDescriptor.offset))

        // Builds everything the environment shares per image — the accessor
        // index, the symbol index — and pages the symbol table in.
        _ = MachOThunkEnvironment(machO: machOFile).callee(at: address)

        let symbolTableWalkNanoseconds = Self.nanoseconds {
            var nameByteCount = 0
            for symbol in machOFile.symbols {
                nameByteCount &+= symbol.name.utf8.count
            }
            #expect(nameByteCount > 0)
        }
        let freshEnvironmentLookupNanoseconds = Self.nanoseconds {
            _ = MachOThunkEnvironment(machO: machOFile).callee(at: address)
        }

        #expect(freshEnvironmentLookupNanoseconds * 5 < symbolTableWalkNanoseconds)
    }

    @Test("A fresh environment does not read the cache's image list again")
    func freshEnvironmentReusesTheCachesImageTable() throws {
        let cache = try DyldCache(path: .current)
        let machOFile = try #require(cache.machOFile(named: .SwiftUI))
        let swiftCore = try #require(cache.machOFile(by: .path("/usr/lib/swift/libswiftCore.dylib")))
        // A runtime entry point another image of the cache exports: naming it
        // goes through the table of the cache's images.
        let exportedSymbol = try #require(swiftCore.exportTrie?.search(by: "_swift_getWitnessTable"))
        let exportedSymbolOffset = try #require(exportedSymbol.offset)
        let address = try #require(ThunkAddressSpace(of: swiftCore).address(forExportedSymbolOffset: exportedSymbolOffset))

        #expect(MachOThunkEnvironment(machO: machOFile).callee(at: address) == .witnessTableLookup)

        let mainCache = cache.mainCache ?? cache
        let imageInfos = try #require(mainCache.imageInfos)
        let imageListReadNanoseconds = Self.nanoseconds {
            var pathByteCount = 0
            for imageInfo in imageInfos {
                pathByteCount &+= imageInfo.path(in: mainCache)?.utf8.count ?? 0
            }
            #expect(pathByteCount > 0)
        }
        var freshEnvironmentCallee: ThunkCallee?
        let freshEnvironmentLookupNanoseconds = Self.nanoseconds {
            freshEnvironmentCallee = MachOThunkEnvironment(machO: machOFile).callee(at: address)
        }

        #expect(freshEnvironmentCallee == .witnessTableLookup)
        #expect(freshEnvironmentLookupNanoseconds * 5 < imageListReadNanoseconds)
    }

    private static func nanoseconds(of body: () -> Void) -> UInt64 {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        return DispatchTime.now().uptimeNanoseconds - start
    }
}
