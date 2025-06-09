import Foundation
import MachOKit
import MachOFoundation

func loadMachOFile(options: MachOOptionGroup) throws -> MachOFile {
    if options.isDyldSharedCache || options.usesSystemDyldSharedCache {
        let url: URL
        if options.usesSystemDyldSharedCache {
            guard let currentCPUType = CPUType.current else { throw SwiftSectionCommandError.failedFetchFromSystemDyldSharedCache }
            switch currentCPUType {
            case .x86_64:
                url = URL(fileURLWithPath: "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_x86_64")
            case .arm64:
                url = URL(fileURLWithPath: "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e")
            default:
                throw SwiftSectionCommandError.failedFetchFromSystemDyldSharedCache
            }
        } else {
            url = try URL(fileURLWithPath: required(options.filePath, error: SwiftSectionCommandError.missingFilePath))
        }
        let dyldCache = try DyldCache(url: url)

        if let _ = options.cacheImagePath, let _ = options.cacheImageName {
            throw SwiftSectionCommandError.ambiguousCacheImageNameAndCacheImagePath
        } else if let cacheImageName = options.cacheImageName {
            return try required(dyldCache.machOFile(by: .name(cacheImageName)), error: SwiftSectionCommandError.imageNotFound)
        } else if let cacheImagePath = options.cacheImagePath {
            return try required(dyldCache.machOFile(by: .path(cacheImagePath)), error: SwiftSectionCommandError.imageNotFound)
        } else {
            throw SwiftSectionCommandError.missingCacheImageNameOrCacheImagePath
        }
    } else {
        let file = try MachOKit.loadFromFile(url: URL(fileURLWithPath: required(options.filePath, error: SwiftSectionCommandError.missingFilePath)))
        switch file {
        case let .machO(machOFile):
            return machOFile
        case let .fat(fatFile):
            return try required(fatFile.machOFiles().first { $0.header.cpu.subtype == options.architecture?.cpu ?? CPU.current?.subtype } ?? fatFile.machOFiles().first, error: SwiftSectionCommandError.invalidArchitecture)
        }
    }
}
