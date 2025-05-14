import Testing
import Foundation
@testable import MachOSwiftSection
import MachOKit

@Suite
struct DyldCacheFileSwiftSectionTests {
    enum Error: Swift.Error {
        case notFound
    }

    let mainCache: DyldCache

    let mainCacheMachOFileInCache: MachOFile
    
    let subCache: DyldCache

    let subCacheMachOFileInCache: MachOFile

    init() throws {
        // Cache
        let arch = "arm64e"
//        let mainCachePath = "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_\(arch)"
//        let subCachePath = "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_\(arch).01"
        let mainCachePath = "/Volumes/Resources/24F74__MacOS/dyld_shared_cache_\(arch)"
        let subCachePath = "/Volumes/Resources/24F74__MacOS/dyld_shared_cache_\(arch).01"
        let mainCacheURL = URL(fileURLWithPath: mainCachePath)
        let subCacheURL = URL(fileURLWithPath: subCachePath)
        self.mainCache = try! DyldCache(url: mainCacheURL)
        self.subCache = try! DyldCache(subcacheUrl: subCacheURL, mainCacheHeader: mainCache.mainCacheHeader)
        self.mainCacheMachOFileInCache = mainCache.machOFiles().first(where: {
            $0.imagePath.contains("/AppKit")
        })!
        self.subCacheMachOFileInCache = subCache.machOFiles().first(where: {
            $0.imagePath.contains("/CodableSwiftUI")
        })!
    }

    @Test func protocolsInFile() async throws {
        guard let protocols = subCacheMachOFileInCache.swift.protocolDescriptors else {
            throw Error.notFound
        }
        for proto in protocols {
            try print(proto.name(in: subCacheMachOFileInCache))
        }
    }

    @Test func typeContextDescriptorsInFile() async throws {
        do {
            try await Dump.dumpTypeContextDescriptors(in: mainCacheMachOFileInCache)
        } catch {
            print(error)
        }
    }
    
    @Test func cacheFileOffsets() async throws {
        for machOFile in mainCache.machOFiles() {
            print(machOFile.imagePath, machOFile.headerStartOffsetInCache)
        }
    }

    @Test func address() async throws {
//        let fileOffset: Int = 1733616806
//        let relativeOffset: Int32 = 149429722
//        let ptr = RelativeIndirectPointer<ContextDescriptorWrapper?, SignedPointer<ContextDescriptorWrapper?>>(relativeOffset: relativeOffset)
//        print(ptr.resolveDirectFileOffset(from: fileOffset))
//        print(try ptr.resolveIndirectFileOffset(from: fileOffset, in: machOFileInCache))
//        let ctx = try ptr.resolve(from: fileOffset, in: machOFileInCache)
//        print(ctx)
//        print(try ctx?.name(in: machOFileInCache))
//        guard let ctx = try machOFileInCache.swift._readContextDescriptor(from: 3911727420, in: machOFileInCache) else { return }
//        let ptr = RelativeDirectPointer<MangledName>(relativeOffset: ctx.namedContextDescriptor!.layout.name.relativeOffset)
//        let mangledName = try ptr.resolve(from: ctx.contextDescriptor.offset + 8, in: machOFileInCache)
//        print(try Demangler.demangle(for: mangledName, in: machOFileInCache))
//        if case let .type(type) = try RelativeIndirectPointer<ContextDescriptorWrapper?, SignedPointer<ContextDescriptorWrapper?>>(relativeOffset: 278655386).resolve(from: 1733619446, in: machOFileInCache) {
//            try print(type.typeContextDescriptor.typeGenericContext(in: machOFileInCache))
//        }
        
//        let offset: Int = 1764186844
//        let context: ContextDescriptor = try mainCache.fileHandle.machO.read(offset: 19328401408.cast())
//        print(context)
//        print(try mainCache.fileHandle.machO.read(offset: 1576349376) as UInt64)
//        print(7161005382531642213 & 0x7FFFFFFF)
//        print(mainCacheMachOFileInCache.cacheAndFileOffset(fromStart: 1576349376))
//        print(try mainCacheMachOFileInCache.swift._readContextDescriptor(from: 1576349376))
        let offset: UInt64 = 149347956 + 4 + 1427001416
        print(offset)
        let address = try subCache.fileHandle.machO.read(offset: subCacheMachOFileInCache.cacheAndFileOffset(for: offset + subCache.header.sharedRegionStart)!.1.cast()) as UInt64
        print(address)
        let newOffset: Int = subCacheMachOFileInCache.cacheAndFileOffset(for: numericCast(address & 0x7FFFFFFF) + subCache.header.sharedRegionStart)!.1.cast()
        print(newOffset)
        let layout = (try subCache.fileHandle.machO.read(offset: newOffset.cast()) as ContextDescriptor.Layout)
        print(ContextDescriptor(layout: layout, offset: newOffset))
    }
}
