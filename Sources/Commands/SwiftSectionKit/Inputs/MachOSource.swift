import Foundation
import MachOKit
import MachOFoundation

/// An image inside a dyld shared cache, named one of the two ways a cache
/// indexes its images.
public enum DyldSharedCacheImage: Sendable, Hashable {
    /// The image's name, as in `SwiftUICore`.
    case name(String)
    /// The image's install path, as in `/usr/lib/libobjc.A.dylib`.
    case path(String)
}

/// Where a Mach-O image comes from.
public enum MachOSource: Sendable, Hashable {
    /// A thin or fat Mach-O file. `architecture` picks a fat binary's slice and
    /// is ignored for a thin one.
    case file(path: String, architecture: Architecture?)
    /// One image of the dyld shared cache at `cachePath`.
    case dyldSharedCache(cachePath: String, image: DyldSharedCacheImage)
    /// One image of the running system's dyld shared cache.
    case systemDyldSharedCache(image: DyldSharedCacheImage)
}

public enum MachOSourceError: Error, LocalizedError, Sendable, Equatable {
    /// A fat binary was given without an architecture to pick.
    case fatBinaryRequiresArchitecture(availableArchitectures: [String])
    /// The fat binary has no slice of this architecture.
    case architectureNotFound(Architecture)
    case dyldSharedCacheImageNotFound(DyldSharedCacheImage)
    /// The running system exposes no dyld shared cache to read (it takes
    /// macOS 11 or later).
    case systemDyldSharedCacheUnavailable

    public var errorDescription: String? {
        switch self {
        case .fatBinaryRequiresArchitecture(let availableArchitectures):
            "The file is a fat (universal) binary; an architecture must be chosen. Available architectures: \(availableArchitectures.joined(separator: ", "))"
        case .architectureNotFound(let architecture):
            "The file has no \(architecture.rawValue) slice."
        case .dyldSharedCacheImageNotFound(.name(let name)):
            "The dyld shared cache has no image named '\(name)'."
        case .dyldSharedCacheImageNotFound(.path(let path)):
            "The dyld shared cache has no image at '\(path)'."
        case .systemDyldSharedCacheUnavailable:
            "The running system's dyld shared cache cannot be read; it takes macOS 11 or later."
        }
    }
}

extension MachOSource {
    /// Loads the image this source names.
    ///
    /// The one loader every request shares, so that the fat-binary handling
    /// and the cache-image lookup cannot drift between them. A cache is read
    /// through `FullDyldCache`, which maps the subcaches too: an image whose
    /// sections live in a subcache read out of range through the main cache
    /// file alone.
    public func load() throws -> MachOFile {
        switch self {
        case .file(let path, let architecture):
            let file = try File.loadFromFile(url: URL(fileURLWithPath: path))
            switch file {
            case .machO(let machOFile):
                return machOFile
            case .fat(let fatFile):
                let machOFiles = try fatFile.machOFiles()
                guard let architecture else {
                    let availableArchitectures = machOFiles.map { machOFile -> String in
                        Architecture(cpu: machOFile.header.cpu)?.rawValue ?? machOFile.header.cpu.description
                    }
                    throw MachOSourceError.fatBinaryRequiresArchitecture(availableArchitectures: availableArchitectures)
                }
                guard let machOFile = machOFiles.first(where: { $0.header.cpu.subtype == architecture.cpuSubtype }) else {
                    throw MachOSourceError.architectureNotFound(architecture)
                }
                return machOFile
            }
        case .dyldSharedCache(let cachePath, let image):
            let dyldCache = try FullDyldCache(url: URL(fileURLWithPath: cachePath))
            return try image.machOFile(in: dyldCache)
        case .systemDyldSharedCache(let image):
            guard let dyldCache = FullDyldCache.cachedHost else {
                throw MachOSourceError.systemDyldSharedCacheUnavailable
            }
            return try image.machOFile(in: dyldCache)
        }
    }
}

extension DyldSharedCacheImage {
    func machOFile(in dyldCache: FullDyldCache) throws -> MachOFile {
        let machOFile: MachOFile? = switch self {
        case .name(let name):
            dyldCache.machOFile(by: .name(name))
        case .path(let path):
            dyldCache.machOFile(by: .path(path))
        }
        guard let machOFile else {
            throw MachOSourceError.dyldSharedCacheImageNotFound(self)
        }
        return machOFile
    }
}
