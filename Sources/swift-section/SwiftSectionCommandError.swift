import Foundation

enum SwiftSectionCommandError: LocalizedError {
    case missingFilePath
    case ambiguousCacheImageNameAndCacheImagePath
    case missingCacheImageNameOrCacheImagePath
    case imageNotFound
    case invalidArchitecture
    case failedFetchFromSystemDyldSharedCache

    var errorDescription: String? {
        switch self {
        case .missingFilePath:
            "The filePath is required when uses-system-dyld-shared-cache is false. Please provide a valid Mach-O file path."
        case .ambiguousCacheImageNameAndCacheImagePath:
            "Both cacheImageName and cacheImagePath are provided, but only one should be specified."
        case .missingCacheImageNameOrCacheImagePath:
            "Either cacheImageName or cacheImagePath must be provided when dyldSharedCache is true."
        case .imageNotFound:
            "The specified image was not found in the dyld shared cache."
        case .invalidArchitecture:
            "The specified architecture is not found or supported."
        case .failedFetchFromSystemDyldSharedCache:
            "Failed to fetch the Mach-O file from the current system dyld shared cache. Please ensure the cache is accessible."
        }
    }
}
