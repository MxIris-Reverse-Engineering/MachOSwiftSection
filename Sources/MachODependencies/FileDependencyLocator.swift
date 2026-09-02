import Foundation
import MachOKit
import MachOKitExtensions

/// Locates dependency `MachOFile`s across a set of search paths, for a root
/// binary read from disk (no running process to ask).
///
/// Two lookups, in order:
///
/// 1. **Exact install path.** A system framework's load name is the absolute
///    path the cache image also reports as its `imagePath`, so this is the
///    compiler's own answer whenever it applies.
/// 2. **Bare name, ranked.** Load names that are not absolute (`@rpath/…`) or
///    that spell a path the cache does not use fall back to the bare image
///    name. Leaf names are not unique inside a shared cache — a macOS cache
///    carries the Mac Catalyst build of SwiftUI under `/System/iOSSupport`
///    next to the native one, and iOS caches ship an `.axbundle` wearing the
///    framework's name — so candidates are ranked with
///    `DyldCacheImageSearchMode.matchRank(forImagePath:)` (canonical framework
///    binary, then plain dylib, then bundle; support-root builds demoted)
///    instead of taking whichever image the cache enumerates first.
///
/// Explicit files are indexed eagerly at construction. Each dyld shared cache
/// is indexed **once**, lazily, on the first lookup that reaches the caches —
/// one pass over `machOFiles()` rather than a fresh per-lookup scan, which
/// would cost `O(dependencies × cache size)` (measured at 21 s over a
/// 551-image closure before this was made one-shot).
public final class FileDependencyLocator: DependencyLocating, @unchecked Sendable {
    /// Search paths that could not be opened. Never thrown: one bad path must
    /// not fail the whole resolution.
    public let loadFailures: [DependencySearchPathLoadFailure]

    private let explicitFilesByInstallPath: [String: MachOFile]
    private let explicitFilesByBareName: [String: MachOFile]
    private let caches: [FullDyldCache]
    private let cacheIndexLock = NSLock()
    private var cacheIndex: CacheImageIndex?

    /// - Parameters:
    ///   - searchPaths: Consulted in order; the first explicit file registered
    ///     under a name wins, and the first cache image with the best rank wins.
    ///   - preferredCPU: For a fat explicit file, the slice to pick — the root
    ///     binary's own architecture, so a universal dependency is laid out
    ///     for the same target as the root. Matched on CPU type plus subtype
    ///     (so arm64 and arm64e are told apart), then on type alone, then the
    ///     first slice.
    public init(searchPaths: [DependencySearchPath], preferredCPU: CPU? = nil) {
        var explicitFilesByInstallPath: [String: MachOFile] = [:]
        var explicitFilesByBareName: [String: MachOFile] = [:]
        var caches: [FullDyldCache] = []
        var loadFailures: [DependencySearchPathLoadFailure] = []

        for searchPath in searchPaths {
            switch searchPath {
            case .machOFile(let path):
                do {
                    let slices = try File.loadFromFile(url: URL(fileURLWithPath: path)).machOFiles
                    guard let machOFile = Self.preferredSlice(among: slices, preferredCPU: preferredCPU) else {
                        throw DependencySearchPathError.noMachOSlice(path: path)
                    }
                    // A file's `imagePath` is its install name (`LC_ID_DYLIB`,
                    // typically `@rpath/…`), not its on-disk path, so both
                    // spellings are registered for the exact lookup, and the
                    // supplied path's bare name for the fallback.
                    for installPath in [path, machOFile.imagePath] where explicitFilesByInstallPath[installPath] == nil {
                        explicitFilesByInstallPath[installPath] = machOFile
                    }
                    let bareImageName = DependencyLoadName.bareImageName(of: path)
                    if !bareImageName.isEmpty, explicitFilesByBareName[bareImageName] == nil {
                        explicitFilesByBareName[bareImageName] = machOFile
                    }
                } catch {
                    loadFailures.append(.init(searchPath: searchPath, error: error))
                }
            case .dyldSharedCache(let path):
                do {
                    caches.append(try FullDyldCache(url: URL(fileURLWithPath: path)))
                } catch {
                    loadFailures.append(.init(searchPath: searchPath, error: error))
                }
            case .systemDyldSharedCache:
                if let hostCache = FullDyldCache.host {
                    caches.append(hostCache)
                } else {
                    loadFailures.append(.init(searchPath: searchPath, error: DependencySearchPathError.systemDyldSharedCacheUnavailable))
                }
            }
        }

        self.explicitFilesByInstallPath = explicitFilesByInstallPath
        self.explicitFilesByBareName = explicitFilesByBareName
        self.caches = caches
        self.loadFailures = loadFailures
    }

    public func locate(loadName: String) -> MachOFile? {
        if let explicitFile = explicitFilesByInstallPath[loadName] {
            return explicitFile
        }
        let bareImageName = DependencyLoadName.bareImageName(of: loadName)
        guard !bareImageName.isEmpty else { return nil }
        if let explicitFile = explicitFilesByBareName[bareImageName] {
            return explicitFile
        }
        guard !caches.isEmpty else { return nil }
        let index = builtCacheIndex()
        if let cacheImage = index.imagesByInstallPath[loadName] {
            return cacheImage
        }
        return index.bestImagesByBareName[bareImageName]?.machOFile
    }

    /// Compared on `CPU.type` and `CPU.subtype` rather than `CPU ==`: the
    /// struct's synthesized equality includes the raw subtype's capability
    /// bits (the arm64e pointer-authentication ABI version and versioned-ABI
    /// flag under `CPU_SUBTYPE_MASK`), so a versioned-ABI arm64e slice would
    /// compare unequal to a plain arm64e root and silently fall through to
    /// the type-only match — the arm64 / arm64e confusion this exists to
    /// avoid. `subtype` masks those bits.
    private static func preferredSlice(among slices: [MachOFile], preferredCPU: CPU?) -> MachOFile? {
        guard let preferredCPU else { return slices.first }
        if let exactSlice = slices.first(where: { $0.header.cpu.type == preferredCPU.type && $0.header.cpu.subtype == preferredCPU.subtype }) {
            return exactSlice
        }
        if let sameTypeSlice = slices.first(where: { $0.header.cpu.type == preferredCPU.type }) {
            return sameTypeSlice
        }
        return slices.first
    }

    // MARK: - One-shot cache index

    private struct CacheImageIndex {
        var imagesByInstallPath: [String: MachOFile] = [:]
        var bestImagesByBareName: [String: (rank: Int, machOFile: MachOFile)] = [:]
    }

    /// Rank given to a cache image whose path the `DyldCacheImageSearchMode`
    /// name rule does not recognize under its bare name (a multi-dotted leaf
    /// such as `libc++.1.dylib`, whose `deletingPathExtension` form is not the
    /// bare name). It still resolves — every entry under a key legitimately
    /// carries that bare name — it just loses to any recognized shape.
    private static let unrankedShapeRank = Int.max

    private func builtCacheIndex() -> CacheImageIndex {
        cacheIndexLock.lock()
        defer { cacheIndexLock.unlock() }
        if let cacheIndex { return cacheIndex }

        var index = CacheImageIndex()
        for cache in caches {
            for machOFile in cache.machOFiles() {
                let installPath = machOFile.imagePath
                if index.imagesByInstallPath[installPath] == nil {
                    index.imagesByInstallPath[installPath] = machOFile
                }
                let bareImageName = DependencyLoadName.bareImageName(of: installPath)
                guard !bareImageName.isEmpty else { continue }
                let rank = DyldCacheImageSearchMode.name(bareImageName).matchRank(forImagePath: installPath) ?? Self.unrankedShapeRank
                if let existing = index.bestImagesByBareName[bareImageName], existing.rank <= rank {
                    continue
                }
                index.bestImagesByBareName[bareImageName] = (rank, machOFile)
            }
        }
        cacheIndex = index
        return index
    }
}
