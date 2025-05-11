import Testing
import Foundation
@_spi(Core) @testable import MachOSwiftSection
import MachOKit

@Suite
struct DyldCacheFileSwiftSectionTests {
    enum Error: Swift.Error {
        case notFound
    }

    let cache: DyldCache

    let machOFileInCache: MachOFile

    init() throws {
        // Cache
        let arch = "arm64e"
        let cachePath = "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_\(arch)"
        let cacheUrl = URL(fileURLWithPath: cachePath)
        self.cache = try! DyldCache(url: cacheUrl)
        self.machOFileInCache = cache.machOFiles().first(where: {
            $0.imagePath.contains("/SwiftUICore")
        })!
    }

    @Test func protocolsInFile() async throws {
        guard let protocols = machOFileInCache.swift.protocolDescriptors else {
            throw Error.notFound
        }
        for proto in protocols {
            print(try proto.name(in: machOFileInCache))
        }
    }
    
    @Test func typeContextDescriptorsInFile() async throws {
        do {
            try await Dump.dumpTypeContextDescriptors(in: machOFileInCache)
        } catch {
            print(error)
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
        if case let .type(type) = try RelativeIndirectPointer<ContextDescriptorWrapper?, SignedPointer<ContextDescriptorWrapper?>>(relativeOffset: 278655386).resolve(from: 1733619446, in: machOFileInCache) {
            print(try type.typeContextDescriptor.typeGenericContext(in: machOFileInCache))
        }
    }
}
