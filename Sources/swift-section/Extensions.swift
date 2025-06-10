import Foundation
import MachOKit
import MachOFoundation
import UniformTypeIdentifiers

func loadMachOFile(options: MachOOptionGroup) throws -> MachOFile {
    if options.isDyldSharedCache || options.usesSystemDyldSharedCache {
        let url: URL
        if options.usesSystemDyldSharedCache {
            guard let currentCPUType = CPUType.current else { throw SwiftSectionCommandError.failedFetchFromSystemDyldSharedCache }
            if #available(macOS 11.0, *) {
                let path: String
                switch currentCPUType {
                case .x86_64:
                    path = "/System/Library/dyld/dyld_shared_cache_x86_64"
                case .arm64:
                    path = "/System/Library/dyld/dyld_shared_cache_arm64e"
                default:
                    throw SwiftSectionCommandError.failedFetchFromSystemDyldSharedCache
                }

                let prefix: String
                if #available(macOS 13.0, *) {
                    prefix = "/System/Volumes/Preboot/Cryptexes/OS"
                } else {
                    prefix = "/System/Cryptexes/OS"
                }

                url = URL(fileURLWithPath: prefix + path)

            } else {
                throw SwiftSectionCommandError.unsupportedSystemVersionForDyldSharedCache
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
        var url = try URL(fileURLWithPath: required(options.filePath, error: SwiftSectionCommandError.missingFilePath))

        if url.contentTypeConformsToBundle(), let executableURL = Bundle(url: url)?.executableURL {
            url = executableURL
        }

        let file = try MachOKit.loadFromFile(url: url)
        switch file {
        case .machO(let machOFile):
            return machOFile
        case .fat(let fatFile):
            return try required(fatFile.machOFiles().first { $0.header.cpu.subtype == options.architecture?.cpu ?? CPU.current?.subtype } ?? fatFile.machOFiles().first, error: SwiftSectionCommandError.invalidArchitecture)
        }
    }
}

extension URL {
    func contentTypeConformsToBundle() -> Bool {
        if #available(macOS 11.0, *) {
            return (try? resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .bundle)) ?? false
        } else {
            return (try? resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier).map { UTTypeConformsTo($0 as CFString, kUTTypeBundle) } ?? false
        }
    }
}
