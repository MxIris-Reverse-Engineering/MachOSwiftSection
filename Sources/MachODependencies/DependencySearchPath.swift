import Foundation
import MachOKit

/// Where an offline (`MachOFile`) dependency locator may look for a dependency
/// binary. Cache-resident system frameworks (the stdlib, Foundation, the rest
/// of the OS) resolve through a dyld shared cache; a system tree that still
/// ships them as files (an iOS 26 or earlier simulator runtime's
/// `RuntimeRoot`) resolves through a system root; anything else — a sibling
/// framework reached through `@rpath`, a test helper next to the root binary —
/// has to be handed over as an explicit file, because `@rpath` /
/// `@loader_path` / `@executable_path` are not expanded.
public enum DependencySearchPath: Sendable, Hashable, Codable, CustomStringConvertible {
    /// An explicit on-disk path to a Mach-O (or fat) binary file.
    case machOFile(path: String)
    /// An explicit path to a dyld shared cache file.
    case dyldSharedCache(path: String)
    /// The running system's active dyld shared cache.
    case systemDyldSharedCache
    /// A directory an absolute load name is resolved under: the dependency
    /// `/System/Library/Frameworks/Foo.framework/Foo` is looked for at
    /// `<path>/System/Library/Frameworks/Foo.framework/Foo`. What a simulator
    /// runtime's `RuntimeRoot` is to its frameworks, before iOS 27 moved them
    /// into a cache. Load names that are not absolute never match here.
    case systemRoot(path: String)

    public var description: String {
        switch self {
        case .machOFile(let path):
            return "machOFile(\(path))"
        case .dyldSharedCache(let path):
            return "dyldSharedCache(\(path))"
        case .systemDyldSharedCache:
            return "systemDyldSharedCache"
        case .systemRoot(let path):
            return "systemRoot(\(path))"
        }
    }
}

extension DependencySearchPath {
    /// The search path a user-supplied path most plausibly means, by its
    /// shape: a directory is a ``systemRoot(path:)``, a file named like a
    /// main dyld cache (`dyld_shared_cache_arm64e`,
    /// `dyld_sim_shared_cache_arm64`) is a ``dyldSharedCache(path:)``, and
    /// any other file is a ``machOFile(path:)``. For a command-line option
    /// that takes all three without asking the user to spell the kind.
    public init(classifyingPath path: String) {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
            self = .systemRoot(path: path)
        } else if Self.isMainCacheFileName(URL(fileURLWithPath: path).lastPathComponent, architectureName: nil) {
            self = .dyldSharedCache(path: path)
        } else {
            self = .machOFile(path: path)
        }
    }

    /// The search paths a root binary's own location on disk implies.
    ///
    /// Two shapes are recognized, nearest ancestor first:
    ///
    /// 1. **A system tree carrying its own dyld cache** — an ancestor
    ///    directory with `System/Library/Caches/com.apple.dyld/` (iOS-family
    ///    and iOS 27+ simulator runtimes: `dyld_sim_shared_cache_arm64`) or
    ///    `System/Library/dyld/` (macOS) holding a main cache file for the
    ///    root's architecture. Each such cache becomes
    ///    ``dyldSharedCache(path:)``.
    /// 2. **A system tree carrying its frameworks as files** — the root's
    ///    on-disk path ends with its own install name
    ///    (`…/RuntimeRoot/System/Library/Frameworks/SwiftUI.framework/SwiftUI`
    ///    for `/System/Library/Frameworks/SwiftUI.framework/SwiftUI`), so the
    ///    prefix is a ``systemRoot(path:)``.
    ///
    /// The filesystem root itself is never a candidate: the host's own cache
    /// is ``systemDyldSharedCache``'s business. A binary that sits in neither
    /// shape — a third-party app under `/Applications`, a build product —
    /// infers nothing, and its caller adds the host cache or explicit paths.
    public static func inferred(forRoot root: MachOFile) -> [DependencySearchPath] {
        inferred(forRootFileAt: root.url, installName: root.imagePath, architectureName: architectureName(of: root.header.cpu))
    }

    /// ``inferred(forRoot:)`` over the three facts it reads off the file.
    /// `architectureName` (`arm64`, `arm64e`, `x86_64`) selects among the
    /// caches a directory carries; `nil` accepts every main cache file there.
    public static func inferred(forRootFileAt url: URL, installName: String, architectureName: String?) -> [DependencySearchPath] {
        let fileManager = FileManager.default
        var ancestor = url.standardizedFileURL.deletingLastPathComponent()
        while ancestor.path != "/", !ancestor.path.isEmpty {
            var caches: [DependencySearchPath] = []
            for cacheDirectory in Self.cacheDirectoriesUnderSystemTree {
                let directory = ancestor.appendingPathComponent(cacheDirectory)
                guard let entries = try? fileManager.contentsOfDirectory(atPath: directory.path) else { continue }
                for entry in entries.sorted() where Self.isMainCacheFileName(entry, architectureName: architectureName) {
                    caches.append(.dyldSharedCache(path: directory.appendingPathComponent(entry).path))
                }
            }
            if !caches.isEmpty { return caches }
            let parent = ancestor.deletingLastPathComponent()
            guard parent.path != ancestor.path else { break }
            ancestor = parent
        }
        if installName.hasPrefix("/"), url.path.hasSuffix(installName) {
            let systemRoot = String(url.path.dropLast(installName.count))
            if !systemRoot.isEmpty { return [.systemRoot(path: systemRoot)] }
        }
        return []
    }

    /// The directories, relative to a system tree's root, dyld caches live in.
    private static let cacheDirectoriesUnderSystemTree = [
        "System/Library/Caches/com.apple.dyld",
        "System/Library/dyld",
    ]

    /// Whether `fileName` is a *main* cache file (`dyld_shared_cache_arm64e`,
    /// `dyld_sim_shared_cache_arm64`) rather than a subcache (`.01`), a
    /// `.map` / `.atlas` / `.symbols` companion, or another architecture's.
    static func isMainCacheFileName(_ fileName: String, architectureName: String?) -> Bool {
        for prefix in ["dyld_shared_cache_", "dyld_sim_shared_cache_"] where fileName.hasPrefix(prefix) {
            let suffix = fileName.dropFirst(prefix.count)
            guard !suffix.isEmpty, suffix.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return false }
            guard let architectureName else { return true }
            return suffix == architectureName
        }
        return false
    }

    /// The architecture spelling a cache file name carries, for the root's CPU.
    static func architectureName(of cpu: CPU) -> String? {
        switch cpu.type {
        case .arm64:
            if case .arm64(.arm64e) = cpu.subtype { return "arm64e" }
            return "arm64"
        case .x86_64:
            return "x86_64"
        default:
            return nil
        }
    }
}

/// Why a search path contributed nothing. Recorded on the closure rather than
/// thrown: one unusable search path must not fail the whole resolution, and
/// this module sits below the event layer, so the host decides where the
/// degradation is reported.
public enum DependencySearchPathError: Error, Sendable, Equatable {
    /// The file loaded but yielded no Mach-O slice.
    case noMachOSlice(path: String)
    /// `FullDyldCache.host` returned `nil` — the platform exposes no shared
    /// cache file to this process.
    case systemDyldSharedCacheUnavailable
    /// A ``DependencySearchPath/systemRoot(path:)`` that is not a directory.
    case systemRootIsNotADirectory(path: String)
}

/// A search path that could not be opened, paired with the reason.
public struct DependencySearchPathLoadFailure: Sendable {
    public let searchPath: DependencySearchPath
    public let error: any Error

    public init(searchPath: DependencySearchPath, error: any Error) {
        self.searchPath = searchPath
        self.error = error
    }
}
